-- Show Bookmarks (Shift+F11 / Cmd+2), like IDEA's Bookmarks: the list, with the whole description
-- above the code in the preview (a long one was cut off in the list), and in the list
--   Delete / Shift+Delete / Ctrl+D (dd, x in Normal mode)   remove the bookmark, the list stays
--   F2 / Ctrl+E / Cmd+F11                                   edit its description
--   right click                                             Open / Edit Description / Delete
-- (the log: Delete, Shift+Delete, a right click did nothing, then each bookmark was opened and
-- toggled off with Ctrl+F11 one by one)

local M = {}

local function bm()
  return require 'bookmarks.actions', require('bookmarks.config').config
end

local function entries()
  local actions, config = bm()
  actions.sync_all()
  local list = {}
  for file, marks in pairs(config.cache.data) do
    for lnum, mark in pairs(marks) do
      table.insert(list, { filename = file, lnum = tonumber(lnum), desc = mark.a or '', line = vim.trim(mark.m or '') })
    end
  end
  table.sort(list, function(a, b)
    return a.filename == b.filename and a.lnum < b.lnum or a.filename < b.filename
  end)
  return list
end

local function finder()
  local display = require('telescope.pickers.entry_display').create {
    separator = ' ▏',
    items = { { width = 5 }, { width = 36 }, { remaining = true } },
  }
  return require('telescope.finders').new_table {
    results = entries(),
    entry_maker = function(item)
      return {
        value = item,
        display = function(entry)
          local v = entry.value
          return display {
            { v.lnum, 'TelescopeResultsLineNr' },
            vim.fn.fnamemodify(v.filename, ':t'),
            v.desc ~= '' and v.desc or { v.line, 'Comment' },
          }
        end,
        ordinal = item.filename .. ' ' .. item.desc .. ' ' .. item.line,
        filename = item.filename,
        lnum = item.lnum,
        col = 1,
      }
    end,
  }
end

-- the code around the bookmark, with its whole description wrapped above it
local function previewer()
  local previewers = require 'telescope.previewers'
  local ns = vim.api.nvim_create_namespace 'pc-bookmark-preview'
  return previewers.new_buffer_previewer {
    title = 'Bookmark',
    define_preview = function(self, entry)
      local v = entry.value
      local ok, lines = pcall(vim.fn.readfile, v.filename)
      lines = ok and lines or { '(file not readable)' }
      local buf = self.state.bufnr
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      local ft = vim.filetype.match { filename = v.filename }
      if ft then
        require('telescope.previewers.utils').highlighter(buf, ft)
      end
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      local row = math.min(math.max(v.lnum, 1), #lines) - 1
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = 'Visual' })
      if v.desc ~= '' then
        local width = math.max(20, vim.api.nvim_win_get_width(self.state.winid) - 4)
        local virt = {}
        for _, part in ipairs(vim.split(v.desc, '\n')) do
          while #part > width do
            table.insert(virt, { { '  ' .. part:sub(1, width), 'DiagnosticInfo' } })
            part = part:sub(width + 1)
          end
          table.insert(virt, { { '  ' .. part, 'DiagnosticInfo' } })
        end
        vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { virt_lines = virt, virt_lines_above = true })
      end
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(self.state.winid) then
          pcall(vim.api.nvim_win_set_cursor, self.state.winid, { row + 1, 0 })
          vim.api.nvim_win_call(self.state.winid, function()
            vim.cmd 'normal! zz'
          end)
        end
      end)
    end,
  }
end

local function selected()
  local entry = require('telescope.actions.state').get_selected_entry()
  return entry and entry.value
end

local function refresh(prompt)
  local picker = require('telescope.actions.state').get_current_picker(prompt)
  picker:refresh(finder(), { reset_prompt = false })
end

local function delete(prompt)
  local v = selected()
  if not v then
    return
  end
  local actions = bm()
  actions.bookmark_del(v.filename, v.lnum)
  actions.saveBookmarks()
  refresh(prompt)
end

-- the plugin edits the description of the bookmark under the cursor: its own Edit, run on that
-- line of the file (loaded if needed) in a hidden window; the box for the text opens after that
-- window is gone (inside it, the box was not focused and typing went into the file), then the
-- list again
local function edit(prompt)
  local v = selected()
  if not v then
    return
  end
  require('telescope.actions').close(prompt)
  local buf = vim.fn.bufadd(v.filename)
  vim.fn.bufload(buf)
  local input, asked = vim.ui.input, nil
  vim.ui.input = function(opts, on_confirm)
    asked = { opts, on_confirm }
  end
  local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 1, height = 1, hide = true, noautocmd = true })
  local ok, err = pcall(vim.api.nvim_win_call, win, function()
    vim.api.nvim_win_set_cursor(0, { v.lnum, 0 })
    bm().bookmark_ann()
  end)
  pcall(vim.api.nvim_win_close, win, true)
  vim.ui.input = input
  if not ok or not asked then
    return vim.notify('Bookmark: ' .. tostring(err or 'no description box'), vim.log.levels.WARN)
  end
  local opts, on_confirm = asked[1], asked[2]
  opts.prompt = 'Bookmark description: '
  vim.schedule(function()
    input(opts, function(answer)
      on_confirm(answer)
      bm().saveBookmarks()
      vim.schedule(M.open)
    end)
  end)
end

local function menu(prompt)
  local items = { 'Open', 'Edit Description', 'Delete' }
  vim.ui.select(items, { prompt = 'Bookmark' }, function(choice)
    if choice == 'Open' then
      require('telescope.actions').select_default(prompt)
    elseif choice == 'Edit Description' then
      edit(prompt)
    elseif choice == 'Delete' then
      delete(prompt)
    end
  end)
end

function M.open()
  require('lazy').load { plugins = { 'bookmarks.nvim' } }
  local conf = require('telescope.config').values
  bm().prune_dead(function()
    require('telescope.pickers')
      .new({}, {
        prompt_title = 'Bookmarks  ·  Del delete  ·  F2 edit description  ·  right click: menu',
        finder = finder(),
        sorter = conf.generic_sorter {},
        previewer = previewer(),
        attach_mappings = function(_, map)
          for _, key in ipairs { '<Del>', '<S-Del>', '<C-d>' } do
            map({ 'i', 'n' }, key, delete)
          end
          map('n', 'dd', delete)
          map('n', 'x', delete)
          for _, key in ipairs { '<F2>', '<C-e>', '<M-F11>', '<F59>' } do
            map({ 'i', 'n' }, key, edit)
          end
          map({ 'i', 'n' }, '<RightMouse>', menu)
          return true
        end,
      })
      :find()
  end)
end

return M
