-- Switching a console (<leader>Qs): schema, another database of the server, another data
-- source; the console runs on what was picked. Needs PG_URL (a PostgreSQL server where the user
-- may create databases) and an isolated XDG_DATA_HOME (consoles are written there).
-- Prints OK / FAIL and quits.
local url = vim.env.PG_URL
local function psql(db, sql)
  return vim.system({ 'psql', '-X', '-w', '-At', (url:gsub('/[^/?]*$', '/' .. db)), '-c', sql }, { text = true }):wait()
end
psql('postgres', 'drop database if exists pc_switch_b')
psql('postgres', 'create database pc_switch_b')
psql('pc_switch_b', 'create schema sales')
vim.g.dbs = { { name = 'srv', url = (url:gsub('/[^/?]*$', '/postgres')) }, { name = 'other', url = url } }

local console = require 'pc.db_console'
local bad = {}
local function pick(label)
  vim.ui.select = function(items, opts, on_choice)
    for _, item in ipairs(items) do
      if opts.format_item(item):match('^..' .. vim.pesc(label) .. '$') then
        return on_choice(item)
      end
    end
    table.insert(bad, 'no item ' .. label)
    on_choice(nil)
  end
end
local function run(sql)
  local r = vim.system({ 'psql', '-X', '-w', '-At', console.url(0), '-c', sql }, { text = true }):wait()
  return vim.trim(r.stdout .. r.stderr)
end
local function expect(what, got, want)
  if got ~= want then
    table.insert(bad, ('%s: got %q, wanted %q'):format(what, got, want))
  end
end

-- a new console on srv
vim.ui.input = function(_, on_confirm)
  on_confirm 'switch_test'
end
vim.ui.select = function(items, _, on_choice)
  if items[1].new then
    return on_choice(items[1])
  end
  for _, c in ipairs(items) do
    if c.name == 'srv' then
      return on_choice(c)
    end
  end
end
console.open()
expect('console', console.connection_name(0), 'srv')
expect('database at start', run 'select current_database()', 'postgres')

pick 'database  pc_switch_b'
console.choose_schema()
expect('database switched', run 'select current_database()', 'pc_switch_b')
expect('winbar', vim.wo.winbar:gsub('%%#Title#', ''), '󰆼 srv › pc_switch_b')

pick 'schema    sales'
console.choose_schema()
expect('schema of the other database', run 'select current_schema()', 'sales')
expect('history name', console.connection_name(0), 'srv.pc_switch_b.sales')

pick 'database  postgres'
console.choose_schema()
expect('back to the default database', run 'select current_database() || current_schema()', 'postgrespublic')
expect('winbar default', vim.wo.winbar:gsub('%%#Title#', ''), '󰆼 srv')

pick 'source    other'
console.choose_schema()
expect('other data source', console.connection_name(0), 'other')

psql('postgres', 'drop database if exists pc_switch_b')
io.stdout:write((#bad == 0 and 'OK console switch' or ('FAIL console switch: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
