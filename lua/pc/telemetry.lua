-- Your moves in the error log (pc.error_log), next to the errors they led to, so the ways you
-- work can be replayed in the regression tests:
--   Normal / Visual keys and shortcuts as typed (mouse clicks too), grouped per mode, window
--   and file:   move  [src/…/OrderService.java]  n java: j×5 w <M-d> q
--   text typed in a file, a prompt or a terminal is not written, only how much (+12 chars),
--   with the special keys among it (<Esc>, <C-k>, <M-1>…)
--   Ex commands (:…) and searches (/…) are NOT written as entered: they carry data you typed
--   (a path, a URL, a token in a :!curl, a search word), and the log is sent on as a whole.
--   M.mask() keeps how you work and drops what you typed:
--     search  /  ?      only the kind and the length:  /(+7 chars)
--     command :         range, command name, a "!" right after it; the arguments only as length:
--                       :%s(+14 chars)  :e (+23 chars)  :!(+31 chars)  :'<,'>q  :12  :wq
--   (the exact rules are above M.mask)
-- Settings → Editor → "Record my moves in the error log" turns it off.

local M = {}

local log = require 'pc.error_log'

-- Masks what was entered on the command line before it is logged, so that what you typed as
-- data (paths, shell commands, patterns, identifiers) never reaches the log, only how you work.
--
--   kind '/' or '?'  ->  kind .. '(+N chars)' (just '/' for an empty search); N counts characters.
--   kind ':'         ->  ':' .. range .. name .. bang .. [' '] .. '(+N chars)'
--     range  leading line specifiers, spaces dropped: digits . $ % , ; + - and marks ('a '< '>).
--            A /pattern/ range is data, not a range: it is counted with the arguments.
--     name   the command name: letters only when it starts lowercase (built-ins: so that
--            `s1a1b` cannot smuggle text into it), letters and digits when it starts uppercase
--            (user commands: Git2). It ends where the next character is not one of those, so
--            `:s/a/b/` and `:g/x/d` have no space before their arguments. Abbreviated or
--            misspelt names stay as typed (:Wq, :Qa!).
--     bang   a '!' directly after the name (:q!). A bare `:!cmd` has no name: '!' is its bang.
--     args   everything after that, written only as its length. One space is kept if the
--            line had whitespace there (`:e (+23 chars)`, `:%s(+14 chars)`); no args, nothing.
-- Surrounding whitespace is dropped; a line of only a range (:12, :%) is kept as it is.
-- When the config rewrites what you typed (cmdline_enter: `:q` in a diff) the rewritten line
-- is what is masked: `:lua (+N chars)`.
---@param kind string ':' | '/' | '?'
---@param line string
---@return string
function M.mask(kind, line)
  line = vim.trim(line)
  if kind ~= ':' then
    return line == '' and kind or ('%s(+%d chars)'):format(kind, vim.fn.strchars(line))
  end
  local pos = 1
  local range = ''
  -- leading colons and blanks are noise; then range pieces, one mark ('x) at a time
  pos = line:find('[^:%s]', pos) or #line + 1
  while true do
    local piece = line:match('^[%d%.%$%%,;+%-]+', pos) or line:match("^'.", pos)
    if not piece then
      local blanks = line:match('^%s+', pos)
      if not blanks or pos + #blanks > #line then
        break
      end
      pos = pos + #blanks
    else
      range = range .. piece
      pos = pos + #piece
    end
  end
  local rest = line:sub(pos)
  local name = rest:match '^%l%a*' or rest:match '^%u%w*' or ''
  rest = rest:sub(#name + 1)
  local bang = ''
  if rest:sub(1, 1) == '!' then
    bang, rest = '!', rest:sub(2)
  end
  local gap = rest:match '^%s' and ' ' or ''
  local args = vim.trim(rest)
  local masked = ':' .. range .. name .. bang
  if args ~= '' then
    masked = masked .. gap .. ('(+%d chars)'):format(vim.fn.strchars(args))
  end
  return masked
end

local function enabled()
  local cfg = vim.g.pc_settings
  return not (cfg and cfg.telemetry == false)
end

---@type { ctx: string, where: string, keys: string[], typed: integer }?
local group
local timer = vim.uv.new_timer()
local recent = '' -- the last keys typed, as keytrans() text

local function write(g)
  if not g or (#g.keys == 0 and g.typed == 0) then
    return
  end
  local keys = table.concat(g.keys, ' ')
  if g.typed > 0 then
    keys = keys .. (keys ~= '' and ' ' or '') .. ('(+%d chars)'):format(g.typed)
  end
  log.record('move', g.ctx .. ': ' .. keys, g.where)
end

local function flush()
  local g = group
  group = nil
  write(g)
end

-- "n java", "t toggleterm", "n java diff", "i TelescopePrompt popup" and the file it is in
local function context(mode)
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local kind = vim.bo[buf].filetype ~= '' and vim.bo[buf].filetype or (vim.bo[buf].buftype ~= '' and vim.bo[buf].buftype or 'text')
  if vim.wo.diff then
    kind = kind .. ' diff'
  end
  if vim.api.nvim_win_get_config(0).relative ~= '' then
    kind = kind .. ' popup'
  end
  local where = (vim.bo[buf].buftype == '' and name ~= '') and vim.fn.fnamemodify(name, ':~:.')
    or (name:match '^%a+://' and name:gsub('^(%a+://).-([^/]+)$', '%1…/%2') or kind)
  return mode .. ' ' .. kind, where
end

-- modes whose printable keys are text
local TEXT_MODES = { i = true, R = true, t = true, c = true }

vim.on_key(function(_, typed)
  if not typed or typed == '' or not enabled() then
    return
  end
  local mode = vim.api.nvim_get_mode().mode
  local short = mode:sub(1, 1)
  -- the command line is written whole when it is entered (CmdlineLeave)
  if short == 'c' then
    return
  end
  local key = vim.fn.keytrans(typed)
  -- which-key replays a combination it waited on (g d → gd, <Space> d → <Space>d): written once
  local replay = #key:gsub('<[^>]+>', 'x') > 1 and recent:sub(-#key) == key
  recent = (recent .. key):sub(-64)
  if replay then
    return
  end
  local ctx, where = context(short)
  if group and (group.ctx ~= ctx or group.where ~= where) then
    local old = group
    vim.schedule(function()
      write(old)
    end)
    group = nil
  end
  group = group or { ctx = ctx, where = where, keys = {}, typed = 0 }
  if TEXT_MODES[short] and vim.fn.strchars(key) == 1 or (TEXT_MODES[short] and key == '<Space>') then
    group.typed = group.typed + 1
  else
    -- the same key again: j×5
    local last = group.keys[#group.keys]
    local base, n = (last or ''):match '^(.-)×(%d+)$'
    if last == key then
      group.keys[#group.keys] = key .. '×2'
    elseif base == key then
      group.keys[#group.keys] = key .. '×' .. (tonumber(n) + 1)
    else
      table.insert(group.keys, key)
    end
  end
  if #group.keys >= 40 then
    local old = group
    group = nil
    vim.schedule(function()
      write(old)
    end)
  end
  -- a pause ends the group
  timer:stop()
  timer:start(1500, 0, vim.schedule_wrap(flush))
end, vim.api.nvim_create_namespace 'pc-telemetry')

vim.api.nvim_create_autocmd('CmdlineLeave', {
  group = vim.api.nvim_create_augroup('pc-telemetry', { clear = true }),
  callback = function()
    local kind = vim.fn.getcmdtype()
    if not enabled() or vim.v.event.abort or not (kind == ':' or kind == '/' or kind == '?') then
      return
    end
    local line = vim.fn.getcmdline()
    vim.schedule(function()
      flush()
      log.record('move', M.mask(kind, line))
    end)
  end,
})
vim.api.nvim_create_autocmd('VimLeavePre', { group = 'pc-telemetry', callback = flush })

return M
