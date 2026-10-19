-- Useful plugin to show you pending keybinds.
return {
  'folke/which-key.nvim',
  event = 'VimEnter', -- Sets the loading event to 'VimEnter'
  config = function() -- This is the function that runs, AFTER loading
    require('which-key').setup()

    -- Document existing key chains
    -- (single-key leader actions from .ideavimrc: c class, n file, f usages, d branches,
    --  h call hierarchy, k structure, q switcher, g generate)
    require('which-key').add {
      { '<leader>b', group = '[B]uffer' },
      { '<leader>e', group = '[E]xtract (refactor)', mode = { 'n', 'x' } },
      { '<leader>p', group = 'Bookmarks / Har[p]oon' },
      { '<leader>Q', group = '[Q]uery console (database)' },
      { '<leader>M', group = '[M]aven' },
      { '<leader>r', group = '[R]ename' },
      { '<leader>s', group = '[S]earch' },
      { '<leader>w', group = '[W]orkspace' },
      { '<leader>t', group = '[T]oggle' },
      { '<leader>v', group = '[V]CS (git)', mode = { 'n', 'v' } },
      { '<leader>x', group = 'Run / Debug (e[x]ecute)', mode = { 'n', 'v' } },
    }
  end,
}
