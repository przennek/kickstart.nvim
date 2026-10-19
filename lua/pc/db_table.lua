-- Tables in SQL, like IDEA's navigation on a table name in a query console:
--   F4             open the table's data (first 200 rows) in the results grid
--   Alt+B / gd     the table's DDL (CREATE TABLE + constraints + indexes) in a split
--   gh             its columns (name, type, nullable, default) in a float
-- On the table name under the cursor (schema.table works), in consoles (<leader>Qq), query
-- buffers from the Database window and any .sql file with a connection.
-- The Database window gets the same as table helpers: Structure and DDL next to List/Columns…,
-- and opening one runs it straight away.

local M = {}

local LIMIT = 200

-- psql: one value per line, no header, so DDL comes out as plain SQL
local PG_PLAIN = '\\set QUIET on\n\\pset tuples_only on\n\\pset format unaligned\n'

local QUERIES = {
  postgresql = {
    structure = [[
select a.attname as name, format_type(a.atttypid, a.atttypmod) as type,
       case when a.attnotnull then 'NO' else 'YES' end as nullable,
       pg_get_expr(d.adbin, d.adrelid) as default_value
from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
where a.attrelid = '{table}'::regclass and a.attnum > 0 and not a.attisdropped
order by a.attnum]],
    ddl = [[
select 'CREATE TABLE ' || c.oid::regclass || E' (\n' ||
       string_agg('    ' || quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod)
         || case when a.attnotnull then ' NOT NULL' else '' end
         || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), ''), E',\n' order by a.attnum)
       || coalesce((select E',\n' || string_agg('    CONSTRAINT ' || quote_ident(conname) || ' '
         || pg_get_constraintdef(oid), E',\n' order by contype desc, conname)
         from pg_constraint where conrelid = c.oid and contype <> 'n'), '')
       || E'\n);'
from pg_class c
join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
where c.oid = '{table}'::regclass
group by c.oid
union all
(select pg_get_indexdef(i.indexrelid) || ';' from pg_index i
 where i.indrelid = '{table}'::regclass
   and not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid)
 order by 1)]],
  },
  sqlite = {
    structure = [[
select name, type, case "notnull" when 1 then 'NO' else 'YES' end as nullable, dflt_value as default_value
from pragma_table_info('{table}')]],
    ddl = [[select sql || ';' from sqlite_master where tbl_name = '{table}' and sql is not null order by type desc]],
  },
  mysql = {
    structure = [[
select column_name as name, column_type as type, is_nullable as nullable, column_default as default_value
from information_schema.columns where table_schema = database() and table_name = '{table}'
order by ordinal_position]],
    ddl = [[show create table `{table}`]],
  },
}
QUERIES.postgres = QUERIES.postgresql
QUERIES.sqlite3 = QUERIES.sqlite
QUERIES.mariadb = QUERIES.mysql

local function scheme(url)
  return url:match '^(%w+):'
end

local function queries(url)
  return QUERIES[scheme(url) or ''] or {}
end

-- The connection of a SQL buffer: console, Database window query buffer, b:db / g:db
local function buffer_url(buf)
  local url = require('pc.db_console').url(buf)
  if url then
    return url
  end
  local db = vim.b[buf].db or vim.g.db
  return type(db) == 'string' and db ~= '' and db or nil
end

local function table_under_cursor()
  local word = vim.fn.expand '<cWORD>'
  local name = word:match '[%w_."`]+'
  name = name and name:gsub('[`"]', ''):gsub('^%.+', ''):gsub('%.+$', '')
  if not name or name == '' or not name:match '^[%a_][%w_.]*$' then
    return nil
  end
  return name
end

local function fill(sql, tbl)
  return (sql:gsub('{table}', function()
    return tbl
  end))
end

-- Runs a query through the database's command-line client; returns the output lines.
-- tabular = true: a header and aligned columns (structure), otherwise bare values (DDL).
local function run(url, sql, tabular)
  local cmd
  local s = scheme(url)
  if s == 'postgres' or s == 'postgresql' then
    cmd = { 'psql', '-X', '-w', '-q', '-P', 'footer=off', url, '-v', 'ON_ERROR_STOP=1' }
  else
    cmd = vim.fn['db#adapter#call'](url, 'filter', { url }, '')
    if type(cmd) ~= 'table' or #cmd == 0 then
      cmd = vim.fn['db#adapter#call'](url, 'interactive', { url }, '')
    end
    if type(cmd) ~= 'table' or #cmd == 0 then
      return nil, 'this database type has no command-line client support'
    end
    if s == 'sqlite' or s == 'sqlite3' then
      -- after dadbod's own options, so these win
      vim.list_extend(cmd, tabular and { '-header', '-column' } or { '-list', '-noheader' })
    elseif s == 'mysql' or s == 'mariadb' then
      table.insert(cmd, 2, tabular and '--table' or '--skip-column-names')
    end
  end
  local result = vim.system(cmd, { stdin = sql, text = true, timeout = 15000 }):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr ~= '' and result.stderr or result.stdout or '')
  end
  return vim.split((result.stdout or ''):gsub('%s+$', ''), '\n')
end

M.run = run

local PRIMARY_KEY = {
  postgresql = [[
select a.attname from pg_index i
join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
where i.indrelid = '{table}'::regclass and i.indisprimary order by array_position(i.indkey, a.attnum)]],
  sqlite = [[select name from pragma_table_info('{table}') where pk > 0 order by pk]],
  mysql = [[
select column_name from information_schema.key_column_usage
where table_schema = database() and table_name = '{table}' and constraint_name = 'PRIMARY'
order by ordinal_position]],
}
PRIMARY_KEY.postgres = PRIMARY_KEY.postgresql
PRIMARY_KEY.sqlite3 = PRIMARY_KEY.sqlite
PRIMARY_KEY.mariadb = PRIMARY_KEY.mysql

--- First value of a one-value query (string), or nil + error
function M.scalar(url, sql)
  local is_pg = scheme(url):match '^postgres'
  local lines, err = run(url, (is_pg and PG_PLAIN or '') .. sql .. ';\n')
  if not lines then
    return nil, err
  end
  return vim.trim(lines[#lines] or '')
end

--- Primary key columns of a table ({} when it has none), or nil + error
function M.primary_key(url, tbl)
  local sql = PRIMARY_KEY[scheme(url) or '']
  if not sql then
    return nil, 'not supported for this database'
  end
  local is_pg = scheme(url):match '^postgres'
  local lines, err = run(url, (is_pg and PG_PLAIN or '') .. fill(sql, tbl) .. ';\n')
  if not lines then
    return nil, err
  end
  return vim.tbl_filter(function(l)
    return l ~= ''
  end, lines)
end

local function with_table(fn)
  return function()
    require('lazy').load { plugins = { 'vim-dadbod-ui' } }
    local buf = vim.api.nvim_get_current_buf()
    local url = buffer_url(buf)
    if not url then
      return vim.notify('No connection for this buffer: open a console (<leader>Qq)', vim.log.levels.WARN)
    end
    local tbl = table_under_cursor()
    if not tbl then
      return vim.notify('No table name under the cursor', vim.log.levels.WARN)
    end
    fn(url, tbl)
  end
end

M.open_data = with_table(function(url, tbl)
  local s = scheme(url)
  local quoted = (s == 'mysql' or s == 'mariadb') and ('`' .. tbl:gsub('%.', '`.`') .. '`') or tbl
  vim.cmd(('DB %s select * from %s limit %d'):format(url, quoted, LIMIT))
end)

M.show_ddl = with_table(function(url, tbl)
  local sql = queries(url).ddl
  if not sql then
    return vim.notify('DDL: not supported for this database', vim.log.levels.WARN)
  end
  local is_pg = scheme(url):match '^postgres'
  local lines, err = run(url, (is_pg and PG_PLAIN or '') .. fill(sql, tbl) .. ';\n')
  if not lines then
    return vim.notify('DDL ' .. tbl .. ': ' .. err, vim.log.levels.ERROR)
  end
  if not is_pg and scheme(url):match '^m' then
    -- mysql batch output: "table<TAB>CREATE TABLE …" with \n escaped
    local create = (lines[#lines] or ''):match '\t(.*)$' or table.concat(lines, '\n')
    lines = vim.split(create:gsub('\\n', '\n') .. ';', '\n')
  end
  vim.cmd 'botright new'
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'sql'
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, 'DDL ' .. tbl)
  vim.api.nvim_win_set_height(0, math.min(#lines + 1, math.floor(vim.o.lines / 2)))
  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, desc = 'Close' })
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, desc = 'Close' })
end)

M.show_structure = with_table(function(url, tbl)
  local sql = queries(url).structure
  if not sql then
    return vim.notify('Structure: not supported for this database', vim.log.levels.WARN)
  end
  local lines, err = run(url, fill(sql, tbl) .. ';\n', true)
  if not lines then
    return vim.notify(tbl .. ': ' .. err, vim.log.levels.ERROR)
  end
  vim.lsp.util.open_floating_preview(lines, '', { title = ' ' .. tbl .. ' ', border = 'rounded', focus_id = 'pc-db-structure' })
end)

-- Database window: Structure and DDL under every table, executed when opened
local helpers = vim.g.db_ui_table_helpers or {}
for name, q in pairs { postgresql = QUERIES.postgresql, sqlite = QUERIES.sqlite, mysql = QUERIES.mysql, mariadb = QUERIES.mysql } do
  local schema_table = name == 'postgresql' and '{optional_schema}"{table}"' or '{table}'
  helpers[name] = vim.tbl_extend('keep', helpers[name] or {}, {
    Structure = fill(q.structure, schema_table),
    DDL = (name == 'postgresql' and PG_PLAIN or '') .. fill(q.ddl, schema_table),
  })
end
vim.g.db_ui_table_helpers = helpers
vim.g.db_ui_auto_execute_table_helpers = 1

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'sql', 'mysql', 'plsql' },
  group = vim.api.nvim_create_augroup('pc-db-table', { clear = true }),
  callback = function(event)
    local function map(lhs, fn, desc)
      vim.keymap.set('n', lhs, fn, { buffer = event.buf, desc = desc })
    end
    map('<F4>', M.open_data, 'Open table data')
    map('gd', M.show_ddl, 'Table DDL')
    map('<M-b>', M.show_ddl, 'Table DDL')
    map('gh', M.show_structure, 'Table structure')
  end,
})

return M
