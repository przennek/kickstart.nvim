-- Fuzzy Finder (files, lsp, etc)
return {
  'nvim-telescope/telescope.nvim',
  event = 'VimEnter',
  dependencies = {
    'nvim-lua/plenary.nvim',
    { -- If encountering errors, see telescope-fzf-native README for installation instructions
      'nvim-telescope/telescope-fzf-native.nvim',

      -- `build` is used to run some command when the plugin is installed/updated.
      -- This is only run then, not every time Neovim starts up.
      build = 'make',

      -- `cond` is a condition used to determine whether this plugin should be
      -- installed and loaded.
      cond = function()
        return vim.fn.executable 'make' == 1
      end,
    },
    { 'nvim-telescope/telescope-ui-select.nvim' },

    -- Useful for getting pretty icons, but requires a Nerd Font.
    { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
  },
  config = function()
    -- Telescope is a fuzzy finder that comes with a lot of different things that
    -- it can fuzzy find! It's more than just a "file finder", it can search
    -- many different aspects of Neovim, your workspace, LSP, and more!
    --
    -- The easiest way to use Telescope, is to start by doing something like:
    --  :Telescope help_tags
    --
    -- After running this command, a window will open up and you're able to
    -- type in the prompt window. You'll see a list of `help_tags` options and
    -- a corresponding preview of the help.
    --
    -- Two important keymaps to use while in Telescope are:
    --  - Insert mode: <c-/>
    --  - Normal mode: ?
    --
    -- This opens a window that shows you all of the keymaps for the current
    -- Telescope picker. This is really useful to discover what Telescope can
    -- do as well as how to actually do it!

    -- [[ Configure Telescope ]]
    -- See `:help telescope` and `:help telescope.setup()`
    -- Ctrl+T in any picker moves all its results to the Find window at the bottom (Alt+3)
    local function open_in_find_window(prompt_bufnr)
      require('telescope.actions').send_to_qflist(prompt_bufnr)
      require('trouble').open 'quickfix'
    end

    require('telescope').setup {
      defaults = {
        mappings = {
          i = { ['<C-t>'] = open_in_find_window },
          n = { ['<C-t>'] = open_in_find_window },
        },
      },
      -- You can put your default mappings / updates / etc. in here
      --  All the info you're looking for is in `:help telescope.setup()`
      --
      -- defaults = {
      --   mappings = {
      --     i = { ['<c-enter>'] = 'to_fuzzy_refine' },
      --   },
      -- },
      -- pickers = {}
      extensions = {
        ['ui-select'] = {
          require('telescope.themes').get_dropdown(),
        },
      },
    }

    -- Enable Telescope extensions if they are installed
    pcall(require('telescope').load_extension, 'fzf')
    pcall(require('telescope').load_extension, 'ui-select')

    -- See `:help telescope.builtin`
    local builtin = require 'telescope.builtin'
    vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
    vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
    vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
    vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
    vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
    vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
    vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
    vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })
    vim.keymap.set('n', '<leader>sp', builtin.git_files, { desc = '[S]earch [P]roject (git files)' })
    vim.keymap.set('n', '<leader>s:', '<cmd>Telescope command_history<CR>', { desc = '[S]earch command history' })

    -- [[ IDEA-like navigation ]]
    -- GotoClass: workspace symbols narrowed to types
    -- Works from any buffer (file tree, diff, Markdown…): asks a buffer whose language
    -- server can search the workspace, preferring the current one.
    local function workspace_symbol_buf()
      local method = 'workspace/symbol'
      local function capable(buf)
        for _, client in ipairs(vim.lsp.get_clients { bufnr = buf }) do
          if client:supports_method(method, buf) then
            return true
          end
        end
      end
      if capable(0) then
        return vim.api.nvim_get_current_buf()
      end
      for _, client in ipairs(vim.lsp.get_clients { method = method }) do
        local buf = next(client.attached_buffers)
        if buf then
          return buf
        end
      end
    end
    local function goto_class()
      local bufnr = workspace_symbol_buf()
      if not bufnr then
        vim.notify('No language server running yet: open a source file first', vim.log.levels.WARN)
        return
      end
      builtin.lsp_dynamic_workspace_symbols {
        bufnr = bufnr,
        prompt_title = 'Go to Class',
        symbols = { 'class', 'interface', 'enum', 'struct', 'module' },
      }
    end
    vim.keymap.set('n', '<leader>sc', goto_class, { desc = '[S]earch [C]lass' })
    vim.keymap.set('n', '<leader>sn', goto_class, { desc = '[S]earch class by [N]ame' })
    vim.keymap.set('n', '<M-n>', goto_class, { desc = 'Go to Class' })
    vim.keymap.set('n', '<leader>sS', function()
      builtin.lsp_dynamic_workspace_symbols { bufnr = workspace_symbol_buf() }
    end, { desc = '[S]earch [S]ymbol' })
    vim.keymap.set('n', '<M-N>', builtin.find_files, { desc = 'Go to File' })
    -- Switcher: open files, most recently used first
    vim.keymap.set('n', '<leader>q', function()
      builtin.buffers { sort_mru = true, ignore_current_buffer = true }
    end, { desc = 'Switcher' })
    -- Find Action
    vim.keymap.set('n', '<M-A>', builtin.commands, { desc = 'Find Action' })

    -- Slightly advanced example of overriding default behavior and theme
    vim.keymap.set('n', '<leader>/', function()
      -- You can pass additional configuration to Telescope to change the theme, layout, etc.
      builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
        winblend = 10,
        previewer = false,
      })
    end, { desc = '[/] Fuzzily search in current buffer' })

    -- It's also possible to pass additional configuration options.
    --  See `:help telescope.builtin.live_grep()` for information about particular keys
    vim.keymap.set('n', '<leader>s/', function()
      builtin.live_grep {
        grep_open_files = true,
        prompt_title = 'Live Grep in Open Files',
      }
    end, { desc = '[S]earch [/] in Open Files' })

    -- Shortcut for searching your Neovim configuration files
    vim.keymap.set('n', '<leader>sN', function()
      builtin.find_files { cwd = vim.fn.stdpath 'config' }
    end, { desc = '[S]earch [N]eovim files' })
  end,
}
