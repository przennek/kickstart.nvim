-- Useful plugin to show you pending keybinds.
return {
  'folke/which-key.nvim',
  event = 'VimEnter', -- Sets the loading event to 'VimEnter'
  config = function() -- This is the function that runs, AFTER loading
    require('which-key').setup()

    -- Document existing key chains
    require('which-key').add {
      { '<leader>c', group = '[C]ode / refactor', mode = { 'n', 'x' } },
      { '<leader>p', group = 'Har[p]oon bookmarks' },
      { '<leader>r', group = '[R]ename' },
      { '<leader>s', group = '[S]earch' },
      { '<leader>w', group = '[W]orkspace' },
      { '<leader>t', group = '[T]oggle' },
      { '<leader>v', group = '[V]CS (git)', mode = { 'n', 'v' } },
      { '<leader>x', group = 'Run / Debug (e[x]ecute)', mode = { 'n', 'v' } },
    }
  end,
}
