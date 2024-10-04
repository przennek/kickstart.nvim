-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  cmd = 'Neotree',
  lazy = false,
  keys = {
    { '<A-1>', ':Neotree reveal<CR>', desc = 'NeoTree reveal' },
  },
  opts = {
    filesystem = {
      hijack_netrw_behavior = 'open_current',
      window = {
        mappings = {
          ['<A-1>'] = 'close_window',
          ['<space>'] = {
            'toggle_node',
            nowait = false, -- disable `nowait` if you have existing combos starting with this char that you want to use
          },
        },
      },
    },
  },
}
