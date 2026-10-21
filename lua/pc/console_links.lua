-- File links in the Run window and terminals, like IDEA's console: Enter or a double click on a
-- line with a location opens it in the editor, at the line and column:
--   javac / Maven   /path/File.java:[11,39]          gcc / clang / ruff …   path:12:5: error
--   Python          File "path", line 12             Java stack traces      at a.B.c(File.java:123)
-- Relative paths are taken from the command's directory; a stack trace's file is looked for in
-- the project. A line without a location does what Enter / the click normally does.

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

--- Enter / double click on a location in `buf` (a terminal or console) opens it; cwd: where
--- relative paths start (a function for terminals that change directory)
function M.attach(buf, cwd)
  for _, lhs in ipairs { '<CR>', '<2-LeftMouse>', 'gf' } do
    vim.keymap.set('n', lhs, function()
      local dir = type(cwd) == 'function' and cwd() or cwd or vim.fn.getcwd()
      if not M.follow(vim.api.nvim_get_current_win(), dir) then
        vim.api.nvim_feedkeys(vim.keycode(lhs), 'n', false)
      end
    end, { buffer = buf, desc = 'Open the file:line under the cursor' })
  end
end

return M
