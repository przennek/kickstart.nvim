-- Files changed on disk show up at once, like in IDEA: an LLM agent, git or a script in the
-- terminal (or another tmux pane) edits a file you have open, and the buffer follows.
--   unchanged buffers are reloaded silently (the old text stays in Local History, undo works)
--   a buffer with your own unsaved edits is left alone with a warning (:e! takes the file's
--   version, :w keeps yours)
-- Directories of open files are watched (editors and agents often save through a new file and
-- a rename, which a watcher on the file itself would miss); returning from the terminal,
-- entering a window and focus coming back check as well.
-- A file deleted on disk (an agent, git, a script) is closed like IDEA closes its tab, the
-- windows stay; with your unsaved edits it stays open with a warning (:w writes it back).
-- Neovim's own "E211: File … no longer available" no longer shows.

local M = {}

local watchers = {} -- directory -> uv fs_event handle
local pending = {} -- buf -> true while a check is scheduled
local warned = {} -- buf -> true once warned about a conflict

-- modification time of the file as last loaded / written, to the nanosecond
local function mtime(name)
  local stat = vim.uv.fs_stat(name)
  return stat and (stat.mtime.sec .. '.' .. stat.mtime.nsec) or nil
end

local function file_buf(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == '' and vim.api.nvim_buf_get_name(buf) ~= ''
end

local function check(buf)
  if not file_buf(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local stat = vim.uv.fs_stat(name)
  if not stat then
    return M.gone(buf)
  end
  local changed = mtime(name) ~= vim.b[buf].pc_mtime
  if vim.bo[buf].modified then
    -- would ask "File changed… Load / OK" in the middle of typing; tell instead
    if changed and not warned[buf] then
      warned[buf] = true
      vim.notify(vim.fn.fnamemodify(name, ':t') .. ' changed on disk while you edit it: :e! loads it, :w keeps yours', vim.log.levels.WARN)
    end
    return
  end
  warned[buf] = nil
  -- the text from before the change goes to Local History (Recent Changes shows the change)
  if changed then
    require('pc.local_history').keep_buffer(buf)
  end
  -- with 'autoread' an unchanged buffer is reloaded without asking
  vim.api.nvim_buf_call(buf, function()
    vim.cmd 'silent! checktime'
  end)
end

local gone_pending = {} -- buf -> true while a deleted file is being looked at again

--- The file of `buf` is gone from disk: looked at again a moment later (a tool saving through
--- delete + write), then the buffer is closed in place, or kept with a warning when modified
function M.gone(buf)
  if gone_pending[buf] or not vim.b[buf].pc_mtime or vim.b[buf].pc_new_file then
    return
  end
  gone_pending[buf] = true
  vim.defer_fn(function()
    gone_pending[buf] = nil
    if not file_buf(buf) or not vim.api.nvim_buf_is_loaded(buf) then
      return
    end
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.uv.fs_stat(name) then
      return check(buf)
    end
    local short = vim.fn.fnamemodify(name, ':t')
    if vim.bo[buf].modified then
      if not warned[buf] then
        warned[buf] = true
        vim.notify(short .. ' was deleted on disk: your text is still here, :w writes it back', vim.log.levels.WARN)
      end
      return
    end
    local ok = pcall(function()
      require('mini.bufremove').delete(buf, true)
    end)
    if not ok and vim.fn.bufwinid(buf) == -1 then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) or not vim.bo[buf].buflisted then
      vim.notify(short .. ' was deleted on disk and closed', vim.log.levels.INFO)
    end
  end, 400)
end

local function schedule_check(buf)
  if pending[buf] then
    return
  end
  pending[buf] = true
  -- an agent writes in several steps: look once it is done
  vim.defer_fn(function()
    pending[buf] = nil
    if vim.fn.mode() == 'c' then
      return schedule_check(buf)
    end
    check(buf)
  end, 150)
end

local function watch(buf)
  if not file_buf(buf) then
    return
  end
  local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
  if watchers[dir] or not vim.uv.fs_stat(dir) then
    return
  end
  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end
  local ok = handle:start(dir, {}, function(err, filename)
    if err or not filename then
      return
    end
    vim.schedule(function()
      local b = vim.fn.bufnr(vim.fs.joinpath(dir, filename))
      if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then
        schedule_check(b)
      end
    end)
  end)
  if ok then
    watchers[dir] = handle
  else
    handle:close()
  end
end

-- watchers of directories without any open file are stopped
local function prune()
  local used = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if file_buf(buf) and vim.api.nvim_buf_is_loaded(buf) then
      used[vim.fs.dirname(vim.api.nvim_buf_get_name(buf))] = true
    end
  end
  for dir, handle in pairs(watchers) do
    if not used[dir] then
      handle:stop()
      handle:close()
      watchers[dir] = nil
    end
  end
end

vim.o.autoread = true
local group = vim.api.nvim_create_augroup('pc-autoreload', { clear = true })
vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile', 'BufWritePost' }, {
  group = group,
  callback = function(event)
    vim.b[event.buf].pc_mtime = mtime(vim.api.nvim_buf_get_name(event.buf))
    -- a file that is not on disk yet (autosave creates it, pc.autosave)
    vim.b[event.buf].pc_new_file = event.event == 'BufNewFile' or nil
    warned[event.buf] = nil
    watch(event.buf)
  end,
})
-- not while your changes are still in the buffer (W12 answered OK): Neovim keeps the old time to
-- warn on writing, and autosave then asked "changed since reading it, really write?" on every
-- window change; it stays off until you :w (keeps yours) or :e! (loads theirs)
vim.api.nvim_create_autocmd('FileChangedShellPost', {
  group = group,
  callback = function(event)
    if vim.bo[event.buf].modified then
      return
    end
    vim.b[event.buf].pc_mtime = mtime(vim.api.nvim_buf_get_name(event.buf))
  end,
})
vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufUnload' }, {
  group = group,
  callback = function(event)
    pending[event.buf], warned[event.buf] = nil, nil
    vim.schedule(prune)
  end,
})
vim.api.nvim_create_autocmd({ 'FocusGained', 'TermLeave', 'BufEnter', 'WinEnter' }, {
  group = group,
  callback = function()
    if vim.fn.getcmdwintype() == '' then
      schedule_check(vim.api.nvim_get_current_buf())
    end
  end,
})

-- files opened before this module was loaded
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then
    watch(buf)
  end
end

-- Neovim's own check (focus, entering the buffer, :checktime) of a file deleted on disk said
-- "E211: File … no longer available"; that case is handled above, the others as before
vim.api.nvim_create_autocmd('FileChangedShell', {
  group = group,
  callback = function(event)
    if vim.v.fcs_reason == 'deleted' then
      vim.v.fcs_choice = ''
      vim.schedule(function()
        M.gone(event.buf)
      end)
    else
      vim.v.fcs_choice = 'ask'
    end
  end,
})

return M
