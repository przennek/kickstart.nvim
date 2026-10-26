-- Clickable gutter icons, like IDEA's: modules register a handler for clicks in the sign
-- column (the first 4 screen columns of a window, signcolumn=yes:2); a click anywhere else
-- works as usual. Used by the run (▶) and hierarchy (↑ ↓) markers. A handler gets the clicked
-- sign's text (both cells, e.g. '↑↓') and the clicked cell itself, so one sign can hold two icons.

local M = {}

---@type fun(buf: integer, lnum: integer, sign: string, cell: string): boolean  true = handled
local handlers = {}

function M.on_click(handler)
  table.insert(handlers, handler)
end

vim.keymap.set('n', '<LeftMouse>', function()
  local mouse = vim.fn.getmousepos()
  -- a window without the sign column (a terminal, the tree): its first columns are text
  if mouse.winid == 0 or mouse.line == 0 or mouse.wincol > 4 or vim.wo[mouse.winid].signcolumn == 'no' then
    return '<LeftMouse>'
  end
  local buf = vim.api.nvim_win_get_buf(mouse.winid)
  -- signs take two cells each: columns 1-2 and 3-4 of the window
  local first = mouse.screencol - (mouse.wincol - 1) % 2
  local sign = vim.fn.screenstring(mouse.screenrow, first) .. vim.fn.screenstring(mouse.screenrow, first + 1)
  local cell = vim.fn.screenstring(mouse.screenrow, mouse.screencol)
  vim.schedule(function()
    vim.api.nvim_set_current_win(mouse.winid)
    for _, handler in ipairs(handlers) do
      if handler(buf, mouse.line - 1, sign, cell) then
        return
      end
    end
    pcall(vim.api.nvim_win_set_cursor, mouse.winid, { mouse.line, 0 })
  end)
  return ''
end, { expr = true, desc = 'Click: gutter icon or move cursor' })

return M
