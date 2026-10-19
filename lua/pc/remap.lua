-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

-- netrw
-- vim.keymap.set('n', '<leader>pv', vim.cmd.Ex)

--- append to system clipboard
vim.opt.clipboard:append 'unnamedplus'

-- <Esc> clears the search highlight (and closes a diff); it is defined in split_diff.lua

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

-- Visual mode: Ctrl+J/K move and scroll the screen with the cursor, Ctrl+H/L move left/right
-- (in normal mode Ctrl+H/J/K/L switch splits / tmux panes, as in .ideavimrc)
map('x', '<C-j>', 'gj<C-e>')
map('x', '<C-k>', 'gk<C-y>')
map('x', '<C-h>', 'h')
map('x', '<C-l>', 'l')

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
-- (<leader>d is the Git branches popup now, as in the new .ideavimrc)
map('n', '<leader>bd', function()
  require('mini.bufremove').delete()
end, { desc = '[B]uffer: close file (keep window)' })

-- Jump to last / next change (Ctrl+Alt+P / N in .ideavimrc) = Neovim's change list
map('n', '<C-M-p>', 'g;', { desc = 'Jump to last change' })
map('n', '<C-M-n>', 'g,', { desc = 'Jump to next change' })

-- Cmd shortcuts from the macOS keymap, on Alt (the key next to space, like Cmd with Karabiner)
map('n', '<M-/>', 'gcc', { remap = true, desc = 'Comment line' })
map('x', '<M-/>', 'gc', { remap = true, desc = 'Comment selection' })
map('n', '<M-S-Down>', '<cmd>move .+1<CR>==', { desc = 'Move statement down' })
map('n', '<M-S-Up>', '<cmd>move .-2<CR>==', { desc = 'Move statement up' })
map('x', '<M-S-Down>', ":move '>+1<CR>gv=gv", { desc = 'Move selection down' })
map('x', '<M-S-Up>', ":move '<-2<CR>gv=gv", { desc = 'Move selection up' })
map('n', '<M-s>', '<cmd>wall<CR>', { desc = 'Save all' })
-- Replace word under cursor in file (gdefault already replaces every match in a line)
map('n', '<M-r>', [[:%s/\<<C-r><C-w>\>//<Left>]], { desc = 'Replace' })
map('n', '<M-e>', function()
  require('telescope.builtin').oldfiles { cwd_only = true }
end, { desc = 'Recent Files' })
map('n', '<M-E>', function()
  require('telescope.builtin').jumplist()
end, { desc = 'Recent locations' })
map({ 'n', 'i' }, '<M-V>', function()
  require('telescope.builtin').registers()
end, { desc = 'Paste from history' })

-- Scratch file (New Scratch File): an unnamed buffer with a filetype you pick
map('n', '<leader>N', function()
  vim.ui.select({ 'java', 'sql', 'json', 'yaml', 'python', 'markdown', 'sh', 'text' }, { prompt = 'Scratch file type' }, function(ft)
    if ft then
      vim.cmd 'enew'
      vim.bo.buftype = 'nofile'
      vim.bo.filetype = ft
    end
  end)
end, { desc = '[N]ew scratch file' })

-- Back / Forward (Ctrl+Alt+H/L in IDEA, but Ctrl+Alt+H/L switches GNOME workspaces here)
map('n', '<M-h>', '<C-o>', { desc = 'Back' })
map('n', '<M-l>', '<C-i>', { desc = 'Forward' })

-- Problems: F2 / Shift+F2 = next / previous, Alt+F1 = error description
-- (F14 / F49 are what Shift+F2 / Alt+F1 arrive as inside tmux); Alt+6 window is in ide-ui.lua
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
