-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  {
    'christoomey/vim-tmux-navigator',
    cmd = {
      'TmuxNavigateLeft',
      'TmuxNavigateDown',
      'TmuxNavigateUp',
      'TmuxNavigateRight',
      'TmuxNavigatePrevious',
    },
    -- its Terminal-mode mappings are Vim's (they typed "TmuxNavigateUp" into the shell): ours
    init = function()
      vim.g.tmux_navigator_no_mappings = 1
    end,
    keys = {
      { '<c-h>', '<cmd>TmuxNavigateLeft<cr>' },
      { '<c-j>', '<cmd>TmuxNavigateDown<cr>' },
      { '<c-k>', '<cmd>TmuxNavigateUp<cr>' },
      { '<c-l>', '<cmd>TmuxNavigateRight<cr>' },
      { '<c-\\>', '<cmd>TmuxNavigatePrevious<cr>' },
      {
        '<c-h>',
        function()
          return require('pc.terminal_nav').keys('h', 'Left')
        end,
        mode = 't',
        expr = true,
        desc = 'Move to the split / tmux pane left',
      },
      {
        '<c-j>',
        function()
          return require('pc.terminal_nav').keys('j', 'Down')
        end,
        mode = 't',
        expr = true,
        desc = 'Move to the split / tmux pane down',
      },
      {
        '<c-k>',
        function()
          return require('pc.terminal_nav').keys('k', 'Up')
        end,
        mode = 't',
        expr = true,
        desc = 'Move to the split / tmux pane up',
      },
      {
        '<c-l>',
        function()
          return require('pc.terminal_nav').keys('l', 'Right')
        end,
        mode = 't',
        expr = true,
        desc = 'Move to the split / tmux pane right',
      },
    },
  },
}
