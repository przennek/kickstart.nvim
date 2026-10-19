-- Diff in the current split, like IDEA's diff editor tab: the window you are in is split into
-- <version from the branch> | <your working file>, all other splits stay as they are.
--   <leader>d    pick a branch: Enter = all files changed against it, Ctrl+F = this file only
--   Alt+D        this file against HEAD (Show Diff); pressing it again closes the diff
--   F7 / Shift+F7  next / previous change; past the last one the next changed file opens
--                  in the same place (handled in debug.lua together with Diffview)
--   Esc          close the diff and bring back what the window showed before

local M = {}

---@class pc.SplitDiff
---@field ref string
---@field root string
---@field files string[]  paths relative to root
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

--- Show file number `idx`, landing on its first change (or its last one with `from_end`)
local function show(s, idx, from_end)
  close_ref(s)
  s.idx = idx
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
  local files
  if file then
    files = { vim.fs.relpath(root, file) or file }
  else
    local out = git({ 'diff', '--name-only', ref }, root)
    if out.code ~= 0 then
      return vim.notify(out.stderr, vim.log.levels.ERROR)
    end
    files = vim.split(vim.trim(out.stdout), '\n', { trimempty = true })
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
  }
  sessions[vim.api.nvim_get_current_tabpage()] = s
  show(s, 1)
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
        end)
      elseif closed == s.refwin then
        s.refwin = nil
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
