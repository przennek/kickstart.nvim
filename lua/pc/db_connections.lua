-- Data Sources dialog like IDEA's (a form, see pc.form): type, host, port, database, user,
-- password, plus an SSH tunnel and / or a SOCKS5 / HTTP proxy (pc.db_tunnels); Test Connection
-- (Ctrl+T) and OK (Ctrl+S) save it to the Database window's list.
--   in the Database window: a or Alt+Insert = new data source, E = edit data sources, R = refresh
--   <leader>Qd / :DBDataSources = pick a data source to edit (or + New), :DBAddConnection = new
-- PostgreSQL passwords go to ~/.pgpass (mode 600), not into the saved connection list.

local M = {}

local TYPES = {
  { label = 'PostgreSQL', scheme = 'postgresql', port = '5432', client = 'psql' },
  { label = 'MySQL / MariaDB', scheme = 'mysql', port = '3306', client = 'mysql' },
  { label = 'MongoDB', scheme = 'mongodb', port = '27017', client = 'mongosh' },
  { label = 'SQLite (file)', scheme = 'sqlite', client = 'sqlite3' },
}

local function encode(s)
  return (s:gsub('[^%w%-%._~]', function(c)
    return ('%%%02X'):format(c:byte())
  end))
end

local function connections_file()
  return vim.fn.stdpath 'data' .. '/dadbod/connections.json'
end

local function read_connections()
  local f = io.open(connections_file())
  if not f then
    return {}
  end
  local ok, list = pcall(vim.json.decode, f:read '*a')
  f:close()
  return ok and type(list) == 'table' and list or {}
end

local function write_connections(list)
  vim.fn.mkdir(vim.fs.dirname(connections_file()), 'p')
  local f = assert(io.open(connections_file(), 'w'))
  f:write(vim.json.encode(list))
  f:close()
  -- proxy passwords may be in it
  vim.uv.fs_chmod(connections_file(), tonumber('600', 8))
  -- refresh an open Database window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'dbui' then
      vim.api.nvim_win_call(win, function()
        vim.cmd 'normal R'
      end)
    end
  end
end

-- Adds a connection, or replaces the one called `replaces` (editing)
local function save_connection(entry, replaces)
  local list = read_connections()
  for i = #list, 1, -1 do
    if list[i].name == replaces then
      table.remove(list, i)
    elseif list[i].name == entry.name then
      vim.notify('A connection named "' .. entry.name .. '" already exists', vim.log.levels.ERROR)
      return false
    end
  end
  table.insert(list, entry)
  write_connections(list)
  return true
end

-- host:port:database:user:password, replacing an existing entry for the same target
local function store_pgpass(host, port, db, user, password)
  local path = vim.fs.joinpath(vim.env.HOME, '.pgpass')
  local key = table.concat({ host, port, db, user }, ':') .. ':'
  local lines = {}
  local f = io.open(path)
  if f then
    for line in f:lines() do
      if not vim.startswith(line, key) then
        table.insert(lines, line)
      end
    end
    f:close()
  end
  table.insert(lines, key .. password:gsub('\\', '\\\\'):gsub(':', '\\:'))
  f = assert(io.open(path, 'w'))
  f:write(table.concat(lines, '\n') .. '\n')
  f:close()
  vim.uv.fs_chmod(path, tonumber('600', 8))
end

local function test_connection(t, url)
  if vim.fn.executable(t.client) == 0 then
    return false, t.client .. ' is not installed'
  end
  local cmd
  if t.scheme == 'postgresql' then
    cmd = { 'psql', url, '-X', '-q', '-c', 'select 1' }
  elseif t.scheme == 'mysql' then
    -- the mysql client takes no URL; credentials are checked when the connection is first used
    return true, ''
  elseif t.scheme == 'mongodb' then
    cmd = { 'mongosh', url, '--quiet', '--eval', 'db.runCommand({ ping: 1 }).ok' }
  else
    cmd = { 'sqlite3', url:gsub('^sqlite:', ''), 'select 1;' }
  end
  local result = vim.system(cmd, { text = true, timeout = 10000 }):wait()
  return result.code == 0, vim.trim((result.stderr ~= '' and result.stderr) or result.stdout or '')
end

local function type_by_label(label)
  for _, t in ipairs(TYPES) do
    if t.label == label then
      return t
    end
  end
  return TYPES[1]
end

local function decode(s)
  return (s:gsub('%%(%x%x)', function(h)
    return string.char(tonumber(h, 16))
  end))
end

-- Form values of a saved connection: its own settings, or parsed from the URL
local function values_of(entry)
  if entry.pc then
    return vim.tbl_extend('force', vim.deepcopy(entry.pc), { name = entry.name, password = '' })
  end
  local scheme, rest = entry.url:match '^(%w+):(.*)$'
  local v = { name = entry.name }
  for _, t in ipairs(TYPES) do
    if scheme and (t.scheme == scheme or (t.scheme == 'postgresql' and scheme == 'postgres')) then
      v.type = t.label
    end
  end
  if scheme == 'sqlite' then
    v.file = rest
    return v
  end
  local auth, host, port, db = (rest or ''):match '^//([^@/]*@?)([^:/?]*):?(%d*)/?([^?]*)'
  local user = auth and auth:match '^([^:@]*)'
  v.host, v.port, v.database, v.user = host, port ~= '' and port or nil, db, user and decode(user)
  return v
end

-- URL and saved settings of the form's values
local function build(values, local_port)
  local t = type_by_label(values.type)
  if t.scheme == 'sqlite' then
    return 'sqlite:' .. vim.fn.fnamemodify(values.file or '', ':p'), nil
  end
  local tunnel = values.ssh or values.proxy
  local host = tunnel and '127.0.0.1' or values.host
  local port = tunnel and tostring(local_port) or values.port
  local auth = values.user ~= '' and encode(values.user or '') or ''
  if values.password ~= '' and t.scheme ~= 'postgresql' then
    auth = auth .. ':' .. encode(values.password)
  end
  local url = ('%s://%s%s:%s/%s'):format(t.scheme, auth ~= '' and (auth .. '@') or '', host, port, values.database or '')
  local pc = vim.deepcopy(values)
  pc.name, pc.password, pc.local_port = nil, nil, tunnel and local_port or nil
  return url, pc
end

local function form_fields()
  local function server(v)
    return type_by_label(v.type).scheme ~= 'sqlite'
  end
  local function ssh(v)
    return server(v) and v.ssh
  end
  local function proxy(v)
    return server(v) and v.proxy
  end
  local labels = vim.tbl_map(function(t)
    return t.label
  end, TYPES)
  return {
    { header = 'General' },
    { key = 'name', label = 'Name' },
    { key = 'type', label = 'Type', choices = labels, default = TYPES[1].label },
    { key = 'file', label = 'Database file', complete = 'file', visible = function(v)
      return not server(v)
    end },
    { key = 'host', label = 'Host', default = 'localhost', visible = server },
    { key = 'port', label = 'Port', default = TYPES[1].port, visible = server },
    { key = 'database', label = 'Database', default = '', visible = server },
    { key = 'user', label = 'User', default = vim.env.USER, visible = server },
    { key = 'password', label = 'Password', secret = true, default = '', visible = server },
    { header = 'SSH tunnel' },
    { key = 'ssh', label = 'Use SSH tunnel', check = true, default = false, visible = server },
    { key = 'ssh_host', label = 'SSH host', default = '', visible = ssh },
    { key = 'ssh_port', label = 'SSH port', default = '22', visible = ssh },
    { key = 'ssh_user', label = 'SSH user', default = vim.env.USER, visible = ssh },
    { key = 'ssh_key', label = 'Private key (empty = agent)', default = '', complete = 'file', visible = ssh },
    { header = 'Proxy' },
    { key = 'proxy', label = 'Use proxy', check = true, default = false, visible = server },
    { key = 'proxy_type', label = 'Proxy type', choices = { 'SOCKS5', 'HTTP' }, default = 'SOCKS5', visible = proxy },
    { key = 'proxy_host', label = 'Proxy host', default = '', visible = proxy },
    { key = 'proxy_port', label = 'Proxy port', default = '1080', visible = proxy },
    { key = 'proxy_user', label = 'Proxy user', default = '', visible = function(v)
      return proxy(v) and not v.ssh
    end },
    { key = 'proxy_password', label = 'Proxy password', secret = true, default = '', visible = function(v)
      return proxy(v) and not v.ssh
    end },
    { key = 'url', label = 'URL', readonly = true, value = function(v)
      local url = build(v, '<local port>')
      return (url:gsub(':[^:@/]*@', ':••••@'))
    end },
  }
end

--- The Data Source dialog; entry = a saved connection to edit, nil for a new one
function M.open(entry)
  local tunnels = require 'pc.db_tunnels'
  local old_port = entry and entry.pc and entry.pc.local_port
  local function local_port(values)
    if not (values.ssh or values.proxy) then
      return nil
    end
    if not old_port then
      local taken = {}
      for _, c in ipairs(read_connections()) do
        if c.pc and c.pc.local_port then
          taken[c.pc.local_port] = true
        end
      end
      old_port = tunnels.free_port(taken)
    end
    return old_port
  end
  local function check(values, form)
    local t = type_by_label(values.type)
    local url, pc = build(values, local_port(values))
    if t.scheme ~= 'sqlite' and values.password ~= '' and t.scheme == 'postgresql' then
      store_pgpass(pc.local_port and '127.0.0.1' or values.host, pc.local_port and tostring(pc.local_port) or values.port, values.database ~= '' and values.database or '*', values.user, values.password)
    end
    local ok, err = tunnels.ensure({ name = values.name or 'new', url = url, pc = pc }, true)
    if ok then
      ok, err = test_connection(t, url)
    end
    form:say(ok and 'Test Connection: succeeded' or ('Test Connection failed: ' .. err), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    return ok, url, pc
  end
  require('pc.form').open {
    title = entry and ('Data Source: ' .. entry.name) or 'New Data Source',
    fields = form_fields(),
    values = entry and values_of(entry) or nil,
    on_change = function(values, key)
      if key == 'type' then
        values.port = type_by_label(values.type).port
      end
    end,
    buttons = {
      { label = 'Test Connection', key = '<C-t>', run = check },
      {
        label = 'OK',
        key = '<C-s>',
        run = function(values, form)
          if not values.name or values.name == '' then
            values.name = type_by_label(values.type).scheme == 'sqlite' and vim.fn.fnamemodify(values.file or 'db', ':t:r') or ((values.database ~= '' and values.database or 'db') .. '@' .. (values.host or ''))
          end
          local ok, url, pc = check(values, form)
          if not ok and vim.fn.confirm('Test Connection failed. Save anyway?', '&Yes\n&No', 2) ~= 1 then
            return
          end
          if save_connection({ name = values.name, url = url, pc = pc }, entry and entry.name) then
            form:close()
            vim.notify(('Data source "%s" saved (Database window: <leader>S)'):format(values.name))
          end
        end,
      },
    },
  }
end

function M.add()
  M.open(nil)
end

--- Data Sources: pick one to edit, or + New
function M.manage()
  local items = vim.list_extend({ { name = '+ New data source…' } }, read_connections())
  vim.ui.select(items, {
    prompt = 'Data Sources',
    format_item = function(c)
      return c.name .. (c.pc and (c.pc.ssh and '  (SSH)' or c.pc.proxy and '  (proxy)') or '')
    end,
  }, function(c, i)
    if c then
      M.open(i > 1 and c or nil)
    end
  end)
end

--- Disconnect (IDEA's Database → Disconnect): cancels running queries and closes the data
--- source's SSH tunnel / proxy; the next query connects again
function M.disconnect()
  local tunnels = require 'pc.db_tunnels'
  local list = read_connections()
  if #list == 0 then
    return vim.notify('No data sources', vim.log.levels.INFO)
  end
  vim.ui.select(list, {
    prompt = 'Disconnect',
    format_item = function(c)
      local up = c.pc and c.pc.local_port and tunnels.running(c.pc.local_port)
      return (up and '● ' or '  ') .. c.name
    end,
  }, function(c)
    if not c then
      return
    end
    local canceled = package.loaded['pc.db_console'] and require('pc.db_console').cancel(true)
    local closed = c.pc and c.pc.local_port and tunnels.stop(c.pc.local_port)
    vim.notify(('Disconnected %s%s%s'):format(c.name, closed and ' (tunnel closed)' or '', canceled and ', queries canceled' or ''))
  end)
end

--- Starts the tunnel of a saved connection by name (consoles, Database window)
function M.ensure_tunnel(name)
  for _, c in ipairs(read_connections()) do
    if c.name == name then
      local ok, err = require('pc.db_tunnels').ensure(c)
      if not ok then
        vim.notify(err, vim.log.levels.ERROR)
      end
      return ok
    end
  end
  return true
end

vim.api.nvim_create_user_command('DBAddConnection', M.add, { desc = 'New data source' })
vim.api.nvim_create_user_command('DBDataSources', M.manage, { desc = 'Data sources' })
vim.keymap.set('n', '<leader>Qd', M.manage, { desc = 'Data sources (edit / new)' })
vim.keymap.set('n', '<leader>Qx', M.disconnect, { desc = 'Disconnect data source' })
vim.api.nvim_create_user_command('DBDisconnect', M.disconnect, { desc = 'Disconnect a data source' })

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'dbui',
  group = vim.api.nvim_create_augroup('pc-db-connections', { clear = true }),
  callback = function(event)
    vim.keymap.set('n', 'a', M.add, { buffer = event.buf, desc = 'New data source' })
    vim.keymap.set('n', '<M-Insert>', M.add, { buffer = event.buf, desc = 'New data source' })
    vim.keymap.set('n', 'E', M.manage, { buffer = event.buf, desc = 'Edit data sources' })
    vim.keymap.set('n', 'X', M.disconnect, { buffer = event.buf, desc = 'Disconnect' })
    -- tunnels of the listed connections, so expanding one just works
    vim.schedule(function()
      for _, c in ipairs(read_connections()) do
        if c.pc and c.pc.local_port then
          M.ensure_tunnel(c.name)
        end
      end
    end)
  end,
})

return M
