-- Editor windows: the windows that show files, as opposed to tool windows (the project tree, a
-- terminal, Find…) and popups. One definition for everything that needs "the editor".

local M = {}

--- Is `win` an editor window: part of the layout (not a popup) and showing a file buffer?
function M.is_editor(win)
  return win ~= nil
    and win ~= 0
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_config(win).relative == ''
    and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ''
end

--- The first editor window of the current tab that `accept(win)` takes (default: any), or nil
function M.editor(accept)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if M.is_editor(win) and (not accept or accept(win)) then
      return win
    end
  end
end

--- The editor window to act in from a tool window: the one you were in last, else the first
function M.last_editor()
  local prev = vim.fn.win_getid(vim.fn.winnr '#')
  return M.is_editor(prev) and prev or M.editor()
end

return M
