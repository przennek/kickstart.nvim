-- sonarlint and a Java file jdtls does not have in its project (pc.lsp_guard.sonarlint_foreign_files),
-- headless, a fake jdtls:  nvim --headless --clean -u NONE -n -i NONE -c 'luafile tests/sonarlint_foreign.lua'
-- Exit status: the number of failures.
vim.opt.rtp:append(vim.fn.expand '~/.local/share/nvim/lazy/sonarlint.nvim')
local here = vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, 'S').source:sub(2)))
package.path = here .. '/../lua/?.lua;' .. package.path
local util = require 'sonarlint.jdtlsutil'
local ERR = { code = -32001, message = 'Given URI does not belong to an existing Java source file.', data = { message = 'Given URI does not belong to an existing Java source file.' } }
util.execute_command = function(cmd)
  if cmd.arguments[1]:find 'foreign' then return ERR, nil end
  if cmd.command == 'java.project.isTestFile' then return nil, true end
  if cmd.command == 'java.project.getClasspaths' then return nil, { projectRoot = 'r', classpaths = { 'a.jar' } } end
  return { message = 'other failure' }, nil
end
require('pc.lsp_guard').sonarlint_foreign_files()
local fails = 0
local function expect(l, got, want) local ok = vim.deep_equal(got, want) print((ok and 'ok   ' or 'FAIL ') .. l .. ': ' .. vim.inspect(got)) if not ok then fails = fails + 1 end end
local e, r = util.execute_command { command = 'java.project.isTestFile', arguments = { 'file:///foreign/A.java' } }
expect('foreign isTestFile: no error', { e, r }, { nil, false })
e, r = util.execute_command { command = 'java.project.getClasspaths', arguments = { 'file:///foreign/A.java' } }
expect('foreign classpath: no error', e, nil)
e, r = util.execute_command { command = 'java.project.isTestFile', arguments = { 'file:///proj/A.java' } }
expect('project file: real answer', r, true)
e, r = util.execute_command { command = 'java.other', arguments = { 'file:///proj/A.java' } }
expect('other errors still reported', e and e.message, 'other failure')
-- the real handler path: no assert for a foreign file
local notified = {}
vim.notify = function(m, lvl) table.insert(notified, m) end
package.loaded['sonarlint.java'] = nil
local java = require 'sonarlint.java'
vim.lsp.get_client_by_id = function() return { id = 1 } end
java._classpath_change_listener = { [1] = true }
local ok, cfg = pcall(java.get_java_config_handler, nil, 'file:///foreign/A.java', { client_id = 1 })
expect('handler: no error', ok, true)
expect('handler: no error message', #notified, 0)
os.exit(fails)
