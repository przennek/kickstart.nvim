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

local function file_structure()
  require('telescope').extensions.aerial.aerial()
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
      keys = { ['<F4>'] = 'jump' }, -- Jump to Source
      win = { size = 12 },
    },
  },
  -- Structure (Alt+7) and File Structure popup (<leader>k, Alt+F12)
  {
    'stevearc/aerial.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    cmd = { 'AerialToggle', 'AerialNavToggle' },
    keys = {
      { '<M-7>', '<cmd>AerialToggle! right<CR>', desc = 'Structure' },
      { '<leader>k', file_structure, desc = 'File structure' },
      -- File Structure popup is Cmd+F12 in the macOS keymap (F60 inside tmux)
      { '<M-F12>', file_structure, desc = 'File structure' },
      { '<F60>', file_structure, desc = 'File structure' },
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
  -- Navigation bar (<leader>nb, Alt+Home, Alt+\): breadcrumbs are off like in your IDEA
  -- (SHOW_BREADCRUMBS=false); the key shows them in the current window and lets you pick
  -- a segment, pressing it again hides them
  {
    'Bekaboo/dropbar.nvim',
    event = 'BufReadPost',
    keys = function()
      local function navbar()
        local win = vim.api.nvim_get_current_win()
        if vim.w[win].pc_navbar then
          vim.w[win].pc_navbar = false
          vim.wo[win].winbar = ''
          return
        end
        vim.w[win].pc_navbar = true
        require('dropbar.utils.bar').attach(vim.api.nvim_get_current_buf(), win)
        vim.defer_fn(function()
          pcall(require('dropbar.api').pick)
        end, 50)
      end
      return {
        { '<leader>nb', navbar, desc = '[N]avigation [b]ar' },
        { '<M-Home>', navbar, desc = 'Navigation bar' },
        { '<M-\\>', navbar, desc = 'Navigation bar' },
      }
    end,
    opts = function()
      local default_enable = require('dropbar.configs').opts.bar.enable
      return {
        bar = {
          enable = function(buf, win, info)
            return vim.w[win].pc_navbar == true and default_enable(buf, win, info)
          end,
        },
      }
    end,
  },
  -- Terminal tool window: Alt+T (Cmd+T in your macOS keymap)
  {
    'akinsho/toggleterm.nvim',
    version = '*',
    keys = {
      { '<M-t>', '<cmd>ToggleTerm<CR>', mode = { 'n', 't' }, desc = 'Terminal' },
    },
    opts = {
      size = 15,
      direction = 'horizontal',
    },
  },
}
