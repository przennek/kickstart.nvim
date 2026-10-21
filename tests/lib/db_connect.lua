-- Data sources: Test Connection fails with a message that says why, never an empty one (a server
-- that does not answer, a missing password: no prompt, nothing listening); passwords are kept for
-- every database of the server. Needs SILENT_PORT / PASSWORD_PORT (tests/lib/fake_pg.py) and
-- FREE_PORT. Prints OK / FAIL and quits.
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
-- the password of a data source is kept for all databases of its server (switching databases),
-- replacing older entries of that server and user; other lines stay
local pgpass = vim.fn.tempname()
vim.fn.writefile({ '# mine', 'other:5432:*:u:keep', 'db.example:5432:app:u:old', 'db.example:5432:*:u:older', 'db.example:5432:app:admin:x' }, pgpass)
local saved = vim.env.PGPASSFILE
vim.env.PGPASSFILE = pgpass
dbc.store_pgpass('db.example', '5432', 'u', 'new:pa\\ss')
vim.env.PGPASSFILE = saved
local want = { '# mine', 'other:5432:*:u:keep', 'db.example:5432:app:admin:x', 'db.example:5432:*:u:new\\:pa\\\\ss' }
local got = vim.fn.readfile(pgpass)
if not vim.deep_equal(got, want) then
  table.insert(bad, 'pgpass: ' .. table.concat(got, ' | '))
end
os.remove(pgpass)
io.stdout:write((#bad == 0 and 'OK data source connections' or ('FAIL data source connections: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
