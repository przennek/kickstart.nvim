-- IDEA-like tool windows: Find, Structure, navigation bar, terminal.

-- The Find tool window (Alt+3) shows the quickfix list: search results are sent there
-- (Ctrl+T in a picker, Alt+F7 usages), so they stay put while you walk through them,
-- and older searches are kept (:colder / :cnewer, like the tabs in IDEA's Find window).
local function find_toggle()
  local trouble = require 'trouble'
  if trouble.is_open 'quickfix' then
    trouble.close 'quickfix'
  else
    trouble.open 'quickfix'
  end
end

local function find_history(cmd)
  return function()
    if pcall(vim.cmd, cmd) then
      require('trouble').open 'quickfix'
    end
  end
end

return {
  -- Find / Problems tool windows at the bottom
  {
    'folke/trouble.nvim',
    cmd = 'Trouble',
    keys = {
      { '<M-3>', find_toggle, desc = 'Find window (toggle)' },
      { '<leader>s[', find_history 'colder', desc = 'Previous search results' },
      { '<leader>s]', find_history 'cnewer', desc = 'Next search results' },
      {
        '<M-6>',
        function()
          require('trouble').toggle 'diagnostics'
        end,
        desc = 'Problems window (toggle)',
      },
      -- ]q / [q (Neovim defaults: :cnext / :cprev) walk the results without opening the window
    },
    opts = {
      focus = true, -- jump into the window, like IDEA's tool windows
      auto_preview = true,
      follow = false, -- don't move the selection along with the editor cursor
      win = { size = 12 },
    },
  },
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
