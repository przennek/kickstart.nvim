-- Errors go to the error log (pc.error_log): a notification error and warning, a Vim error, a
-- Lua error in a callback with its traceback; not info messages, not errors silenced with
-- silent!; your moves, without the text typed. Writes into the scratch directory, not your log. Prints OK / FAIL and quits.
local log = require 'pc.error_log'
log.FILE = vim.env.WORK .. '/errors.log'
local bad = {}
vim.notify('notify error', vim.log.levels.ERROR, { title = 'jdtls' })
vim.notify('notify warning', vim.log.levels.WARN)
vim.notify 'just information'
vim.cmd 'silent! call silenced_missing()'
pcall(vim.cmd, 'call visible_missing()')
vim.api.nvim_echo({ { 'E117: Unknown function: visible_missing' } }, true, { err = true })
vim.schedule(function()
  error 'callback failure'
end)
-- moves: Normal keys as typed (text typed is only counted: checked in the scenario, feedkeys
-- does not mark Insert keys as typed)
vim.api.nvim_feedkeys('jjw', 'tx', false)
-- Ex commands and searches are masked when written: kind, command name and length only
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a sekretword here' }) -- found, so no E486 with the pattern in it
vim.api.nvim_feedkeys('/sekretword\r', 'tx', false)
vim.api.nvim_feedkeys(':echo "sekret123"\r', 'tx', false)
vim.wait(2000, function()
  return false
end)
local text = table.concat(vim.fn.readfile(log.FILE), '\n')
for _, want in ipairs {
  'move .* n text: j×2 w',
  'ERROR jdtls .* notify error',
  'WARN .* notify warning',
  'E117: Unknown function: visible_missing',
  'callback failure',
  'stack traceback',
  'move .* /%(%+10 chars%)',
  'move .* :echo %(%+11 chars%)',
} do
  if not text:match(want) then
    table.insert(bad, 'missing ' .. want)
  end
end
for _, unwanted in ipairs { 'just information', 'silenced_missing', 'sekretword', 'sekret123' } do
  if text:find(unwanted, 1, true) then
    table.insert(bad, 'logged ' .. unwanted)
  end
end
io.stdout:write('\n' .. (#bad == 0 and 'OK error log' or ('FAIL error log: ' .. table.concat(bad, '; ') .. '\n' .. text)) .. '\n')
vim.cmd 'qa!'
