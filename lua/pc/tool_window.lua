-- IDEA's tool window keys (Alt+3 Find, Alt+6 Problems, Alt+0 Commit…): a hidden window opens, a
-- visible one you are not in gets the focus, the key pressed inside it hides it.

local M = {}

--- Wraps a toggle function. `is_tool(win)` tells the tool window's windows apart.
function M.activate(is_tool, toggle, on_focus)
  return function()
    -- from a popup (an input box, a hover): it closes and the tool window opens, as in IDEA;
    -- a dialog (pc.form) is modal and keeps the key
    if vim.api.nvim_win_get_config(0).relative ~= '' then
      if vim.bo.filetype == 'pcform' then
        return
      end
      local back = vim.fn.win_getid(vim.fn.winnr '#')
      if back == 0 or vim.api.nvim_win_get_config(back).relative ~= '' then
        back = vim.tbl_filter(function(w)
          return vim.api.nvim_win_get_config(w).relative == ''
        end, vim.api.nvim_tabpage_list_wins(0))[1]
      end
      vim.cmd 'stopinsert'
      vim.api.nvim_set_current_win(back)
    end
    local current = vim.api.nvim_get_current_win()
    local first
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).relative == '' and is_tool(win) then
        if win == current then
          return toggle()
        end
        first = first or win
      end
    end
    if first then
      vim.api.nvim_set_current_win(first)
      if on_focus then
        on_focus(first)
      end
      return
    end
    toggle()
  end
end

--- Matcher: windows showing one of these filetypes
function M.filetypes(...)
  local set = {}
  for _, ft in ipairs { ... } do
    set[ft] = true
  end
  return function(win)
    local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    return set[ft] or ft:match '^dapui_' and set['dapui_*'] or false
  end
end

--- Matcher: Trouble windows of one mode (quickfix = Find, diagnostics = Problems)
function M.trouble(mode)
  return function(win)
    local t = vim.w[win].trouble
    return type(t) == 'table' and t.mode == mode
  end
end

return M
