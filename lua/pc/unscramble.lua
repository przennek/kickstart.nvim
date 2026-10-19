-- Analyze Stack Trace (IDEA's Unscramble):
--   <leader>U / :Unscramble   the stack trace from the clipboard in a window at the bottom: frames from
--                             this project are links (Enter jumps there), library frames are dimmed,
--                             and the project frames also go to the Find window (Alt+3, ]q / [q).
-- Paste another trace into that window (p, or edit it) and press R to analyze it again.
-- Java, Python, JavaScript / Node and C (gdb, sanitizers) traces; a trace squashed into one line
-- (logs, JSON with \n\tat …) is split back into frames first.

local M = {}

local ns = vim.api.nvim_create_namespace 'pc-unscramble'
local frames_of = {} -- buffer → { line → frame }

-- One-line and escaped traces back into one frame per line
local function normalize(text)
  text = text:gsub('\\r\\n', '\n'):gsub('\\n', '\n'):gsub('\\t', '\t'):gsub('\r', '')
  local lines = {}
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    -- "… at a.B.c(B.java:1) at a.B.d(B.java:2)" → one frame per line
    line = line:gsub('(%S)%s+(at [%w_$.<>/]+%()', '%1\n\t%2'):gsub('(%S)%s+(Caused by: )', '%1\n%2')
    vim.list_extend(lines, vim.split(line, '\n', { plain = true }))
  end
  while lines[#lines] == '' do
    table.remove(lines)
  end
  return lines
end

-- Project files, for Java frames (package path + file name) and bare C file names
local function project_files()
  local cmd = vim.fn.executable 'rg' == 1 and { 'rg', '--files' } or { 'git', 'ls-files' }
  local out = vim.system(cmd, { text = true, cwd = vim.fn.getcwd() }):wait().stdout or ''
  return vim.split(out, '\n', { trimempty = true })
end

local function by_suffix(files, suffix)
  for _, f in ipairs(files) do
    if f == suffix or vim.endswith(f, '/' .. suffix) then
      return vim.fn.fnamemodify(f, ':p')
    end
  end
end

local function in_project(path)
  path = vim.fn.fnamemodify(path, ':p')
  local cwd = vim.fn.getcwd() .. '/'
  if vim.startswith(path, cwd) and not path:find '/site%-packages/' and not path:find '/node_modules/' and vim.uv.fs_stat(path) then
    return path
  end
end

-- A frame of a line: { file, lnum, col } (file = nil for library frames), or nil
local function frame(line, files)
  -- Java / Kotlin: at a.b.C$D.m(C.java:12)
  local class, file, lnum = line:match '^%s*at ([%w_$.]+)%.[%w_$<>]+%(([%w_$]+%.%w+):(%d+)%)'
  if class then
    local package = class:match '^(.*)%.[^.]+$'
    local path = package and package:gsub('%.', '/') .. '/' .. file or file
    return { file = by_suffix(files, path) or by_suffix(files, file), lnum = tonumber(lnum) }
  end
  if line:match '^%s*at [%w_$.]+%.[%w_$<>]+%(' then
    return { lnum = 0 } -- Native Method / Unknown Source
  end
  local col
  -- Python: File "x.py", line 12, in f
  file, lnum = line:match '^%s*File "([^"]+)", line (%d+)'
  if file then
    return { file = in_project(file), lnum = tonumber(lnum) }
  end
  -- Node: at f (/x/y.js:1:2), at /x/y.js:1:2, at file:///x/y.mjs:1:2
  file, lnum, col = line:match '^%s*at .-%(([^()]+):(%d+):(%d+)%)%s*$'
  if not file then
    file, lnum, col = line:match '^%s*at ([^%s()]+):(%d+):(%d+)%s*$'
  end
  if file then
    file = file:gsub('^file://', '')
    return { file = not file:match '^node:' and in_project(file) or nil, lnum = tonumber(lnum), col = tonumber(col) }
  end
  -- gdb / sanitizers: #3 0x… in f /x/y.c:12:5, or … at y.c:12
  file, lnum = line:match '^%s*#%d+.-%s([^%s:]+%.%w+):(%d+)'
  if file then
    return { file = in_project(file) or (not file:match '^/' and by_suffix(files, file)) or nil, lnum = tonumber(lnum) }
  end
end

local function analyze(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local files = project_files()
  local frames, qf = {}, {}
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, line in ipairs(lines) do
    local f = frame(line, files)
    if f then
      frames[i] = f.file and f or nil
      local group = f.file and 'Underlined' or 'Comment'
      vim.hl.range(buf, ns, group, { i - 1, 0 }, { i - 1, -1 })
      if f.file then
        table.insert(qf, { filename = f.file, lnum = f.lnum, col = f.col or 1, text = vim.trim(line) })
      end
    elseif line:match '^%S' and (line:match 'Exception' or line:match 'Error' or line:match '^Caused by') then
      vim.hl.range(buf, ns, 'DiagnosticError', { i - 1, 0 }, { i - 1, -1 })
    end
  end
  frames_of[buf] = frames
  if #qf > 0 then
    vim.fn.setqflist({}, ' ', { title = 'Stack trace', items = qf })
  end
  vim.notify(('Stack trace: %d frames in this project%s'):format(#qf, #qf > 0 and ' (Alt+3: Find window)' or ''))
  return qf
end

local function jump(buf)
  local f = (frames_of[buf] or {})[vim.api.nvim_win_get_cursor(0)[1]]
  if not f then
    return vim.notify('Not a frame from this project', vim.log.levels.INFO)
  end
  vim.cmd 'wincmd k'
  vim.cmd('edit ' .. vim.fn.fnameescape(f.file))
  vim.api.nvim_win_set_cursor(0, { math.max(f.lnum, 1), math.max((f.col or 1) - 1, 0) })
  vim.cmd 'normal! zz'
end

function M.open(text)
  text = text or vim.fn.getreg '+'
  if vim.trim(text) == '' then
    text = vim.fn.getreg '"'
  end
  local lines = normalize(text)
  vim.cmd 'botright new'
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'pcstacktrace'
  pcall(vim.api.nvim_buf_set_name, buf, 'Stack trace')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_height(0, math.max(8, math.min(#lines + 1, math.floor(vim.o.lines / 3))))
  vim.wo.wrap = false
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, desc = desc })
  end
  map('<CR>', function()
    jump(buf)
  end, 'Go to frame')
  map('R', function()
    local normalized = normalize(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, normalized)
    analyze(buf)
  end, 'Analyze again')
  map('q', '<cmd>close<CR>', 'Close')
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      frames_of[buf] = nil
    end,
  })
  local qf = analyze(buf)
  -- start on the first frame from the project, like IDEA's first link
  local frames = frames_of[buf]
  for i = 1, #lines do
    if frames[i] then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      break
    end
  end
  return qf
end

vim.keymap.set('n', '<leader>U', function()
  M.open()
end, { desc = '[U]nscramble stack trace (from clipboard)' })
vim.api.nvim_create_user_command('Unscramble', function()
  M.open()
end, { desc = 'Analyze the stack trace from the clipboard' })

return M
