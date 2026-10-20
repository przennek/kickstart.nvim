-- Notifications tool window like IDEA's: messages from plugins (vim.notify, LSP messages) and
-- background tasks (LSP progress) are collected here instead of popping up at the bottom.
--   <leader>tn / :Notifications   show / hide the window (on the right)
--   in the window: y copy the message, C clear all, q close
-- The status bar shows a spinner with the running background task, the last message for a few
-- seconds and 󰂚 N for unread ones (red when one of them is an error). Errors are also echoed
-- once in the command line (Settings → Editor → Notifications).

local M = {}

local NAMES = { [0] = 'TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR' }
local HL = { TRACE = 'Comment', DEBUG = 'Comment', INFO = 'DiagnosticInfo', WARN = 'DiagnosticWarn', ERROR = 'DiagnosticError' }
local ICON = { TRACE = '·', DEBUG = '·', INFO = '', WARN = '', ERROR = '' }
local SPINNER = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local MAX = 500
local SHOW_LAST = 4000 -- ms the last message stays in the status bar

local log = {} -- newest last: { time, level, title, msg }
local tasks = {} -- running LSP progress: key -> { title, message, percentage, client }
local unread, unread_error = 0, false
local last, last_timer, spin, spin_timer = nil, nil, 1, nil
local buf, win, line_entry = nil, nil, {}

local function setting(key, default)
  local cfg = vim.g.pc_settings
  if cfg and cfg[key] ~= nil then
    return cfg[key]
  end
  return default
end

local function visible()
  return win and vim.api.nvim_win_is_valid(win)
end

local function redrawstatus()
  pcall(vim.cmd.redrawstatus, { bang = true })
end

local function render()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local lines, marks = {}, {}
  line_entry = {}
  local function add(text, hl, entry)
    table.insert(lines, text)
    line_entry[#lines] = entry
    if hl then
      table.insert(marks, { #lines - 1, hl })
    end
  end
  local running = vim.tbl_values(tasks)
  if #running > 0 then
    add('Running', 'Title')
    for _, t in ipairs(running) do
      local pct = t.percentage and (' ' .. t.percentage .. '%') or ''
      add(('  %s %s%s  %s'):format(t.client, t.title or '', pct, t.message or ''), 'Comment')
    end
    add ''
  end
  if #log == 0 then
    add('No notifications', 'Comment')
  end
  for i = #log, 1, -1 do
    local e = log[i]
    add(('%s %s %s'):format(os.date('%H:%M:%S', e.time), ICON[e.level], e.title or e.level:lower()), HL[e.level], i)
    for _, l in ipairs(vim.split(e.msg, '\n', { trimempty = true })) do
      add('  ' .. l, nil, i)
    end
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local ns = vim.api.nvim_create_namespace 'pc-notifications'
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, m[1], 0, { end_row = m[1] + 1, hl_group = m[2], hl_eol = false })
  end
end

local function changed()
  if visible() then
    unread, unread_error = 0, false
    render()
  end
  redrawstatus()
end

local function add(msg, level, opts)
  msg = type(msg) == 'string' and msg or vim.inspect(msg)
  local name = NAMES[type(level) == 'number' and level or vim.log.levels.INFO] or 'INFO'
  table.insert(log, { time = os.time(), level = name, title = opts and opts.title, msg = msg })
  if #log > MAX then
    table.remove(log, 1)
  end
  if name == 'DEBUG' or name == 'TRACE' then
    return changed()
  end
  unread = unread + 1
  unread_error = unread_error or name == 'ERROR'
  local first = vim.split(vim.trim(msg), '\n')[1] or ''
  if name == 'ERROR' and setting('notify_echo_errors', true) then
    -- one screen line at most: a longer message would stop everything at "Press ENTER"
    local more = '  (<leader>tn)'
    local room = math.max(10, vim.v.echospace - #more - 1)
    local text = vim.fn.strdisplaywidth(first) > room and (vim.fn.strcharpart(first, 0, room - 1) .. '…') or first
    vim.api.nvim_echo({ { text, 'ErrorMsg' }, { more, 'Comment' } }, true, {})
  end
  if setting('notify_status_bar', true) then
    last = { text = first, level = name }
    if last_timer then
      last_timer:stop()
    end
    last_timer = vim.defer_fn(function()
      last = nil
      redrawstatus()
    end, SHOW_LAST)
  end
  changed()
end

--- Replacement for vim.notify: logs instead of printing
function M.notify(msg, level, opts)
  if vim.in_fast_event() then
    return vim.schedule(function()
      add(msg, level, opts)
    end)
  end
  add(msg, level, opts)
end

--- Logged notifications, oldest first: { time, level, title, msg }
function M.entries()
  return vim.deepcopy(log)
end

--- Status bar part: spinner + running task, the last message, unread count
function M.status()
  local parts = {}
  local running = vim.tbl_values(tasks)
  if #running > 0 then
    local t = running[1]
    table.insert(parts, ('%s %s%s'):format(SPINNER[spin], t.title or t.client, t.percentage and (' ' .. t.percentage .. '%%') or ''))
  end
  if last then
    local text = last.text:gsub('%%', '%%%%')
    if vim.fn.strchars(text) > 60 then
      text = vim.fn.strcharpart(text, 0, 59) .. '…'
    end
    table.insert(parts, text)
  end
  if unread > 0 then
    table.insert(parts, unread_error and ('%#DiagnosticError#󰂚 ' .. unread .. '%*') or ('󰂚 ' .. unread))
  end
  return table.concat(parts, '  ')
end

function M.toggle()
  if visible() then
    vim.api.nvim_win_close(win, true)
    win = nil
    return
  end
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, 'Notifications')
    vim.bo[buf].filetype = 'pcnotifications'
    vim.bo[buf].bufhidden = 'hide'
    local function bmap(lhs, fn, desc)
      vim.keymap.set('n', lhs, fn, { buffer = buf, desc = desc })
    end
    bmap('q', M.toggle, 'Close')
    bmap('C', function()
      log = {}
      changed()
    end, 'Clear all')
    bmap('y', function()
      local e = log[line_entry[vim.fn.line '.'] or 0]
      if e then
        vim.fn.setreg('+', e.msg)
        vim.fn.setreg('"', e.msg)
      end
    end, 'Copy the message')
  end
  local from = vim.api.nvim_get_current_win()
  vim.cmd('botright vertical sbuffer ' .. buf)
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, 60)
  for opt, value in pairs { number = false, relativenumber = false, signcolumn = 'no', winfixwidth = true, wrap = true, linebreak = true, list = false, cursorline = true } do
    vim.wo[win][opt] = value
  end
  vim.wo[win].winbar = '%#Title# Notifications %*%#Comment#  y copy · C clear · q close'
  changed()
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  -- like IDEA's tool window: shown, the editor keeps the focus
  vim.api.nvim_set_current_win(from)
end

-- LSP background tasks: running ones in the status bar and at the top of the window
vim.api.nvim_create_autocmd('LspProgress', {
  group = vim.api.nvim_create_augroup('pc-notifications', { clear = true }),
  callback = function(event)
    local value = event.data.params.value
    if type(value) ~= 'table' then
      return
    end
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    local key = event.data.client_id .. ':' .. tostring(event.data.params.token)
    if value.kind == 'end' then
      tasks[key] = nil
    else
      local t = tasks[key] or { client = client and client.name or 'lsp', title = value.title }
      t.message, t.percentage = value.message, value.percentage
      tasks[key] = t
    end
    if next(tasks) and not spin_timer then
      spin_timer = vim.uv.new_timer()
      spin_timer:start(0, 120, vim.schedule_wrap(function()
        spin = spin % #SPINNER + 1
        redrawstatus()
      end))
    elseif not next(tasks) and spin_timer then
      spin_timer:stop()
      spin_timer:close()
      spin_timer = nil
    end
    changed()
  end,
})

vim.notify = M.notify
vim.keymap.set('n', '<leader>tn', M.toggle, { desc = '[T]oggle [n]otifications window' })
vim.api.nvim_create_user_command('Notifications', M.toggle, { desc = 'Notifications window' })

return M
