-- Query consoles, like IDEA's database consoles: several named consoles per connection, a
-- schema per console, query history and Cancel.
--   <leader>Qq   open a console (or "New console…": pick the connection, name it)
--   <leader>Qs   choose the schema of this console (PostgreSQL: search_path, MySQL: database)
--   <leader>Qh   query history (all connections): Enter puts the query into the console
--   Ctrl+F2 / <leader>Qc   cancel the running query (also Ctrl+C in the results)
--   Alt+Enter    execute the statement under the cursor / the selection (plugins/database.lua)
-- Consoles are plain .sql files outside the projects (stdpath data /dadbod/consoles), so they
-- keep their text between sessions. The window shows "connection › schema" on top.

local M = {}

local root = vim.fn.stdpath 'data' .. '/dadbod'
local consoles_dir = root .. '/consoles'
local meta_file = root .. '/consoles.json'
local history_file = root .. '/history.json'
local HISTORY_MAX = 500

local function read_json(path, default)
  local f = io.open(path)
  if not f then
    return default
  end
  local ok, value = pcall(vim.json.decode, f:read '*a')
  f:close()
  return ok and type(value) == 'table' and value or default
end

local function write_json(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local f = assert(io.open(path, 'w'))
  f:write(vim.json.encode(value))
  f:close()
end

local function connections()
  require('lazy').load { plugins = { 'vim-dadbod-ui' } }
  return vim.fn['db_ui#connections_list']()
end

local function connection_url(name)
  for _, c in ipairs(connections()) do
    if c.name == name then
      -- SSH tunnel / proxy of the data source (db_connections)
      require('pc.db_connections').ensure_tunnel(name)
      return c.url
    end
  end
end

local function set_param(url, key, value)
  url = url:gsub('([?&])' .. key .. '=[^&]*&?', '%1'):gsub('[?&]$', '')
  return url .. (url:find '?' and '&' or '?') .. key .. '=' .. value
end

-- Console queries are tagged with this application_name, so Cancel can stop them on the server
local APP = 'nvim-console-' .. vim.fn.getpid()
local pg_urls = {}

-- ?options=-csearch_path=<schema> (libpq) / the database in the path (MySQL)
local function with_schema(url, schema)
  if url:match '^postgres' then
    url = set_param(url, 'application_name', APP)
    pg_urls[url] = true
    return schema and set_param(url, 'options', '-csearch_path%3D' .. schema) or url
  elseif schema and (url:match '^mysql' or url:match '^mariadb') then
    return (url:gsub('^([^:]+://[^/?]*)/?[^?]*', '%1/' .. schema, 1))
  end
  return url
end

--- Console of a buffer: { conn = name, schema = name? } or nil
local function console_of(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return vim.startswith(name, consoles_dir .. '/') and read_json(meta_file, {})[name] or nil
end

local function label(c)
  return '󰆼 ' .. c.conn .. (c.schema and (' › ' .. c.schema) or '')
end

--- The URL Alt+Enter runs on in this buffer, or nil to use dadbod-ui / b:db
function M.url(buf)
  local c = console_of(buf or 0)
  if c then
    local url = connection_url(c.conn)
    return url and with_schema(url, c.schema)
  end
  return vim.b[buf or 0].pc_db_url
end

local function show_label(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local c = console_of(buf)
  if c then
    vim.wo[win].winbar = '%#Title#' .. label(c):gsub('%%', '%%%%')
    vim.w[win].pc_console_winbar = true
  elseif vim.w[win].pc_console_winbar then
    vim.wo[win].winbar = ''
    vim.w[win].pc_console_winbar = nil
  end
end

local function open_console(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  show_label(0)
end

local function new_console(conn_name)
  local function create(conn)
    local default = 'console'
    local n = 1
    while vim.uv.fs_stat(('%s/%s/%s.sql'):format(consoles_dir, conn, default)) do
      n = n + 1
      default = 'console_' .. n
    end
    vim.ui.input({ prompt = 'Console name: ', default = default }, function(name)
      if not name or name == '' then
        return
      end
      local path = ('%s/%s/%s.sql'):format(consoles_dir, conn, name:gsub('[/\\]', '_'))
      vim.fn.mkdir(vim.fs.dirname(path), 'p')
      if not vim.uv.fs_stat(path) then
        vim.fn.writefile({}, path)
      end
      local meta = read_json(meta_file, {})
      meta[path] = meta[path] or { conn = conn }
      write_json(meta_file, meta)
      open_console(path)
    end)
  end
  if conn_name then
    return create(conn_name)
  end
  local list = connections()
  if #list == 0 then
    return vim.notify('No connections yet: add one in the Database window (<leader>S, a)', vim.log.levels.WARN)
  end
  vim.ui.select(list, {
    prompt = 'New console on',
    format_item = function(c)
      return c.name
    end,
  }, function(c)
    if c then
      create(c.name)
    end
  end)
end

function M.open()
  local meta = read_json(meta_file, {})
  local items = { { new = true } }
  for path, c in pairs(meta) do
    if vim.uv.fs_stat(path) then
      table.insert(items, { path = path, c = c, mtime = vim.uv.fs_stat(path).mtime.sec })
    end
  end
  table.sort(items, function(a, b)
    if a.new or b.new then
      return a.new == true
    end
    return a.mtime > b.mtime
  end)
  vim.ui.select(items, {
    prompt = 'Query consoles',
    format_item = function(item)
      if item.new then
        return '+ New console…'
      end
      return ('%-24s %s'):format(vim.fn.fnamemodify(item.path, ':t:r'), label(item.c))
    end,
  }, function(item)
    if item and item.new then
      new_console()
    elseif item then
      open_console(item.path)
    end
  end)
end

local function list_schemas(url)
  if url:match '^postgres' then
    local result = vim
      .system({
        'psql',
        '-X',
        '-w',
        '-At',
        url,
        '-c',
        "select schema_name from information_schema.schemata where schema_name !~ '^(pg_|information_schema$)' order by 1",
      }, { text = true, timeout = 10000 })
      :wait()
    if result.code ~= 0 then
      return nil, vim.trim(result.stderr or '')
    end
    return vim.split(vim.trim(result.stdout), '\n', { trimempty = true })
  elseif url:match '^mysql' or url:match '^mariadb' then
    return vim.fn['db#adapter#call'](url, 'complete_database', { url }, {})
  end
  return nil, 'this database has no schemas to choose'
end

function M.choose_schema()
  local buf = vim.api.nvim_get_current_buf()
  local c = console_of(buf)
  if not c then
    return vim.notify('Choose schema works in a query console (<leader>Qq)', vim.log.levels.WARN)
  end
  local url = connection_url(c.conn)
  if not url then
    return vim.notify('Connection "' .. c.conn .. '" no longer exists', vim.log.levels.ERROR)
  end
  local schemas, err = list_schemas(url)
  if not schemas then
    return vim.notify('Choose schema: ' .. err, vim.log.levels.WARN)
  end
  table.insert(schemas, 1, '(default)')
  vim.ui.select(schemas, { prompt = 'Schema for ' .. c.conn }, function(schema)
    if not schema then
      return
    end
    local meta = read_json(meta_file, {})
    local path = vim.api.nvim_buf_get_name(buf)
    meta[path].schema = schema ~= '(default)' and schema or nil
    write_json(meta_file, meta)
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      show_label(win)
    end
  end)
end

--- Called by Alt+Enter with the lines it is about to run
function M.record(lines, conn)
  local query = vim.trim(table.concat(lines, '\n'))
  if query == '' then
    return
  end
  local history = read_json(history_file, {})
  if history[1] and history[1].query == query and history[1].conn == conn then
    history[1].time = os.time()
  else
    table.insert(history, 1, { time = os.time(), conn = conn, query = query })
  end
  while #history > HISTORY_MAX do
    table.remove(history)
  end
  write_json(history_file, history)
end

--- Connection name for the history, as the user knows it
function M.connection_name(buf)
  local c = console_of(buf)
  if c then
    return c.conn .. (c.schema and ('.' .. c.schema) or '')
  end
  local key = vim.b[buf].dbui_db_key_name
  return key and key:gsub('_[^_]*$', '') or 'b:db'
end

function M.history()
  local history = read_json(history_file, {})
  if #history == 0 then
    return vim.notify 'Query history is empty'
  end
  local target = vim.api.nvim_get_current_buf()
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local previewers = require 'telescope.previewers'
  local actions = require 'telescope.actions'
  local state = require 'telescope.actions.state'
  pickers
    .new({}, {
      prompt_title = 'Query History',
      finder = finders.new_table {
        results = history,
        entry_maker = function(h)
          local one_line = h.query:gsub('%s+', ' ')
          local display = ('%s  %-16s %s'):format(os.date('%m-%d %H:%M', h.time), h.conn, one_line)
          return { value = h, display = display, ordinal = h.conn .. ' ' .. one_line }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      previewer = previewers.new_buffer_previewer {
        title = 'Query',
        define_preview = function(self, entry)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(entry.value.query, '\n'))
          vim.bo[self.state.bufnr].filetype = 'sql'
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not entry then
            return
          end
          local lines = vim.split(entry.value.query, '\n')
          if vim.bo[target].filetype ~= 'sql' then
            return vim.notify('Query history: open a console first (<leader>Qq)', vim.log.levels.WARN)
          end
          -- after the last line, separated by an empty line, like IDEA pastes into the console
          local last = vim.api.nvim_buf_line_count(target)
          local blank = vim.api.nvim_buf_get_lines(target, last - 1, last, false)[1] == ''
          if not blank then
            table.insert(lines, 1, '')
          end
          vim.api.nvim_buf_set_lines(target, last, last, false, lines)
          vim.api.nvim_win_set_cursor(0, { last + (blank and 1 or 2), 0 })
        end)
        return true
      end,
    })
    :find()
end

-- Running queries: dadbod fires User <output>/DBExecutePre and …/DBExecutePost
local running = {}

vim.api.nvim_create_autocmd('User', {
  pattern = { '*DBExecutePre', '*DBExecutePost' },
  group = vim.api.nvim_create_augroup('pc-db-console-running', { clear = true }),
  callback = function(event)
    local output = vim.fs.dirname(event.match)
    if vim.endswith(event.match, 'Pre') then
      running[output] = true
    else
      running[output] = nil
    end
  end,
})

-- Killing psql leaves the statement running on the server: cancel it there too
local function cancel_on_server()
  for url in pairs(pg_urls) do
    vim.system {
      'psql',
      '-X',
      '-w',
      '-qAt',
      (url:gsub('[?&]options=[^&]*', '')),
      '-c',
      ("select pg_cancel_backend(pid) from pg_stat_activity where application_name = '%s' and pid <> pg_backend_pid()"):format(APP),
    }
  end
end

function M.cancel()
  local any = false
  for output in pairs(running) do
    local buf = vim.fn.bufnr(output)
    if buf > 0 then
      vim.fn['db#cancel'](buf)
      any = true
    end
    running[output] = nil
  end
  if any then
    cancel_on_server()
  end
  vim.notify(any and 'Query canceled' or 'No query is running')
end

vim.keymap.set('n', '<leader>Qq', M.open, { desc = 'Open query console' })
vim.keymap.set('n', '<leader>Qs', M.choose_schema, { desc = 'Choose schema' })
vim.keymap.set('n', '<leader>Qh', M.history, { desc = 'Query history' })
vim.keymap.set('n', '<leader>Qc', M.cancel, { desc = 'Cancel query' })

local group = vim.api.nvim_create_augroup('pc-db-console', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'sql', 'mysql', 'plsql', 'dbout' },
  group = group,
  callback = function(event)
    for _, lhs in ipairs { '<C-F2>', '<F26>' } do
      vim.keymap.set('n', lhs, M.cancel, { buffer = event.buf, desc = 'Cancel query' })
    end
  end,
})

vim.api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  callback = function()
    show_label(0)
  end,
})

-- Consoles save themselves, like in IDEA (no swap file, no "save changes?")
vim.api.nvim_create_autocmd('BufReadPre', {
  group = group,
  pattern = consoles_dir .. '/*',
  callback = function(event)
    vim.bo[event.buf].swapfile = false
  end,
})
vim.api.nvim_create_autocmd({ 'InsertLeave', 'TextChanged', 'BufLeave', 'FocusLost', 'VimLeavePre' }, {
  group = group,
  pattern = consoles_dir .. '/*',
  callback = function(event)
    if vim.bo[event.buf].modified and vim.api.nvim_buf_is_loaded(event.buf) then
      vim.api.nvim_buf_call(event.buf, function()
        vim.cmd 'silent! update'
      end)
    end
  end,
})

return M
