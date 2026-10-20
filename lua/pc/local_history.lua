-- Local History like IDEA: every save of a file is kept, independent of git, for 5 days.
--   <leader>vH      history of this file: list of versions with a diff against the current text,
--                   Enter = side-by-side diff in a new tab (q closes), Ctrl+R = revert to that version
--                   (undo brings the current text back)
--   :LocalHistoryDeleted   files deleted from this project that are still in the history, Enter restores
--   <leader>vE / :RecentChanges   Recent Changes (IDEA's Alt+Shift+C): every saved change in this
--                   project, newest first, with what it changed; Enter = the file before that
--                   change against now (side by side), Ctrl+R = put the file back to before it
-- Versions are in stdpath('data')/local_history/<path with / as %>/<time>; the version from before
-- the first save and changes made outside nvim are kept too.

local M = {}

local ROOT = vim.fn.stdpath 'data' .. '/local_history'
local KEEP_DAYS = 5
local MAX_SIZE = 1024 * 1024

local function dir_of(path)
  return ROOT .. '/' .. path:gsub('/', '%%')
end

local function path_of(dir)
  return (vim.fs.basename(dir):gsub('%%', '/'))
end

-- Versions of a file, newest first: { file, time }
local function versions(path)
  local list = {}
  for name, kind in vim.fs.dir(dir_of(path)) do
    local time = tonumber(name:match '^(%d+)')
    if kind == 'file' and time then
      table.insert(list, { file = dir_of(path) .. '/' .. name, time = time, name = name })
    end
  end
  table.sort(list, function(a, b)
    return a.name > b.name
  end)
  return list
end

local function read(file)
  local f = io.open(file, 'rb')
  if not f then
    return nil
  end
  local text = f:read '*a'
  f:close()
  return text
end

local function tracked(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  return vim.bo[buf].buftype == '' and path ~= '' and not path:find '^%w+://' and path or nil
end

-- Saves the file's text on disk as a new version, unless it is the same as the last one
local function snapshot(path)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= 'file' or stat.size > MAX_SIZE then
    return
  end
  local text = read(path)
  local last = versions(path)[1]
  if not text or (last and read(last.file) == text) then
    return
  end
  vim.fn.mkdir(dir_of(path), 'p')
  local sec, usec = vim.uv.gettimeofday()
  local f = io.open(('%s/%d.%06d'):format(dir_of(path), sec, usec), 'wb')
  if f then
    f:write(text)
    f:close()
  end
end

local function cleanup()
  local limit = os.time() - KEEP_DAYS * 24 * 3600
  for dir, kind in vim.fs.dir(ROOT) do
    if kind == 'directory' then
      local left = 0
      for name in vim.fs.dir(ROOT .. '/' .. dir) do
        if (tonumber(name:match '^(%d+)') or 0) < limit then
          os.remove(ROOT .. '/' .. dir .. '/' .. name)
        else
          left = left + 1
        end
      end
      if left == 0 then
        vim.uv.fs_rmdir(ROOT .. '/' .. dir)
      end
    end
  end
end

local function ago(time)
  local s = os.time() - time
  if s < 60 then
    return 'just now'
  elseif s < 3600 then
    return ('%d min ago'):format(s / 60)
  elseif s < 86400 then
    return ('%d h ago'):format(s / 3600)
  end
  return ('%d days ago'):format(s / 86400)
end

local function lines_of(text)
  local lines = vim.split(text, '\n', { plain = true })
  if lines[#lines] == '' then
    table.remove(lines)
  end
  return lines
end

-- Side-by-side diff: the version (left, read-only) against the file (right)
local function open_diff(path, v)
  vim.cmd('tabedit ' .. vim.fn.fnameescape(path))
  local ft = vim.bo.filetype
  vim.cmd 'diffthis'
  vim.cmd 'leftabove vnew'
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_of(read(v.file) or ''))
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = ft
  pcall(vim.api.nvim_buf_set_name, buf, ('%s @ %s'):format(vim.fs.basename(path), os.date('%Y-%m-%d %H:%M:%S', v.time)))
  vim.cmd 'diffthis'
  for _, b in ipairs { buf, vim.fn.bufnr(path) } do
    vim.keymap.set('n', 'q', function()
      vim.cmd 'diffoff!'
      vim.cmd 'tabclose'
    end, { buffer = b, desc = 'Close Local History diff' })
  end
  -- the q on the file itself goes away with the tab
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      pcall(vim.keymap.del, 'n', 'q', { buffer = vim.fn.bufnr(path) })
    end,
  })
end

local function revert(path, v)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_of(read(v.file) or ''))
  vim.notify(('Reverted to the version from %s (u undoes, :w saves)'):format(os.date('%H:%M:%S', v.time)))
end

function M.show(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local path = tracked(buf)
  if not path then
    return vim.notify('Local History: not a file', vim.log.levels.WARN)
  end
  local list = versions(path)
  if #list == 0 then
    return vim.notify('Local History: no saved versions of this file yet', vim.log.levels.INFO)
  end
  local current = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n'
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local previewers = require 'telescope.previewers'
  local actions = require 'telescope.actions'
  local state = require 'telescope.actions.state'
  pickers
    .new({}, {
      prompt_title = 'Local History: ' .. vim.fs.basename(path),
      finder = finders.new_table {
        results = list,
        entry_maker = function(v)
          local diff = vim.diff(read(v.file) or '', current, { result_type = 'indices' })
          local added, removed = 0, 0
          for _, h in ipairs(diff) do
            removed, added = removed + h[2], added + h[4]
          end
          local summary = #diff == 0 and 'same as now' or ('+%d -%d'):format(added, removed)
          local display = ('%s  %-12s %s'):format(os.date('%Y-%m-%d %H:%M:%S', v.time), ago(v.time), summary)
          return { value = v, display = display, ordinal = display }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      previewer = previewers.new_buffer_previewer {
        title = 'Changes since this version',
        define_preview = function(self, entry)
          local diff = vim.diff(read(entry.value.file) or '', current, { ctxlen = 3 })
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(diff ~= '' and diff or 'No changes', '\n'))
          vim.bo[self.state.bufnr].filetype = 'diff'
        end,
      },
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            open_diff(path, entry.value)
          end
        end)
        map({ 'i', 'n' }, '<C-r>', function()
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            revert(path, entry.value)
          end
        end, { desc = 'Revert to this version' })
        return true
      end,
    })
    :find()
end

--- Recent Changes: the saves of all files of this project, newest first
function M.recent()
  local cwd = vim.fn.getcwd() .. '/'
  local changes = {}
  for dir, kind in vim.fs.dir(ROOT) do
    local path = path_of(dir)
    if kind == 'directory' and vim.startswith(path, cwd) then
      local list = versions(path)
      -- each version but the oldest is a change made to the one before it
      for i = 1, #list - 1 do
        table.insert(changes, { path = path, version = list[i], before = list[i + 1] })
      end
    end
  end
  if #changes == 0 then
    return vim.notify('Local History: no changes saved in this project yet', vim.log.levels.INFO)
  end
  table.sort(changes, function(a, b)
    return a.version.name > b.version.name
  end)
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local previewers = require 'telescope.previewers'
  local actions = require 'telescope.actions'
  local state = require 'telescope.actions.state'
  local function diff_of(c, opts)
    return vim.diff(read(c.before.file) or '', read(c.version.file) or '', opts)
  end
  pickers
    .new({}, {
      prompt_title = 'Recent Changes',
      finder = finders.new_table {
        results = vim.list_slice(changes, 1, 500),
        entry_maker = function(c)
          local added, removed = 0, 0
          for _, h in ipairs(diff_of(c, { result_type = 'indices' })) do
            removed, added = removed + h[2], added + h[4]
          end
          local display = ('%s  %-12s %-8s %s'):format(os.date('%m-%d %H:%M:%S', c.version.time), ago(c.version.time), ('+%d -%d'):format(added, removed), c.path:sub(#cwd + 1))
          return { value = c, display = display, ordinal = display }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      previewer = previewers.new_buffer_previewer {
        title = 'What this save changed',
        define_preview = function(self, entry)
          local diff = diff_of(entry.value, { ctxlen = 3 })
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(diff ~= '' and diff or 'No changes', '\n'))
          vim.bo[self.state.bufnr].filetype = 'diff'
        end,
      },
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not entry then
            return
          end
          if not vim.uv.fs_stat(entry.value.path) then
            return vim.notify('Deleted since: :LocalHistoryDeleted restores it', vim.log.levels.WARN)
          end
          open_diff(entry.value.path, entry.value.before)
        end)
        map({ 'i', 'n' }, '<C-r>', function()
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            -- shown, so the reverted text can be checked (u undoes, :w saves)
            vim.cmd.edit(vim.fn.fnameescape(entry.value.path))
            revert(entry.value.path, entry.value.before)
          end
        end, { desc = 'Revert the file to before this change' })
        return true
      end,
    })
    :find()
end

function M.deleted()
  local cwd = vim.fn.getcwd() .. '/'
  local files = {}
  for dir, kind in vim.fs.dir(ROOT) do
    local path = path_of(dir)
    if kind == 'directory' and vim.startswith(path, cwd) and not vim.uv.fs_stat(path) then
      local last = versions(path)[1]
      if last then
        table.insert(files, { path = path, version = last })
      end
    end
  end
  if #files == 0 then
    return vim.notify('Local History: no deleted files in this project', vim.log.levels.INFO)
  end
  vim.ui.select(files, {
    prompt = 'Restore deleted file',
    format_item = function(f)
      return ('%s  (%s)'):format(f.path:sub(#cwd + 1), ago(f.version.time))
    end,
  }, function(f)
    if not f then
      return
    end
    vim.fn.mkdir(vim.fs.dirname(f.path), 'p')
    vim.fn.writefile(vim.fn.readfile(f.version.file, 'b'), f.path, 'b')
    vim.cmd('edit ' .. vim.fn.fnameescape(f.path))
  end)
end

local group = vim.api.nvim_create_augroup('pc-local-history', { clear = true })
-- the version on disk before a save (the first one, or changed outside nvim since the last
-- version: checkout, another editor…), then every saved version
vim.api.nvim_create_autocmd('BufWritePre', {
  group = group,
  callback = function(event)
    local path = tracked(event.buf)
    if path then
      snapshot(path)
    end
  end,
})
vim.api.nvim_create_autocmd({ 'BufWritePost', 'FileChangedShellPost' }, {
  group = group,
  callback = function(event)
    local path = tracked(event.buf)
    if path then
      snapshot(path)
    end
  end,
})
vim.api.nvim_create_autocmd('VimEnter', {
  group = group,
  callback = function()
    vim.defer_fn(cleanup, 3000)
  end,
})

vim.keymap.set('n', '<leader>vH', M.show, { desc = 'VCS: Local [H]istory of this file' })
vim.api.nvim_create_user_command('LocalHistory', function()
  M.show()
end, { desc = 'Local History of this file' })
vim.api.nvim_create_user_command('LocalHistoryDeleted', M.deleted, { desc = 'Restore a deleted file from Local History' })
vim.keymap.set('n', '<leader>vE', M.recent, { desc = 'VCS: Recent Changes (Local History of the project)' })
vim.api.nvim_create_user_command('RecentChanges', M.recent, { desc = 'Recent Changes (Local History of the project)' })

return M
