-- Error log: every error you get while working goes to one file, to send it on as a whole
-- (stdpath('log')/pc-errors.log, ~/.local/state/nvim/pc-errors.log):
--   errors and warnings of plugins and language servers (vim.notify, through pc.notifications)
--   Vim / Lua errors you saw (E… messages, "Error executing lua callback" with its traceback),
--   which never pass vim.notify: read from the message history
-- Each entry: time, source, the file you were in, the message (more lines indented).
--   :ErrorLog        open the log (newest at the end)
--   :ErrorLogClear   empty it
-- Over 2 MB the log moves to pc-errors.log.old and starts again.

local M = {}

M.FILE = vim.fn.stdpath 'log' .. '/pc-errors.log'
local MAX = 2 * 1024 * 1024

local last_entry, last_time = nil, 0

--- Appends an entry; `source` e.g. 'vim', 'ERROR lsp', 'WARN telescope'
function M.record(source, msg)
  msg = vim.trim(type(msg) == 'string' and msg or vim.inspect(msg))
  if msg == '' then
    return
  end
  -- the same message again within a second (a loop of errors) is written once
  local now = vim.uv.now()
  if msg == last_entry and now - last_time < 1000 then
    return
  end
  last_entry, last_time = msg, now
  local stat = vim.uv.fs_stat(M.FILE)
  if stat and stat.size > MAX then
    os.rename(M.FILE, M.FILE .. '.old')
  end
  local ok, file = pcall(function()
    local name = vim.api.nvim_buf_get_name(0)
    return name ~= '' and vim.fn.fnamemodify(name, ':~:.') or vim.bo.filetype
  end)
  local lines = vim.split(msg, '\n', { plain = true })
  local text = ('%s  %s  [%s]  %s\n'):format(os.date '%Y-%m-%d %H:%M:%S', source, ok and file or '?', lines[1])
  for i = 2, #lines do
    text = text .. '    ' .. lines[i] .. '\n'
  end
  local f = io.open(M.FILE, 'a')
  if f then
    f:write(text)
    f:close()
  end
end

-- Vim errors: the ones shown to you are in the message history (`:messages`); errors a plugin
-- silences on purpose (silent!) are not. A changed v:errmsg says there is something new: the
-- history's new lines are read and their error blocks (E123: …, Error …, "… error …" with the
-- indented traceback below) written. Our own echo of a notification is in the log already.
local seen = {} -- the history as read last time
local function new_lines()
  local ok, out = pcall(vim.api.nvim_exec2, 'messages', { output = true })
  local lines = ok and vim.split(out.output, '\n', { plain = true }) or {}
  -- the history drops its oldest lines when full: find where the last read ended
  local from = 1
  for i = math.min(#seen, #lines), 1, -1 do
    local match = true
    for j = 0, i - 1 do
      if lines[i - j] ~= seen[#seen - j] then
        match = false
        break
      end
    end
    if match then
      from = i + 1
      break
    end
  end
  seen = lines
  return vim.list_slice(lines, from)
end

-- error text: E123:, Error …, … error …; not our own echo of a notification (it is logged)
local function is_error(chunk)
  local text = table.concat(chunk, '\n')
  if text:find('(<leader>tn)', 1, true) then
    return false
  end
  return text:match 'E%d+:' or text:match '%f[%a][Ee]rror' or text:match 'stack traceback:'
end

-- The history has no boundaries between messages: an indented line and "stack traceback:"
-- belong to the line before; a header ("Error detected while processing …:") to the one after
local function scan()
  local chunks = {}
  for _, line in ipairs(new_lines()) do
    local prev = chunks[#chunks]
    if line == '' then
      prev = nil
    elseif prev and (line:match '^%s' or line:match '^stack traceback' or prev[#prev]:match ':$') then
      table.insert(prev, line)
    else
      table.insert(chunks, { line })
    end
  end
  for _, chunk in ipairs(chunks) do
    if is_error(chunk) then
      M.record('vim', table.concat(chunk, '\n'))
    end
  end
end

local last_errmsg = vim.v.errmsg
local function check()
  if vim.v.errmsg ~= last_errmsg then
    last_errmsg = vim.v.errmsg
    scan()
  end
end

vim.fn.mkdir(vim.fs.dirname(M.FILE), 'p')
scan() -- what went wrong before this module loaded
local timer = vim.uv.new_timer()
if timer then
  timer:start(500, 500, vim.schedule_wrap(check))
end
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = vim.api.nvim_create_augroup('pc-error-log', { clear = true }),
  callback = check,
})

vim.api.nvim_create_user_command('ErrorLog', function()
  vim.cmd('tabnew ' .. vim.fn.fnameescape(M.FILE))
  vim.bo.readonly = true
  vim.cmd 'normal! G'
end, { desc = 'Open the error log' })
vim.api.nvim_create_user_command('ErrorLogClear', function()
  local f = io.open(M.FILE, 'w')
  if f then
    f:close()
  end
  vim.notify 'Error log cleared'
end, { desc = 'Empty the error log' })

return M
