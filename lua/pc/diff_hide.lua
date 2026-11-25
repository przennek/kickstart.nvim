-- Hide the diff for a while and come back to it with the same key (Alt+Shift+F12 = Hide All
-- Windows, Cmd+Shift+F12 on the Mac; Space vd): you review a diff, put it away, work on a class,
-- jump around, and one key brings the diff back as you left it (the user, 2026-11-25).
--   in a Diffview (working tree, branch, Git log)  its tab stays as it is (file list, file,
--                                                  sides, cursor); you go back to the editor
--                                                  window you came from (another one of the
--                                                  editor when that one is gone)
--   in a split diff (Alt+D, Space d)               branch, files, the file and line are kept,
--                                                  the window shows what it did before the diff
--   the key again (outside a diff)                 the diff back, the editor window you were in
--                                                  is remembered for the next hide
-- Both the editor and the diff keep their files, splits and cursors in between.

local M = {}

local diff = nil -- { kind = 'diffview', tab, win } or { kind = 'split', snap, win }
local editor = nil -- { tab, win }: where hiding the diff takes you
M.seq = 0 -- when the diff was hidden (pc.hide_windows: the later of the two comes back first)

local function diffview_tab(tab)
  if not package.loaded['diffview'] then
    return false
  end
  for _, view in ipairs(require('diffview.lib').views) do
    if view.tabpage == tab then
      return true
    end
  end
  return false
end

local function in_split_diff()
  local sd = package.loaded['pc.split_diff']
  return sd and sd.current() ~= nil
end

--- Is the current window in a diff this module can hide?
function M.in_diff()
  return diffview_tab(vim.api.nvim_get_current_tabpage()) or in_split_diff()
end

--- Is a hidden diff waiting to come back?
function M.hidden()
  if not diff then
    return false
  end
  if diff.kind == 'diffview' and not (vim.api.nvim_tabpage_is_valid(diff.tab) and diffview_tab(diff.tab)) then
    diff = nil
    return false
  end
  return true
end

local function editor_window_of(tab)
  local wins = require 'pc.wins'
  local found
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if not found and vim.api.nvim_win_get_config(win).relative == '' and not vim.wo[win].diff and wins.is_editor(win) then
      found = win
    end
  end
  return found
end

-- back where the editor was: the remembered window, else an editor window of a tab without a
-- diff (a new tab when there is none)
local function to_editor()
  if editor and vim.api.nvim_win_is_valid(editor.win) and not diffview_tab(vim.api.nvim_win_get_tabpage(editor.win)) then
    vim.api.nvim_set_current_tabpage(vim.api.nvim_win_get_tabpage(editor.win))
    vim.api.nvim_set_current_win(editor.win)
    return
  end
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if not diffview_tab(tab) then
      vim.api.nvim_set_current_tabpage(tab)
      local win = editor_window_of(tab)
      if win then
        vim.api.nvim_set_current_win(win)
      end
      return
    end
  end
  vim.cmd 'tabnew'
end

--- Puts the diff away; false when the current window is not in one
function M.hide()
  local tab = vim.api.nvim_get_current_tabpage()
  if diffview_tab(tab) then
    diff = { kind = 'diffview', tab = tab, win = vim.api.nvim_get_current_win() }
    to_editor()
  elseif in_split_diff() then
    local sd = require 'pc.split_diff'
    local s = sd.current()
    diff = { kind = 'split', snap = sd.snapshot(), win = s.win }
    -- the window shows the file it showed before the diff, the cursor stays there
    sd.close()
  else
    return false
  end
  M.seq = vim.uv.hrtime()
  vim.api.nvim_echo({ { 'Diff hidden: Alt+Shift+F12 / Space vd brings it back', 'Comment' } }, false, {})
  return true
end

--- The Diffview in `tab` counts as hidden (Jump to Source left it for the editor): the key
--- brings it back to `win`
function M.mark_hidden(tab, win)
  diff = { kind = 'diffview', tab = tab, win = win }
  M.seq = vim.uv.hrtime()
end

--- Brings the hidden diff back; false when there is none
function M.restore()
  if not M.hidden() then
    return false
  end
  local d = diff
  diff = nil
  local here = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(here).relative == '' then
    editor = { win = here }
  end
  if d.kind == 'diffview' then
    vim.api.nvim_set_current_tabpage(d.tab)
    if vim.api.nvim_win_is_valid(d.win) and vim.api.nvim_win_get_tabpage(d.win) == d.tab then
      vim.api.nvim_set_current_win(d.win)
    end
  else
    -- the split diff comes back in the window it was in (when it is still in this tab), else here
    if vim.api.nvim_win_is_valid(d.win) and vim.api.nvim_win_get_tabpage(d.win) == vim.api.nvim_get_current_tabpage() then
      vim.api.nvim_set_current_win(d.win)
    elseif vim.bo.buftype ~= '' then
      local win = editor_window_of(0)
      if win then
        vim.api.nvim_set_current_win(win)
      end
    end
    require('pc.split_diff').restore(d.snap)
  end
  return true
end

--- In a diff: hide it; outside with one hidden: bring it back. False when neither applies.
function M.toggle()
  if M.in_diff() then
    -- remember where the editor is before the first hide (the window the diff was opened from)
    return M.hide()
  end
  return M.restore()
end

-- the editor window you were in before entering a Diffview: where hiding it takes you
vim.api.nvim_create_autocmd('TabLeave', {
  group = vim.api.nvim_create_augroup('pc-diff-hide', { clear = true }),
  callback = function()
    local tab = vim.api.nvim_get_current_tabpage()
    local win = vim.api.nvim_get_current_win()
    if not diffview_tab(tab) and vim.api.nvim_win_get_config(win).relative == '' and vim.bo.buftype == '' then
      editor = { win = win }
    end
  end,
})

return M
