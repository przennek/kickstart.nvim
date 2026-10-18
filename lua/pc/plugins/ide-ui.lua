-- IDEA-like tool windows: Structure, navigation bar, terminal.
return {
  -- Structure (Alt+7) and File Structure popup (<leader>k)
  {
    'stevearc/aerial.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    cmd = { 'AerialToggle', 'AerialNavToggle' },
    keys = {
      { '<M-7>', '<cmd>AerialToggle! right<CR>', desc = 'Structure' },
      {
        '<leader>k',
        function()
          require('telescope').extensions.aerial.aerial()
        end,
        desc = 'File structure',
      },
    },
    opts = {
      backends = { 'lsp', 'treesitter', 'markdown', 'man' },
      layout = { min_width = 30 },
      show_guides = true,
    },
    config = function(_, opts)
      require('aerial').setup(opts)
      require('telescope').load_extension 'aerial'
    end,
  },
  -- Navigation bar / breadcrumbs on top of every window (<leader>n to pick a segment)
  {
    'Bekaboo/dropbar.nvim',
    event = 'BufReadPost',
    keys = {
      {
        '<leader>n',
        function()
          require('dropbar.api').pick()
        end,
        desc = '[N]avigation bar',
      },
    },
    opts = {},
  },
  -- Terminal tool window (Alt+F12; F60 inside tmux), Alt+T like Cmd+T in your Mac keymap
  {
    'akinsho/toggleterm.nvim',
    version = '*',
    keys = {
      { '<M-F12>', '<cmd>ToggleTerm<CR>', mode = { 'n', 't' }, desc = 'Terminal' },
      { '<F60>', '<cmd>ToggleTerm<CR>', mode = { 'n', 't' }, desc = 'Terminal' },
      { '<M-t>', '<cmd>ToggleTerm<CR>', mode = { 'n', 't' }, desc = 'Terminal' },
    },
    opts = {
      size = 15,
      direction = 'horizontal',
    },
  },
}
