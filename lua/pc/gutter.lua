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

-- A click from a file you are typing in into another file ends typing there (Insert mode went
-- along: the log has a click from in.txt into the code, then keys typed into the code and u), and
-- a click back into the first file goes on typing where you click, as it did.
local file_window = require('pc.wins').is_editor
local resuming -- window a click is going back to typing in

vim.keymap.set('i', '<LeftMouse>', function()
  local here, there = vim.api.nvim_get_current_win(), vim.fn.getmousepos().winid
  if there == here or not file_window(here) or not file_window(there) then
    return '<LeftMouse>'
  end
  vim.w[here].pc_typing = true
  return '<Esc><LeftMouse>'
end, { expr = true, desc = 'Click: into another file ends typing' })

-- entered any other way (Ctrl+H, a picker), the window is not typed in any more
vim.api.nvim_create_autocmd('WinEnter', {
  group = vim.api.nvim_create_augroup('pc-click-typing', { clear = true }),
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if win ~= resuming then
      vim.w[win].pc_typing = nil
    end
    resuming = nil
  end,
})

vim.keymap.set('n', '<LeftMouse>', function()
  local mouse = vim.fn.getmousepos()
  if mouse.winid ~= 0 and mouse.winid ~= vim.api.nvim_get_current_win() and vim.w[mouse.winid].pc_typing then
    vim.w[mouse.winid].pc_typing = nil
    resuming = mouse.winid
    return '<LeftMouse>i'
  end
  -- a window without a shown sign column (a terminal, the tree, signcolumn=auto without signs: the
  -- agent terminal opened from a Java file kept auto, and a drag from its first columns copied
  -- nothing): its first columns are text
  if mouse.winid == 0 or mouse.line == 0 then
    return '<LeftMouse>'
  end
  local gutter = math.min(4, vim.fn.getwininfo(mouse.winid)[1].textoff)
  if mouse.wincol > gutter or vim.wo[mouse.winid].signcolumn == 'no' then
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
