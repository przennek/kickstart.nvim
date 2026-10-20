-- Alt+Enter in a SQL buffer runs the statement under the cursor: its lines, for cases where
-- statements touch each other (no empty line between). Prints OK / FAIL and quits.
local cases = {
  { { 'select count(*) from orders', 'select pg_sleep(30)' }, 2, 2, 2 },
  { { 'select count(*) from orders', 'select pg_sleep(30)' }, 1, 1, 1 },
  { { 'select a', 'from t', 'where x = 1' }, 2, 1, 3 },
  { { 'select a from t', 'union', 'select b from u' }, 3, 1, 3 },
  { { 'select a from t;', 'select b from u;' }, 2, 2, 2 },
  { { 'insert into t (a, b)', 'values (1, 2)' }, 2, 1, 2 },
  { { 'with x as (', 'select 1', ')', 'select * from x' }, 4, 1, 4 },
  { { 'update t set a = 1', 'where b = 2;', 'delete from t', 'where c = 3' }, 4, 3, 4 },
  { { 'insert into t (a)', 'select a from u' }, 2, 1, 2 },
  { { 'select 1', '', 'select 2' }, 3, 3, 3 },
  { { 'select a,', 'b from t', 'select c from u', 'where d' }, 4, 3, 4 },
}
vim.cmd 'set ft=sql'
vim.ui.select = function() end
-- the test's statements stay out of your query history
require('pc.db_console').record = function() end
local out = {}
for i, c in ipairs(cases) do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, c[1])
  vim.api.nvim_win_set_cursor(0, { c[2], 0 })
  local m = vim.fn.maparg('<M-CR>', 'n', false, true)
  -- call the mapping with a fake executor: read the marks it sets
  local ok = pcall(m.callback)
  local f, l = vim.fn.line "'<", vim.fn.line "'>"
  table.insert(out, (f == c[3] and l == c[4]) and ('ok ' .. i) or ('FAIL ' .. i .. ': got ' .. f .. '-' .. l .. ' want ' .. c[3] .. '-' .. c[4]))
end
local bad = vim.tbl_filter(function(l) return l:match '^FAIL' end, out)
io.stdout:write((#bad == 0 and 'OK sql statements' or ('FAIL sql statements: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
