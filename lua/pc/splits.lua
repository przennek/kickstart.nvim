-- Split sizes, like the Tab Shifter plugin and Maximize Editor in Split in your IDEA:
--   Ctrl+Shift+M          maximize the current split / restore the layout (in a Diffview: the
--                         diff over the whole width without the file list / the list back)
--                         (Alacritty sends it as Alt+Shift+M: terminals can't tell
--                         Ctrl+Shift+M from Enter)
--   Alt+Shift+[ / ]       move the split's vertical border left / right (Cmd+Shift+[ / ])
--   Alt+Shift+- / =       make the split lower / taller
--   Ctrl+W =              make all splits equal (built in)
-- Each accepts a count, e.g. 3 Alt+Shift+] moves the border three steps.

local STEP_COLS, STEP_ROWS = 5, 3

-- In a Diffview "maximize" is the diff, not one side of it: the file list goes away and the two
-- sides share the whole width; again: the list is back (the log: Ctrl+Shift+M maximized one
-- side, undone at once, then the separators were dragged by hand 23 and 224 columns)
local function diffview_wide()
  if not package.loaded['diffview'] then
    return false
  end
  local view = require('diffview.lib').get_current_view()
  if not (view and view.panel) then
    return false
  end
  local win = vim.api.nvim_get_current_win()
  local wide = not vim.t.pc_diff_wide
  vim.t.pc_diff_wide = wide or nil
  if wide and view.panel:is_open() then
    view.panel:close()
  elseif not wide and not view.panel:is_open() then
    view.panel:open()
  end
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  vim.cmd 'wincmd ='
  return true
end

local function maximize_toggle()
  if diffview_wide() then
    return
  end
  local restore = vim.t.pc_maximize_restore
  if restore then
    vim.t.pc_maximize_restore = nil
    vim.cmd(restore)
    return
  end
  if #vim.api.nvim_tabpage_list_wins(0) == 1 then
    return
  end
  vim.t.pc_maximize_restore = vim.fn.winrestcmd()
  vim.cmd 'wincmd |'
  vim.cmd 'wincmd _'
end

-- Move the vertical border: the window's right border, or its left one when the window is at
-- the right edge. Neovim resizes against the right neighbour first, so growing / shrinking
-- the window moves exactly that border.
local function stretch(dir)
  return function()
    local cols = STEP_COLS * vim.v.count1
    local has_right = vim.fn.winnr 'l' ~= vim.fn.winnr()
    local grow = (dir == 'right') == has_right
    vim.cmd(('vertical resize %s%d'):format(grow and '+' or '-', cols))
  end
end

local function height(delta)
  return function()
    vim.cmd(('resize %+d'):format(delta * STEP_ROWS * vim.v.count1))
  end
end

local map = vim.keymap.set
map('n', '<M-M>', maximize_toggle, { desc = 'Maximize split (toggle)' })
map('n', '<M-{>', stretch 'left', { desc = 'Move split border left' })
map('n', '<M-}>', stretch 'right', { desc = 'Move split border right' })
map('n', '<M-_>', height(-1), { desc = 'Split lower' })
map('n', '<M-+>', height(1), { desc = 'Split taller' })
