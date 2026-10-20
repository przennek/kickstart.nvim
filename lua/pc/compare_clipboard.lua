-- Compare with Clipboard, like IDEA's: the selection (or the whole file) against the clipboard,
-- side by side in a new tab.
--   <leader>vy (normal: whole file, visual: selection) / :CompareClipboard
-- Without a selection the right side is the file itself, so you can take changes into it
-- (do / dp, or edit); q closes the tab.

local M = {}

local function scratch(lines, name, ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = ft
  pcall(vim.api.nvim_buf_set_name, buf, name)
  return buf
end

function M.compare(selection)
  local clip = vim.fn.getreg '+'
  if clip == '' then
    clip = vim.fn.getreg '"'
  end
  if clip == '' then
    return vim.notify('Clipboard is empty', vim.log.levels.WARN)
  end
  local file_buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[file_buf].filetype
  local clip_lines = vim.split(clip:gsub('\n$', ''), '\n', { plain = true })

  vim.cmd 'tabnew'
  local tab_first = vim.api.nvim_get_current_buf()
  local right
  if selection then
    right = scratch(selection, 'Selection', ft)
  else
    right = file_buf
  end
  vim.api.nvim_win_set_buf(0, right)
  vim.cmd 'diffthis'
  vim.cmd 'leftabove vsplit'
  local left = scratch(clip_lines, 'Clipboard', ft)
  vim.api.nvim_win_set_buf(0, left)
  vim.cmd 'diffthis'
  if vim.api.nvim_buf_is_valid(tab_first) and tab_first ~= right then
    pcall(vim.api.nvim_buf_delete, tab_first, { force = true })
  end
  for _, buf in ipairs { left, right } do
    vim.keymap.set('n', 'q', function()
      vim.cmd 'diffoff!'
      vim.cmd 'tabclose'
      pcall(vim.keymap.del, 'n', 'q', { buffer = file_buf })
    end, { buffer = buf, desc = 'Close comparison' })
  end
end

vim.keymap.set('n', '<leader>vy', function()
  M.compare()
end, { desc = 'Compare file with clipboard' })
vim.keymap.set('v', '<leader>vy', function()
  local lines = vim.fn.getregion(vim.fn.getpos 'v', vim.fn.getpos '.', { type = vim.fn.mode() })
  vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'nx', false)
  M.compare(lines)
end, { desc = 'Compare selection with clipboard' })
vim.api.nvim_create_user_command('CompareClipboard', function(opts)
  M.compare(opts.range > 0 and vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false) or nil)
end, { range = true, desc = 'Compare with clipboard' })

return M
