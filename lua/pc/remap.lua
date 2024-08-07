-- netrw
-- vim.keymap.set('n', '<leader>pv', vim.cmd.Ex)

--- append to system clipboard
vim.opt.clipboard:append 'unnamedplus'

-- tab as cww
vim.keymap.set('n', '<Tab>', '<C-w>w', { noremap = true, silent = true })
