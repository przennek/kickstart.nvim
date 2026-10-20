-- Diff in the current split, like IDEA's diff editor tab: the window you are in is split into
-- <version from the branch> | <your working file>, all other splits stay as they are.
--   <leader>d    pick a branch: Enter = all files changed against it, listed on the left
--                (Enter on one shows it, q closes everything), Ctrl+F = this file only
--   Alt+D        this file against HEAD (Show Diff); pressing it again closes the diff
--   F7 / Shift+F7  next / previous change; past the last one the next changed file opens
--                  in the same place (handled in debug.lua together with Diffview)
--   Esc          close the diff and bring back what the window showed before

local M = {}

---@class pc.SplitDiff
---@field ref string
---@field root string
---@field files string[]  paths relative to root
---@field status? table<string, string>  M / A / D … of each file (the changes list)
---@field listwin? integer window with the list of changed files (left)
---@field listbuf? integer
---@field idx integer
---@field win integer      window with the working file (right)
---@field refwin? integer  window with the branch version (left)
---@field prev_buf integer buffer the window showed before the diff
---@field prev_cursor integer[]
---@field bufnr? integer   buffer of the file currently diffed
---@field showing? boolean while show() itself switches the file

---@type table<integer, pc.SplitDiff>  per tab page
local sessions = {}

local function git(args, cwd)
  return vim.system(vim.list_extend({ 'git' }, args), { text = true, cwd = cwd }):wait()
end

function M.current()
  return sessions[vim.api.nvim_get_current_tabpage()]
end

--- Is `win` (default: current) one of the two windows of this tab's diff?
function M.owns(win)
  local s = M.current()
  win = win or vim.api.nvim_get_current_win()
  return s ~= nil and (win == s.win or win == s.refwin)
end

local function close_ref(s)
  if s.refwin and vim.api.nvim_win_is_valid(s.refwin) then
    vim.api.nvim_win_close(s.refwin, true)
  end
  s.refwin = nil
  if vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_call(s.win, function()
      vim.cmd 'diffoff'
    end)
  end
end

local function close_list(s)
  if s.listwin and vim.api.nvim_win_is_valid(s.listwin) then
    vim.api.nvim_win_close(s.listwin, true)
  end
  s.listwin = nil
end

local list_ns = vim.api.nvim_create_namespace 'pc-split-diff-list'

-- The changes list: the file shown in the diff is marked and under the cursor
local function render_list(s)
  if not (s.listbuf and vim.api.nvim_buf_is_valid(s.listbuf)) then
    return
  end
  local lines, marks = {}, {}
  local hl = { A = 'Added', D = 'Removed', M = 'Changed', R = 'Changed' }
  for i, rel in ipairs(s.files) do
    local st = s.status[rel] or 'M'
    local name, dir = vim.fs.basename(rel), vim.fs.dirname(rel)
    local mark = i == s.idx and '▶ ' or '  '
    lines[i] = mark .. st .. ' ' .. name .. '  ' .. (dir ~= '.' and dir or '')
    local name_col = #mark + #st + 1
    table.insert(marks, { i - 1, #mark, #mark + #st, hl[st] or 'Changed' })
    table.insert(marks, { i - 1, name_col, name_col + #name, i == s.idx and 'Title' or nil })
    table.insert(marks, { i - 1, name_col + #name, #lines[i], 'Comment' })
  end
  vim.bo[s.listbuf].modifiable = true
  vim.api.nvim_buf_set_lines(s.listbuf, 0, -1, false, lines)
  vim.bo[s.listbuf].modifiable = false
  vim.api.nvim_buf_clear_namespace(s.listbuf, list_ns, 0, -1)
  for _, m in ipairs(marks) do
    if m[4] then
      vim.api.nvim_buf_set_extmark(s.listbuf, list_ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
    end
  end
  if s.listwin and vim.api.nvim_win_is_valid(s.listwin) then
    vim.api.nvim_win_set_cursor(s.listwin, { s.idx, 0 })
  end
end

--- Show file number `idx`, landing on its first change (or its last one with `from_end`)
local function show(s, idx, from_end)
  close_ref(s)
  s.idx = idx
  render_list(s)
  local rel = s.files[idx]
  vim.api.nvim_set_current_win(s.win)
  s.showing = true
  vim.cmd.edit(vim.fn.fnameescape(s.root .. '/' .. rel))
  s.showing = false
  s.bufnr = vim.api.nvim_get_current_buf()
  require('lazy').load { plugins = { 'vim-fugitive' } }
  -- Branch version on the left, working file on the right
  local ok = pcall(vim.cmd, 'leftabove Gvdiffsplit ' .. s.ref)
  if ok and vim.api.nvim_get_current_win() ~= s.win then
    s.refwin = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(s.win)
  local edge = from_end and vim.fn.line '$' or 1
  vim.api.nvim_win_set_cursor(0, { edge, 0 })
  if vim.wo.diff and vim.fn.diff_hlID(edge, 1) == 0 then
    pcall(vim.cmd.normal, { from_end and '[c' or ']c', bang = true })
  end
  vim.api.nvim_echo({ { ('Diff with %s: %d/%d %s'):format(s.ref, idx, #s.files, rel), 'ModeMsg' } }, false, {})
end

--- Open a diff in the current window. `file` (absolute path) limits it to one file.
function M.open(ref, file)
  M.close()
  local root = vim.fs.root(file or 0, '.git') or vim.fn.getcwd()
  local files, status
  if file then
    files = { vim.fs.relpath(root, file) or file }
  else
    local out = git({ 'diff', '--name-status', ref }, root)
    if out.code ~= 0 then
      return vim.notify(out.stderr, vim.log.levels.ERROR)
    end
    files, status = {}, {}
    for _, line in ipairs(vim.split(vim.trim(out.stdout), '\n', { trimempty = true })) do
      -- "M<Tab>path", renames "R100<Tab>old<Tab>new"
      local st, path = line:match '^(%S+)\t(.*)$'
      if st then
        path = path:match '\t(.*)$' or path
        table.insert(files, path)
        status[path] = st:sub(1, 1)
      end
    end
    if #files == 0 then
      return vim.notify('No differences with ' .. ref)
    end
    -- start at the file you are in when it changed
    local here = vim.fs.relpath(root, vim.api.nvim_buf_get_name(0))
    for i, f in ipairs(files) do
      if f == here then
        table.insert(files, 1, table.remove(files, i))
        break
      end
    end
  end
  local s = {
    ref = ref,
    root = root,
    files = files,
    idx = 1,
    win = vim.api.nvim_get_current_win(),
    prev_buf = vim.api.nvim_get_current_buf(),
    prev_cursor = vim.api.nvim_win_get_cursor(0),
    status = status or {},
  }
  sessions[vim.api.nvim_get_current_tabpage()] = s
  if not file then
    M.open_list(s)
  end
  show(s, 1)
end

--- The changes list on the left of the diff, like the Changes tree of IDEA's branch diff
function M.open_list(s)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'pcdifffiles'
  s.listbuf = buf
  vim.api.nvim_win_call(s.win, function()
    vim.cmd 'leftabove vsplit'
    s.listwin = vim.api.nvim_get_current_win()
  end)
  vim.api.nvim_win_set_buf(s.listwin, buf)
  vim.api.nvim_win_set_width(s.listwin, math.min(40, math.max(24, math.floor(vim.o.columns / 6))))
  for opt, value in pairs { number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0', winfixwidth = true, wrap = false, list = false, cursorline = true, diff = false, scrollbind = false, cursorbind = false } do
    vim.wo[s.listwin][opt] = value
  end
  vim.wo[s.listwin].winbar = ('%%#Title# %d files%%* vs %s'):format(#s.files, s.ref:gsub('%%', '%%%%'))
  local function pick()
    local idx = vim.fn.line '.'
    if s.files[idx] then
      show(s, idx)
    end
  end
  for _, lhs in ipairs { '<CR>', '<2-LeftMouse>', 'o' } do
    vim.keymap.set('n', lhs, pick, { buffer = buf, desc = 'Show this file in the diff' })
  end
  for _, lhs in ipairs { 'q', '<Esc>' } do
    vim.keymap.set('n', lhs, M.close, { buffer = buf, desc = 'Close the diff' })
  end
end

--- Next / previous file of the diff; returns false at the end of the list
function M.step(dir)
  local s = M.current()
  if not s then
    return false
  end
  local idx = s.idx + (dir == 'next' and 1 or -1)
  if idx < 1 or idx > #s.files then
    vim.api.nvim_echo({ { 'No more changed files', 'WarningMsg' } }, false, {})
    return false
  end
  show(s, idx, dir == 'prev')
  return true
end

function M.close()
  local tab = vim.api.nvim_get_current_tabpage()
  local s = sessions[tab]
  if not s then
    return false
  end
  sessions[tab] = nil
  close_ref(s)
  close_list(s)
  if vim.api.nvim_win_is_valid(s.win) and vim.api.nvim_buf_is_valid(s.prev_buf) then
    vim.api.nvim_win_set_buf(s.win, s.prev_buf)
    pcall(vim.api.nvim_win_set_cursor, s.win, s.prev_cursor)
    vim.api.nvim_set_current_win(s.win)
  end
  return true
end

-- Show Diff (Cmd+D): this file against HEAD; again closes it
function M.toggle_file_diff()
  if M.current() then
    return M.close()
  end
  local file = vim.api.nvim_buf_get_name(0)
  if file == '' then
    return
  end
  M.open('HEAD', file)
end

-- A diff window closed by hand (:q) ends the diff
vim.api.nvim_create_autocmd('WinClosed', {
  group = vim.api.nvim_create_augroup('pc-split-diff', { clear = true }),
  callback = function(event)
    local closed = tonumber(event.match)
    for tab, s in pairs(sessions) do
      if closed == s.win then
        sessions[tab] = nil
        vim.schedule(function()
          if s.refwin and vim.api.nvim_win_is_valid(s.refwin) then
            vim.api.nvim_win_close(s.refwin, true)
          end
          close_list(s)
        end)
      elseif closed == s.refwin then
        s.refwin = nil
      elseif closed == s.listwin then
        s.listwin = nil
      end
    end
  end,
})

-- Opening another file in the working-file window (Go to Class, gd, the tree… while the cursor
-- is in the diff) leaves the diff, like opening a file over a diff tab in IDEA: the branch
-- side closes and the diff session ends, so F7 never replaces that file later.
vim.api.nvim_create_autocmd('BufWinEnter', {
  group = vim.api.nvim_create_augroup('pc-split-diff-leave', { clear = true }),
  callback = function(event)
    local tab = vim.api.nvim_get_current_tabpage()
    local s = sessions[tab]
    if not s or s.showing or vim.api.nvim_get_current_win() ~= s.win or event.buf == s.bufnr then
      return
    end
    sessions[tab] = nil
    vim.schedule(function()
      close_ref(s)
      close_list(s)
    end)
  end,
})

-- A split made from a diff window (Ctrl+W v) is a plain editor window, not a third side of
-- the diff: drop the diff options it copied. (Diffview tabs manage their own windows.)
vim.api.nvim_create_autocmd('WinNew', {
  group = vim.api.nvim_create_augroup('pc-split-diff-winnew', { clear = true }),
  callback = function()
    if not vim.wo.diff then
      return
    end
    if package.loaded['diffview'] and require('diffview.lib').get_current_view() then
      return
    end
    vim.wo.diff = false
    vim.wo.scrollbind = false
    vim.wo.cursorbind = false
    vim.wo.foldenable = false
    vim.wo.foldcolumn = '0'
  end,
})

-- Esc in a diff window closes the diff (CloseDiffEditor); elsewhere it clears the search highlight
vim.keymap.set('n', '<Esc>', function()
  if M.owns() then
    M.close()
  else
    vim.cmd 'nohlsearch'
  end
end, { desc = 'Close diff / clear highlight' })

return M
