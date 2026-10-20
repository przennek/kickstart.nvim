-- Database window on lazysql (https://github.com/jorgerojas26/lazysql), a TUI that works with
-- the data like IDEA's Database tool window: schema tree, table data in tabs, cells edited in
-- place (c, then Ctrl+S shows the UPDATE / INSERT / DELETE and asks before running it), rows
-- added / duplicated / deleted, WHERE filter, sorting, CSV export (E), rows copied as SQL /
-- JSON / CSV / Markdown (Y), SQL editor (Ctrl+E, Ctrl+R runs, Esc cancels) and its history
-- (Ctrl+_), foreign keys followed with Enter. ? lists its keys.
--   <leader>S          Database window (Settings → Editor → Database: lazysql or dadbod-ui):
--                      the data source of the current SQL console, else pick one
--   :DBTui [name]      open it on a data source
--   in the window:     Ctrl+Q hide (it keeps running), q quit lazysql; Alt+1…0 and other IDE
--                      keys go to the editor
-- It connects to the data sources of the Data Source dialog (<leader>Qd): their SSH tunnel /
-- proxy is started first, PostgreSQL passwords come from ~/.pgpass. Telemetry is always off.

local M = {}

local sessions = {} -- data source name -> terminal buffer
local last -- name of the last data source shown

function M.available()
  return vim.fn.executable 'lazysql' == 1
end

local function connections()
  return require('pc.db_connections').list()
end

local function find(name)
  for _, c in ipairs(connections()) do
    if c.name == name then
      return c
    end
  end
end

-- lazysql's PostgreSQL driver requires SSL unless told otherwise; local servers and tunnels
-- (127.0.0.1) have none
local function url_of(entry)
  local url = entry.url
  if url:match '^postgres' and not url:match '[?&]sslmode=' then
    local host = url:match '^%w+://[^@/]*@?([^:/?]*)'
    if host == '127.0.0.1' or host == 'localhost' or host == '' then
      url = url .. (url:find '?' and '&' or '?') .. 'sslmode=disable'
    end
  end
  return url
end

local function window_of(buf)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
end

local function hide()
  for _, buf in pairs(sessions) do
    local win = window_of(buf)
    if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then
      vim.api.nvim_win_close(win, false)
    end
  end
end

-- the window at the bottom, over the whole width like a tool window
local function show(buf)
  local win = nil
  for _, b in pairs(sessions) do
    win = win or window_of(b)
  end
  if win then
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd('botright sbuffer ' .. buf)
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(win, math.floor(vim.o.lines * 0.6))
  end
  for opt, value in pairs { number = false, relativenumber = false, signcolumn = 'no', winfixheight = true, list = false, cursorline = false } do
    vim.wo[win][opt] = value
  end
  vim.cmd 'startinsert'
end

local function start(entry)
  if not require('pc.db_connections').ensure_tunnel(entry.name) then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'
  sessions[entry.name] = buf
  show(buf)
  vim.fn.jobstart({ 'lazysql', '--no-telemetry', url_of(entry) }, {
    term = true,
    on_exit = function()
      vim.schedule(function()
        if sessions[entry.name] == buf then
          sessions[entry.name] = nil
        end
        local win = vim.api.nvim_buf_is_valid(buf) and window_of(buf)
        if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then
          vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end)
    end,
  })
  pcall(vim.api.nvim_buf_set_name, buf, 'Database: ' .. entry.name)
  vim.bo[buf].filetype = 'pcdbtui'
  vim.keymap.set('t', '<C-q>', function()
    vim.cmd 'stopinsert'
    vim.schedule(hide)
  end, { buffer = buf, desc = 'Hide the Database window' })
  -- back in the window = typing goes to lazysql (not when the window is only passed through,
  -- e.g. reopened by Hide All with the focus going back to the editor)
  vim.api.nvim_create_autocmd('BufEnter', {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_get_current_buf() == buf then
          vim.cmd 'startinsert'
        end
      end)
    end,
  })
end

--- Opens the Database window on the data source `name` (running one is shown again)
function M.open(name)
  if not M.available() then
    return vim.notify('lazysql is not installed (Arch: yay -S lazysql, macOS: brew install lazysql)', vim.log.levels.WARN)
  end
  local entry = find(name)
  if not entry then
    return vim.notify('No data source "' .. name .. '"', vim.log.levels.ERROR)
  end
  if entry.url:match '^mongodb' then
    return vim.notify('lazysql has no MongoDB support; use a console (<leader>Qq)', vim.log.levels.WARN)
  end
  last = name
  local buf = sessions[name]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return show(buf)
  end
  start(entry)
end

-- Data source of the current buffer: its SQL console / dadbod-ui query buffer
local function current_source()
  if not package.loaded['pc.db_console'] then
    return nil
  end
  local name = require('pc.db_console').connection_name(0)
  local best
  for _, c in ipairs(connections()) do
    if (name == c.name or vim.startswith(name, c.name .. '.')) and (not best or #c.name > #best) then
      best = c.name
    end
  end
  return best
end

--- Asks for a data source (the one of the current SQL console without asking)
function M.pick()
  local name = current_source()
  if name then
    return M.open(name)
  end
  local list = connections()
  if #list == 0 then
    vim.notify 'No data sources yet: add one in the Data Source dialog'
    return require('pc.db_connections').add()
  end
  if #list == 1 then
    return M.open(list[1].name)
  end
  vim.ui.select(list, {
    prompt = 'Database',
    format_item = function(c)
      local running = sessions[c.name] and vim.api.nvim_buf_is_valid(sessions[c.name])
      return (running and '● ' or '  ') .. c.name
    end,
  }, function(c)
    if c then
      M.open(c.name)
    end
  end)
end

--- The Database window key: shows the last one / asks, focuses, hides from inside
function M.toggle()
  local tw = require 'pc.tool_window'
  tw.activate(tw.filetypes 'pcdbtui', function()
    if vim.bo.filetype == 'pcdbtui' then
      return hide()
    end
    if last and sessions[last] and vim.api.nvim_buf_is_valid(sessions[last]) and not current_source() then
      return show(sessions[last])
    end
    M.pick()
  end, function()
    vim.cmd 'startinsert'
  end)()
end

vim.api.nvim_create_user_command('DBTui', function(opts)
  if opts.args ~= '' then
    M.open(opts.args)
  else
    M.pick()
  end
end, {
  nargs = '?',
  desc = 'Database window (lazysql)',
  complete = function()
    return vim.tbl_map(function(c)
      return c.name
    end, connections())
  end,
})

return M
