-- Test Connection fails with a message that says why, never an empty one: a server that does
-- not answer, a missing password (no prompt), nothing listening. Needs SILENT_PORT / PASSWORD_PORT
-- (tests/lib/fake_pg.py) and FREE_PORT. Prints OK / FAIL and quits.
local dbc = require 'pc.db_connections'
local cases = {
  { 'postgresql://u@127.0.0.1:' .. vim.env.SILENT_PORT .. '/db', 'timeout expired' },
  { 'postgresql://u@127.0.0.1:' .. vim.env.PASSWORD_PORT .. '/db', 'no password supplied' },
  { 'postgresql://u@127.0.0.1:' .. vim.env.FREE_PORT .. '/db', 'Connection refused' },
}
local bad = {}
for i, c in ipairs(cases) do
  local t = vim.uv.hrtime()
  local ok, msg = dbc.test(c[1])
  local secs = (vim.uv.hrtime() - t) / 1e9
  if ok or not msg:find(c[2], 1, true) or secs > 10.5 then
    table.insert(bad, ('%d: ok=%s in %.1fs: %q'):format(i, tostring(ok), secs, msg))
  end
end
io.stdout:write((#bad == 0 and 'OK test connection errors' or ('FAIL test connection errors: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
