-- Compare Two Files / Compare With… like IDEA's (Ctrl+D on two files in the project tree):
--   in the file tree: = on a file marks it, = on a second one opens both side by side in a diff tab
--   <leader>v= / :CompareWith   the current file against a file picked from the project
-- q closes the diff tab.

local M = {}

local marked

function M.diff(left, right)
  vim.cmd('tabedit ' .. vim.fn.fnameescape(left))
  vim.cmd 'diffthis'
  vim.cmd('rightbelow vsplit ' .. vim.fn.fnameescape(right))
  vim.cmd 'diffthis'
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    vim.keymap.set('n', 'q', function()
      vim.cmd 'diffoff!'
      vim.cmd 'tabclose'
      for _, b in ipairs { vim.fn.bufnr(left), vim.fn.bufnr(right) } do
        pcall(vim.keymap.del, 'n', 'q', { buffer = b })
      end
    end, { buffer = buf, desc = 'Close comparison' })
  end
end

--- The tree's = : first file is remembered, the second opens the comparison
function M.mark(path)
  if vim.fn.isdirectory(path) == 1 then
    return vim.notify('Compare: pick files, not directories', vim.log.levels.INFO)
  end
  if not marked or marked == path then
    marked = path
    return vim.notify('Compare: ' .. vim.fn.fnamemodify(path, ':.') .. ' marked — = on another file compares them')
  end
  local first = marked
  marked = nil
  M.diff(first, path)
end

function M.compare_with()
  local current = vim.api.nvim_buf_get_name(0)
  if current == '' then
    return vim.notify('Compare With: open a file first', vim.log.levels.INFO)
  end
  require('telescope.builtin').find_files {
    prompt_title = 'Compare ' .. vim.fs.basename(current) .. ' with…',
    attach_mappings = function(prompt_bufnr)
      local actions = require 'telescope.actions'
      actions.select_default:replace(function()
        local entry = require('telescope.actions.state').get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          M.diff(current, vim.fn.fnamemodify(entry.path or entry.value, ':p'))
        end
      end)
      return true
    end,
  }
end

vim.keymap.set('n', '<leader>v=', M.compare_with, { desc = 'VCS/Compare: current file with…' })
vim.api.nvim_create_user_command('CompareWith', M.compare_with, { desc = 'Compare the current file with another file' })

return M
