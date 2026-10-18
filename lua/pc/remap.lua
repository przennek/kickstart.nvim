-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

-- netrw
-- vim.keymap.set('n', '<leader>pv', vim.cmd.Ex)

--- append to system clipboard
vim.opt.clipboard:append 'unnamedplus'

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- [[ Ported from .ideavimrc ]]
local map = vim.keymap.set

-- Escape
map('i', 'jk', '<Esc>`^', { desc = 'Escape' })
map('i', '<C-q>', '<Esc>`^', { desc = 'Escape' })
map({ 'n', 'v', 'o' }, '<C-q>', '<Esc>', { desc = 'Escape' })
map('c', '<C-q>', '<C-c>', { desc = 'Escape' })

-- Insert mode arrows
map('i', '<C-h>', '<Left>')
map('i', '<C-j>', '<Down>')
map('i', '<C-k>', '<Up>')
map('i', '<C-l>', '<Right>')

-- Previous / next f/t match
map({ 'n', 'v', 'o' }, 'H', ',', { desc = 'Previous f/t match' })
map({ 'n', 'v', 'o' }, 'L', ';', { desc = 'Next f/t match' })

-- Editing
map('n', 'U', '<C-r>', { desc = 'Redo' })
map('n', 'K', 'ciw', { desc = 'Change word' })
map('n', 'J', 'ci"', { desc = 'Change in double quotes' })
map('n', '<leader>J', 'J', { desc = '[J]oin lines' })
map('v', '<', '<gv')
map('v', '>', '>gv')
map('n', '<leader>a', 'ggVG', { desc = 'Select [a]ll' })
map('n', '<leader>I', 'gg=G``', { desc = '[I]ndent whole file' })
map('n', '<leader>i', '==', { desc = '[i]ndent line' })
map('v', '<leader>i', '=', { desc = '[i]ndent selection' })

-- <CR> enters the command line, but only in regular file buffers
-- (quickfix, help etc. keep their own <CR>)
map('n', '<CR>', function()
  return vim.bo.buftype == '' and ':' or '<CR>'
end, { expr = true, desc = 'Command line' })

-- [[ IDE-like actions that don't need LSP ]]
map('n', '<leader>d', function()
  require('mini.bufremove').delete()
end, { desc = 'Close file (keep window)' })

-- Back / Forward (Ctrl+Alt+H/L in IDEA, but Ctrl+Alt+H/L switches GNOME workspaces here)
map('n', '<M-h>', '<C-o>', { desc = 'Back' })
map('n', '<M-l>', '<C-i>', { desc = 'Forward' })

-- Problems: F2 / Shift+F2 = next / previous, Alt+F1 = error description, Alt+6 = list
-- (F14 / F49 are what Shift+F2 / Alt+F1 arrive as inside tmux)
local function jump_diag(count)
  return function()
    vim.diagnostic.jump { count = count, float = true }
  end
end
map('n', '<F2>', jump_diag(1), { desc = 'Next problem' })
map('n', '<S-F2>', jump_diag(-1), { desc = 'Previous problem' })
map('n', '<F14>', jump_diag(-1), { desc = 'Previous problem' })
map('n', '<M-F1>', vim.diagnostic.open_float, { desc = 'Show error description' })
map('n', '<F49>', vim.diagnostic.open_float, { desc = 'Show error description' })
map('n', '<M-6>', function()
  require('telescope.builtin').diagnostics()
end, { desc = 'Problems' })
