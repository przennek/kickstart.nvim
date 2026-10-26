-- File links in the Run window and terminals, like IDEA's console: Enter or a double click on a
-- line with a location opens it in the editor, at the line and column:
--   javac / Maven   /path/File.java:[11,39]          gcc / clang / ruff …   path:12:5: error
--   Python          File "path", line 12             Java stack traces      at a.B.c(File.java:123)
-- Relative paths are taken from the command's directory; a stack trace's file is looked for in
-- the project. A line without a location does what Enter / the click normally does.
-- URLs (http/https) open in the browser; gd / gx and Ctrl / Alt (Cmd) + click open as well.

local M = {}

-- the line under the cursor with the lines the terminal wrapped it into
local function logical_line(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local width = vim.api.nvim_win_get_width(win)
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local function get(n)
    return vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1]
  end
  local first, last = row, row
  while first > 1 and #(get(first - 1) or '') >= width - 1 do
    first = first - 1
  end
  while #(get(last) or '') >= width - 1 and get(last + 1) do
    last = last + 1
  end
  return table.concat(vim.api.nvim_buf_get_lines(buf, first - 1, last, false), '')
end

local function exists(path)
  return path and vim.uv.fs_stat(path) and vim.fn.isdirectory(path) == 0
end

-- { path, line, col } of the first location in `text`
function M.parse(text, cwd)
  local function resolve(p)
    if not p then
      return nil
    end
    p = vim.trim(p)
    if not p:match '^/' then
      p = vim.fs.joinpath(cwd, p)
    end
    return exists(p) and vim.fs.normalize(p) or nil
  end
  -- javac / Maven: path:[line,col]
  local p, l, c = text:match '([%w%._%-/~]+%.%w+):%[(%d+),(%d+)%]'
  if resolve(p) then
    return { resolve(p), tonumber(l), tonumber(c) }
  end
  -- Python traceback
  p, l = text:match 'File "([^"]+)", line (%d+)'
  if resolve(p) then
    return { resolve(p), tonumber(l), 1 }
  end
  -- path:line(:col)
  for path, line, col in text:gmatch '([%w%._%-/~]+%.%w+):(%d+):?(%d*)' do
    if resolve(path) then
      return { resolve(path), tonumber(line), tonumber(col) or 1 }
    end
  end
  -- Java stack trace frame: (File.java:123) — the file somewhere in the project
  local file, line = text:match '%(([%w_$]+%.java):(%d+)%)'
  if file then
    local found = vim.fs.find(file, { path = cwd, type = 'file', limit = 1 })[1]
    if found then
      return { found, tonumber(line), 1 }
    end
  end
end

-- the editor window to open files in: the last one with a file, else a new split above
local function editor_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative == '' and vim.bo[buf].buftype == '' then
      return win
    end
  end
  vim.cmd 'aboveleft split'
  return vim.api.nvim_get_current_win()
end

--- Opens the location on the cursor line of `win`; false when there is none
function M.follow(win, cwd)
  local loc = M.parse(logical_line(win), cwd)
  if not loc then
    return false
  end
  local target = editor_window()
  vim.api.nvim_set_current_win(target)
  vim.cmd.edit(vim.fn.fnameescape(loc[1]))
  pcall(vim.api.nvim_win_set_cursor, target, { loc[2], math.max((loc[3] or 1) - 1, 0) })
  vim.cmd 'normal! zz'
  return true
end

-- the URL under the cursor, else the first one on the line
local function url_at(win)
  local pattern = "https?://[%w%-%._~:/%?#%[%]@!%$&'%*%+,;=%%]+"
  local function clean(u)
    return (u:gsub('[%.,;:!%?\'"%]]+$', ''))
  end
  local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), vim.api.nvim_win_get_cursor(win)[1] - 1, vim.api.nvim_win_get_cursor(win)[1], false)[1] or ''
  local col = vim.api.nvim_win_get_cursor(win)[2] + 1
  local init = 1
  while true do
    local from, to = line:find(pattern, init)
    if not from then
      break
    end
    if col >= from and col <= to then
      return clean(line:sub(from, to))
    end
    init = to + 1
  end
  local first = logical_line(win):match(pattern)
  return first and clean(first)
end

local cwds = {} -- buf -> cwd (a string or a function)

local function dir_of(buf)
  local cwd = cwds[buf]
  return type(cwd) == 'function' and cwd() or cwd or vim.fn.getcwd()
end

--- Opens the file:line or the URL under the cursor; false when there is none
function M.open(win)
  win = win or vim.api.nvim_get_current_win()
  if M.follow(win, dir_of(vim.api.nvim_win_get_buf(win))) then
    return true
  end
  local url = url_at(win)
  if url then
    vim.ui.open(url)
    return true
  end
  return false
end

--- Ctrl / Alt (Cmd) + click: the link where the mouse is
function M.click()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then
    return
  end
  vim.api.nvim_set_current_win(pos.winid)
  pcall(vim.api.nvim_win_set_cursor, pos.winid, { pos.line, math.max(pos.column - 1, 0) })
  M.open(pos.winid)
end

--- Enter / double click / gd / gx / Ctrl+click / Alt (Cmd)+click on a location or a URL in
--- `buf` (a terminal or console) opens it; cwd: where relative paths start (a function for
--- terminals that change directory)
function M.attach(buf, cwd)
  cwds[buf] = cwd
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      cwds[buf] = nil
    end,
  })
  for _, lhs in ipairs { '<CR>', '<2-LeftMouse>', 'gf' } do
    vim.keymap.set('n', lhs, function()
      if not M.open() then
        vim.api.nvim_feedkeys(vim.keycode(lhs), 'n', false)
      end
    end, { buffer = buf, desc = 'Open the file:line or link under the cursor' })
  end
  for _, lhs in ipairs { 'gd', 'gx' } do
    vim.keymap.set('n', lhs, function()
      if not M.open() then
        vim.notify('No file:line or link on this line', vim.log.levels.INFO)
      end
    end, { buffer = buf, desc = 'Open the file:line or link under the cursor' })
  end
  for _, lhs in ipairs { '<C-LeftMouse>', '<M-LeftMouse>' } do
    vim.keymap.set('n', lhs, M.click, { buffer = buf, desc = 'Open the link clicked' })
    vim.keymap.set('t', lhs, '<C-\\><C-n><cmd>lua require("pc.console_links").click()<cr>', { buffer = buf, desc = 'Open the link clicked' })
  end
end

return M
