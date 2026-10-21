-- Search Everywhere (double Shift in IDEA; a terminal never sends Shift alone, so: ␣␣).
-- One window with IDEA's tabs, Tab / Shift+Tab switch between them and keep what you typed:
--   All       nothing typed: recent files; typing: classes, files, symbols and actions
--   Classes   project types (workspace symbols)
--   Files     project files
--   Symbols   methods, functions, fields… of the project
--   Actions   the actions of this config (as Alt+Shift+A)
--   Text      text in the project (live grep)
-- Alt+M: file mask for Files / All / Text (*.java, !*Test.java; pc.file_mask), as IDEA's filter.

local M = {}

local SCOPES = { 'All', 'Classes', 'Files', 'Symbols', 'Actions', 'Text' }
local CLASS_KINDS = { Class = true, Interface = true, Enum = true, Struct = true, Module = true }
local SYMBOL_KINDS = { Method = true, Function = true, Field = true, Constant = true, Constructor = true, Property = true, Variable = true }
local TAGS = { recent = 'Recent', file = 'File', class = 'Class', symbol = 'Symbol', action = 'Action' }

local function project_root()
  return vim.fn.getcwd()
end

local function in_project(file, root)
  return vim.startswith(file, root .. '/')
    and not file:match '/%.venv/'
    and not file:match '/site%-packages/'
    and not file:match '/node_modules/'
    and not file:match '/target/'
    and not file:match '/build/'
end

-- a buffer whose language server can search the workspace (current one first)
local function symbol_buffer()
  local method = 'workspace/symbol'
  if #vim.lsp.get_clients { bufnr = 0, method = method } > 0 then
    return vim.api.nvim_get_current_buf()
  end
  for _, client in ipairs(vim.lsp.get_clients { method = method }) do
    local buf = next(client.attached_buffers)
    if buf then
      return buf
    end
  end
end

local function project_files(root)
  local out = vim.system({ 'rg', '--files', '--hidden', '--glob', '!.git' }, { text = true, cwd = root }):wait()
  return vim.split(out.stdout or '', '\n', { trimempty = true })
end

-- files of this session (most recently used first), then older ones
local function recent_files(root)
  local list, seen = {}, { [vim.api.nvim_buf_get_name(0)] = true }
  local buffers = vim.fn.getbufinfo { buflisted = 1 }
  table.sort(buffers, function(a, b)
    return a.lastused > b.lastused
  end)
  local candidates = vim.tbl_map(function(b)
    return b.name
  end, buffers)
  vim.list_extend(candidates, vim.v.oldfiles)
  for _, file in ipairs(candidates) do
    local stat = not seen[file] and in_project(file, root) and vim.uv.fs_stat(file)
    if stat and stat.type == 'file' then
      seen[file] = true
      table.insert(list, file)
      if #list == 30 then
        break
      end
    end
  end
  return list
end

-- LSP workspace symbols for `query` (inside the picker's async context)
local function lsp_symbols(buf, query, kinds, root)
  if not buf or query == '' then
    return {}
  end
  local channel = require('plenary.async.control').channel
  local tx, rx = channel.oneshot()
  vim.lsp.buf_request_all(buf, 'workspace/symbol', { query = query }, tx)
  local items = {}
  for client_id, response in pairs(rx() or {}) do
    local client = vim.lsp.get_client_by_id(client_id)
    if response.result and client then
      for _, item in ipairs(vim.lsp.util.symbols_to_items(response.result, buf, client.offset_encoding)) do
        if kinds[item.kind] and in_project(item.filename, root) then
          table.insert(items, item)
        end
      end
    end
  end
  return items
end

local function open(scope, default_text)
  if scope == 'Text' then
    return require('pc.find_in_path').open {
      prompt_title = 'Search Everywhere · Tab: next tab',
      default_text = default_text,
      attach_mappings = function(prompt_bufnr, map)
        local function switch(step)
          return function()
            local text = require('telescope.actions.state').get_current_line()
            require('telescope.actions').close(prompt_bufnr)
            open(SCOPES[(#SCOPES + 5 + step) % #SCOPES + 1], text)
          end
        end
        map({ 'i', 'n' }, '<Tab>', switch(1))
        map({ 'i', 'n' }, '<S-Tab>', switch(-1))
        return true
      end,
    }
  end

  local file_mask = require 'pc.file_mask'
  local root = project_root()
  local rel = function(f)
    return vim.fs.relpath(root, f) or f
  end
  local files = (scope == 'All' or scope == 'Files') and project_files(root) or {}
  local recent = scope == 'All' and recent_files(root) or {}
  local actions = (scope == 'All' or scope == 'Actions') and require('pc.actions').list() or {}
  local buf = symbol_buffer()

  local function results(prompt)
    local out = {}
    if scope == 'All' and prompt == '' then
      for _, f in ipairs(recent) do
        table.insert(out, { kind = 'recent', name = vim.fs.basename(f), detail = rel(f), file = f })
      end
      return out
    end
    if scope == 'All' or scope == 'Classes' then
      for _, item in ipairs(lsp_symbols(buf, prompt, CLASS_KINDS, root)) do
        table.insert(out, { kind = 'class', name = item.text:gsub('^%[%w+%] ', ''), detail = rel(item.filename), item = item })
      end
    end
    if scope == 'All' or scope == 'Files' then
      for _, f in ipairs(vim.tbl_filter(file_mask.matches, files)) do
        table.insert(out, { kind = 'file', name = vim.fs.basename(f), detail = f, file = root .. '/' .. f })
      end
    end
    if scope == 'All' or scope == 'Symbols' then
      for _, item in ipairs(lsp_symbols(buf, prompt, SYMBOL_KINDS, root)) do
        table.insert(out, { kind = 'symbol', name = item.text:gsub('^%[%w+%] ', ''), detail = rel(item.filename) .. ':' .. item.lnum, item = item })
      end
    end
    if scope == 'All' or scope == 'Actions' then
      -- actions match on words of their name, not loose fuzzy letters
      local query = prompt:lower()
      for _, a in ipairs(actions) do
        if query == '' or (a.name:lower() .. ' ' .. a.keys:lower()):find(query, 1, true) then
          table.insert(out, { kind = 'action', name = a.name, detail = a.keys, action = a })
        end
      end
    end
    return out
  end

  local displayer = require('telescope.pickers.entry_display').create {
    separator = ' ',
    items = { { width = 7 }, { width = 0.45 }, { remaining = true } },
  }
  local tabs = {}
  for _, s in ipairs(SCOPES) do
    table.insert(tabs, s == scope and ('[' .. s .. ']') or s)
  end

  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Search Everywhere · ' .. table.concat(tabs, ' ') .. file_mask.label() .. ' · Tab: next · Alt+M: mask',
      default_text = default_text,
      finder = require('telescope.finders').new_dynamic {
        fn = results,
        entry_maker = function(e)
          return {
            value = e,
            ordinal = e.name .. ' ' .. (e.kind == 'file' and e.detail or ''),
            display = function()
              return displayer { { TAGS[e.kind], 'Comment' }, e.name, { e.detail or '', 'Comment' } }
            end,
          }
        end,
      },
      sorter = (function()
        -- equally good matches: classes first, then files, symbols, actions (as in IDEA)
        local sorter = require('telescope.config').values.generic_sorter {}
        local score = sorter.scoring_function
        local weight = { class = 0.6, recent = 0.7, file = 0.8, symbol = 0.9, action = 1 }
        sorter.scoring_function = function(self, prompt, line, entry, ...)
          if prompt == '' and entry then
            return entry.index -- nothing typed: keep the most-recent-first order
          end
          local s = score(self, prompt, line, entry, ...)
          if s < 0 or not entry then
            return s
          end
          return s * (weight[entry.value.kind] or 1)
        end
        return sorter
      end)(),
      attach_mappings = function(prompt_bufnr, map)
        local actions_t, state = require 'telescope.actions', require 'telescope.actions.state'
        actions_t.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions_t.close(prompt_bufnr)
          if not entry then
            return
          end
          local e = entry.value
          if e.action then
            require('pc.actions').run(e.action)
          elseif e.item then
            vim.cmd.edit(vim.fn.fnameescape(e.item.filename))
            vim.api.nvim_win_set_cursor(0, { e.item.lnum, math.max(e.item.col - 1, 0) })
          else
            vim.cmd.edit(vim.fn.fnameescape(e.file))
          end
        end)
        local function switch(step)
          return function()
            local text = state.get_current_line()
            actions_t.close(prompt_bufnr)
            local index
            for i, s in ipairs(SCOPES) do
              if s == scope then
                index = i
              end
            end
            open(SCOPES[(index - 1 + step) % #SCOPES + 1], text)
          end
        end
        map({ 'i', 'n' }, '<Tab>', switch(1))
        map({ 'i', 'n' }, '<S-Tab>', switch(-1))
        map({ 'i', 'n' }, '<M-m>', function()
          local text = state.get_current_line()
          actions_t.close(prompt_bufnr)
          file_mask.ask(function()
            open(scope, text)
          end)
        end)
        return true
      end,
    })
    :find()
end

function M.open(scope)
  open(scope or 'All')
end

vim.keymap.set('n', '<leader><leader>', M.open, { desc = 'Search Everywhere' })

return M
