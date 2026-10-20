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
      {
        '<M-3>',
        function()
          local tw = require 'pc.tool_window'
          tw.activate(tw.trouble 'quickfix', find_toggle)()
        end,
        desc = 'Find window',
      },
      { '<leader>s[', find_history 'colder', desc = 'Previous search results' },
      { '<leader>s]', find_history 'cnewer', desc = 'Next search results' },
      {
        '<M-6>',
        function()
          local tw = require 'pc.tool_window'
          tw.activate(tw.trouble 'diagnostics', function()
            require('trouble').toggle 'diagnostics'
          end)()
        end,
        desc = 'Problems window',
      },
      -- ]q / [q (Neovim defaults: :cnext / :cprev) walk the results without opening the window
    },
    opts = {
      focus = true, -- jump into the window, like IDEA's tool windows
      -- the Find / Problems window opens also when empty, as in IDEA
      open_no_results = true,
      warn_no_results = false,
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
      {
        '<M-7>',
        function()
          local tw = require 'pc.tool_window'
          tw.activate(tw.filetypes 'aerial', function()
            vim.cmd 'AerialToggle! right'
          end)()
        end,
        desc = 'Structure',
      },
      { '<leader>k', file_structure, desc = 'File structure' },
      -- File Structure popup is Cmd+F12 in the macOS keymap (F60 inside tmux)
      { '<M-F12>', file_structure, desc = 'File structure' },
      { '<F60>', file_structure, desc = 'File structure' },
    },
    opts = {
      backends = { 'lsp', 'treesitter', 'markdown', 'man' },
      layout = { min_width = 30 },
      show_guides = true,
      -- Ctrl+J / Ctrl+K move between splits (and tmux panes) here too, as everywhere else
      keymaps = { ['<C-j>'] = false, ['<C-k>'] = false },
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
            -- always with Settings → Editor → Breadcrumbs, else on demand
            local wanted = vim.w[win].pc_navbar == true or (vim.g.pc_breadcrumbs and vim.w[win].pc_navbar ~= false)
            return wanted and default_enable(buf, win, info)
          end,
        },
      }
    end,
  },
  -- Terminal tool window: Alt+T (Cmd+T in your macOS keymap), see pc.tool_window
  {
    'akinsho/toggleterm.nvim',
    version = '*',
    keys = {
      {
        '<M-t>',
        function()
          local tw = require 'pc.tool_window'
          tw.activate(tw.filetypes 'toggleterm', function()
            vim.cmd 'ToggleTerm'
          end, function()
            vim.cmd 'startinsert'
          end)()
        end,
        mode = { 'n', 't' },
        desc = 'Terminal',
      },
    },
    opts = {
      size = 15,
      direction = 'horizontal',
      -- always back in the shell prompt, also after leaving it with an IDE shortcut
      persist_mode = false,
      -- toggleterm's own start_in_insert switches the mode a moment later in whatever window
      -- has the focus by then: a terminal reopened by Hide All left the editor typing (and
      -- Alt+T there = Esc + t, waiting for a character). Typing mode only in the terminal itself:
      start_in_insert = false,
      on_open = function(term)
        vim.schedule(function()
          if vim.api.nvim_get_current_win() == term.window then
            vim.cmd 'startinsert'
          end
        end)
      end,
    },
    config = function(_, opts)
      require('toggleterm').setup(opts)
      vim.api.nvim_create_autocmd('BufEnter', {
        group = vim.api.nvim_create_augroup('pc-toggleterm-insert', { clear = true }),
        callback = function(event)
          if vim.bo[event.buf].filetype ~= 'toggleterm' then
            return
          end
          vim.schedule(function()
            if vim.api.nvim_get_current_buf() == event.buf then
              vim.cmd 'startinsert'
            end
          end)
        end,
      })
    end,
  },
}
