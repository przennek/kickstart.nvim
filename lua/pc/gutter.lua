-- Clickable gutter icons, like IDEA's: modules register a handler for clicks in the sign
-- column (the first 4 screen columns of a window, signcolumn=yes:2); a click anywhere else
-- works as usual. Used by the run (▶) and hierarchy (↑ ↓) markers.

local M = {}

---@type fun(buf: integer, lnum: integer): boolean  handlers return true when they handled the click
local handlers = {}

function M.on_click(handler)
  table.insert(handlers, handler)
end

vim.keymap.set('n', '<LeftMouse>', function()
  local mouse = vim.fn.getmousepos()
  if mouse.winid == 0 or mouse.line == 0 or mouse.wincol > 4 then
    return '<LeftMouse>'
  end
  local buf = vim.api.nvim_win_get_buf(mouse.winid)
  vim.schedule(function()
    vim.api.nvim_set_current_win(mouse.winid)
    for _, handler in ipairs(handlers) do
      if handler(buf, mouse.line - 1) then
        return
      end
    end
    pcall(vim.api.nvim_win_set_cursor, mouse.winid, { mouse.line, 0 })
  end)
  return ''
end, { expr = true, desc = 'Click: gutter icon or move cursor' })

return M
