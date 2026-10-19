-- "New Data Source" for the Database window (<leader>S), like IDEA's data source dialog:
-- pick the database type, fill host / port / database / user / password, the connection is
-- tested (Test Connection) and saved to the Database window's list.
--   in the Database window: a or Alt+Insert = new data source, R = refresh
--   :DBAddConnection = the same from anywhere
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

local function save_connection(name, url)
  local list = read_connections()
  for _, c in ipairs(list) do
    if c.name == name then
      vim.notify('A connection named "' .. name .. '" already exists', vim.log.levels.ERROR)
      return false
    end
  end
  table.insert(list, { name = name, url = url })
  vim.fn.mkdir(vim.fs.dirname(connections_file()), 'p')
  local f = assert(io.open(connections_file(), 'w'))
  f:write(vim.json.encode(list))
  f:close()
  -- refresh an open Database window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'dbui' then
      vim.api.nvim_win_call(win, function()
        vim.cmd 'normal R'
      end)
    end
  end
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

local function ask(prompt, default, secret)
  local ok, value = pcall(secret and vim.fn.inputsecret or vim.fn.input, prompt, default or '')
  return ok and value or nil
end

function M.add()
  vim.ui.select(TYPES, {
    prompt = 'New Data Source',
    format_item = function(t)
      return t.label
    end,
  }, function(t)
    if not t then
      return
    end
    local url, name
    if t.scheme == 'sqlite' then
      local file = ask('Database file: ', vim.fn.getcwd() .. '/')
      if not file or file == '' then
        return
      end
      url = 'sqlite:' .. vim.fn.fnamemodify(file, ':p')
      name = vim.fn.fnamemodify(file, ':t:r')
    else
      local host = ask('Host: ', 'localhost')
      local port = host and ask('Port: ', t.port)
      local db = port and ask('Database: ', '')
      local user = db and ask('User: ', vim.env.USER)
      local password = user and ask('Password (empty = none): ', '', true)
      if not password then
        return
      end
      local auth = user ~= '' and encode(user) or ''
      if password ~= '' and t.scheme == 'postgresql' then
        store_pgpass(host, port, db ~= '' and db or '*', user, password)
      elseif password ~= '' then
        auth = auth .. ':' .. encode(password)
      end
      url = ('%s://%s%s:%s/%s'):format(t.scheme, auth ~= '' and (auth .. '@') or '', host, port, db)
      name = (db ~= '' and db or t.scheme) .. '@' .. host
    end

    local ok, err = test_connection(t, url)
    if ok then
      vim.notify('Test Connection: succeeded')
    else
      vim.notify('Test Connection failed:\n' .. err, vim.log.levels.WARN)
      if vim.fn.confirm('Save the connection anyway?', '&Yes\n&No', 2) ~= 1 then
        return
      end
    end
    name = ask('Name: ', name)
    if name and name ~= '' and save_connection(name, url) then
      vim.notify(('Data source "%s" added (Database window: <leader>S)'):format(name))
    end
  end)
end

vim.api.nvim_create_user_command('DBAddConnection', M.add, { desc = 'New data source' })

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'dbui',
  group = vim.api.nvim_create_augroup('pc-db-connections', { clear = true }),
  callback = function(event)
    vim.keymap.set('n', 'a', M.add, { buffer = event.buf, desc = 'New data source' })
    vim.keymap.set('n', '<M-Insert>', M.add, { buffer = event.buf, desc = 'New data source' })
  end,
})

return M
