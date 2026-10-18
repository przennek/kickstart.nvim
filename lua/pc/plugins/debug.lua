-- debug.lua
--
-- Shows how to use the DAP plugin to debug your code.
--
-- Primarily focused on configuring the debugger for Go, but can
-- be extended to other languages as well. That's why it's called
-- kickstart.nvim and not kitchen-sink.nvim ;)

return {
  -- NOTE: Yes, you can install new plugins here!
  'mfussenegger/nvim-dap',
  -- NOTE: And you can specify dependencies as well
  dependencies = {
    -- Creates a beautiful debugger UI
    'rcarriga/nvim-dap-ui',

    -- Required dependency for nvim-dap-ui
    'nvim-neotest/nvim-nio',

    -- Installs the debug adapters for you
    'williamboman/mason.nvim',
    'jay-babu/mason-nvim-dap.nvim',

    -- Add your own debuggers here
    'leoluz/nvim-dap-go',

    -- Modern UI enhancements
    'rcarriga/nvim-dap-ui',
    'theHamsta/nvim-dap-virtual-text',
    'nvim-telescope/telescope-dap.nvim',
    'rcarriga/cmp-dap',
  },
  keys = function(_, keys)
    local dap = require 'dap'
    local dapui = require 'dapui'
    local telescope = require 'telescope'
    return {
      -- Basic debugging keymaps, feel free to change to your liking!
      { '<F5>', dap.continue, desc = 'Debug: Start/Continue' },
      { '<F1>', dap.step_into, desc = 'Debug: Step Into' },
      { '<F2>', dap.step_over, desc = 'Debug: Step Over' },
      { '<F3>', dap.step_out, desc = 'Debug: Step Out' },
      { '<leader>b', dap.toggle_breakpoint, desc = 'Debug: Toggle Breakpoint' },
      {
        '<leader>B',
        function()
          dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ')
        end,
        desc = 'Debug: Set Breakpoint',
      },
      -- Toggle to see last session result. Without this, you can't see session output in case of unhandled exception.
      { '<F7>', dapui.toggle, desc = 'Debug: Toggle UI' },
      
      -- Enhanced UI keymaps
      { '<leader>du', dapui.toggle, desc = 'Debug: Toggle UI' },
      { '<leader>db', dap.toggle_breakpoint, desc = 'Debug: Toggle Breakpoint' },
      { '<leader>dB', function()
        dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ')
      end, desc = 'Debug: Set Conditional Breakpoint' },
      { '<leader>dc', dap.clear_breakpoints, desc = 'Debug: Clear All Breakpoints' },
      { '<leader>dC', dap.run_to_cursor, desc = 'Debug: Run to Cursor' },
      { '<leader>di', dap.step_into, desc = 'Debug: Step Into' },
      { '<leader>do', dap.step_over, desc = 'Debug: Step Over' },
      { '<leader>dO', dap.step_out, desc = 'Debug: Step Out' },
      { '<leader>dr', dap.restart, desc = 'Debug: Restart' },
      { '<leader>dl', dap.run_last, desc = 'Debug: Run Last' },
      { '<leader>dt', dap.terminate, desc = 'Debug: Terminate' },
      
      -- Telescope integration
      { '<leader>df', telescope.extensions.dap.frames, desc = 'Debug: Frames' },
      { '<leader>dc', telescope.extensions.dap.commands, desc = 'Debug: Commands' },
      { '<leader>db', telescope.extensions.dap.list_breakpoints, desc = 'Debug: Breakpoints' },
      { '<leader>dv', telescope.extensions.dap.variables, desc = 'Debug: Variables' },
      
      unpack(keys),
    }
  end,
  config = function()
    local dap = require 'dap'
    local dapui = require 'dapui'

    require('mason-nvim-dap').setup {
      -- Makes a best effort to setup the various debuggers with
      -- reasonable debug configurations
      automatic_installation = true,

      -- You can provide additional configuration to the handlers,
      -- see mason-nvim-dap README for more information
      handlers = {},

      -- You'll need to check that you have the required things installed
      -- online, please don't ask me how to install them :)
      ensure_installed = {
        -- Update this to ensure that you have the debuggers for the langs you want
        'delve',           -- Go debugger
        'debugpy',         -- Python debugger
        'codelldb',        -- Rust/C++ debugger
      },
    }

    -- Enhanced Dap UI setup with modern features
    dapui.setup {
      icons = { 
        expanded = '▾', 
        collapsed = '▸', 
        current_frame = '▶',
        circular = '↻',
      },
      mappings = {
        -- Use a table to apply multiple mappings
        expand = { '<CR>', '<2-LeftMouse>' },
        open = 'o',
        remove = 'd',
        edit = 'e',
        repl = 'r',
        toggle = 't',
      },
      expand_lines = true,
      layouts = {
        {
          elements = {
            { id = 'scopes', size = 0.25 },
            { id = 'breakpoints', size = 0.25 },
            { id = 'stacks', size = 0.25 },
            { id = 'watches', size = 0.25 },
          },
          position = 'left',
          size = 40,
        },
        {
          elements = {
            { id = 'repl', size = 0.5 },
            { id = 'console', size = 0.5 },
          },
          position = 'bottom',
          size = 10,
        },
      },
      controls = {
        enabled = true,
        element = 'repl',
        icons = {
          pause = '⏸',
          play = '▶',
          step_into = '⏎',
          step_over = '⏭',
          step_out = '⏮',
          step_back = 'b',
          run_last = '▶▶',
          terminate = '⏹',
          disconnect = '⏏',
        },
      },
      floating = {
        max_height = nil, -- These can be integers or a float between 0 and 1.
        max_width = nil, -- Floats will be treated as percentage of your screen.
        border = 'single', -- Border style. Can be 'single', 'double' or 'rounded'
        mappings = {
          close = { 'q', '<Esc>' },
        },
      },
      windows = { indent = 1 },
      render = {
        max_type_length = nil, -- Can be integer or nil.
        max_value_lines = nil, -- Can be integer or nil.
      },
    }

    dap.listeners.after.event_initialized['dapui_config'] = dapui.open
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close

    -- Virtual text for debugging (shows variable values inline)
    require('nvim-dap-virtual-text').setup {
      enabled = true,
      enabled_commands = true,
      highlight_changed_variables = true,
      highlight_new_as_changed = false,
      show_stop_reason = true,
      commented = false,
      only_first_definition = true,
      all_references = false,
      clear_on_continue = false,
      --- A callback that determines how a variable gets its text
      --- @param variable Variable see https://microsoft.github.io/debug-adapter-protocol/specification#Types_Variable
      --- @param buf number
      --- @param stackframe dap.StackFrame https://microsoft.github.io/debug-adapter-protocol/specification#Types_StackFrame
      --- @param node userdata tree-sitter node identified as variable definition of reference (see `:h tsnode`)
      --- @param options nvim_dap_virtual_text_options
      --- @return string|nil A text how the virtual text should be displayed or nil to use the default behavior
      virt_text_pos = 'eol', -- position of virtual text, see `:h nvim_buf_set_extmark()`
      all_frames = false, -- show virtual text for all stack frames not only current. Set to true for GDB or LLDB
      virt_lines = false, -- show virtual lines instead of virtual text (will flicker when scrolling)
      virt_text_win_col = nil, -- position the virtual text at a fixed window column (starting from the first text column) ,
    }

    -- Telescope integration for debugging
    require('telescope').load_extension('dap')

    -- Install golang specific config
    require('dap-go').setup {
      delve = {
        -- On Windows delve must be run attached or it crashes.
        -- See https://github.com/leoluz/nvim-dap-go/blob/main/README.md#configuring
        detached = vim.fn.has 'win32' == 0,
      },
    }

    -- Python debugging configuration with automatic debugpy installation
    local function get_debugpy_path()
      local mason_path = vim.fn.stdpath('data') .. '/mason/packages/debugpy/venv/bin/python'
      if vim.fn.executable(mason_path) == 1 then
        return mason_path
      end
      
      -- Try alternative Mason path
      local alt_path = vim.fn.stdpath('data') .. '/mason/packages/debugpy/bin/python'
      if vim.fn.executable(alt_path) == 1 then
        return alt_path
      end
      
      -- Fallback to system python with debugpy
      if vim.fn.executable('python3') == 1 then
        return 'python3'
      elseif vim.fn.executable('python') == 1 then
        return 'python'
      else
        return 'python3' -- Default fallback
      end
    end

    dap.adapters.python = {
      type = 'executable',
      command = get_debugpy_path(),
      args = { '-m', 'debugpy.adapter' },
    }

    -- Auto-install debugpy if not available
    local function ensure_debugpy_installed()
      local mason_path = vim.fn.stdpath('data') .. '/mason/packages/debugpy/venv/bin/python'
      local alt_path = vim.fn.stdpath('data') .. '/mason/packages/debugpy/bin/python'
      
      if vim.fn.executable(mason_path) == 0 and vim.fn.executable(alt_path) == 0 then
        vim.notify('🐍 debugpy not found. Installing via Mason...', vim.log.levels.INFO)
        vim.cmd('MasonInstall debugpy')
        vim.notify('Please restart Neovim after installation completes.', vim.log.levels.WARN)
        return false
      end
      return true
    end

    dap.configurations.python = {
      {
        type = 'python',
        request = 'launch',
        name = 'Launch file',
        program = '${file}',
        python = function()
          ensure_debugpy_installed()
          return get_debugpy_path()
        end,
        console = 'integratedTerminal',
        justMyCode = false,
      },
      {
        type = 'python',
        request = 'attach',
        name = 'Attach to process',
        processId = function()
          return vim.fn.input('Process ID: ')
        end,
        python = function()
          return get_debugpy_path()
        end,
      },
      {
        type = 'python',
        request = 'launch',
        name = 'Django',
        program = '${workspaceFolder}/manage.py',
        args = { 'runserver' },
        django = true,
        console = 'integratedTerminal',
        justMyCode = false,
        python = function()
          return get_debugpy_path()
        end,
      },
    }

    -- Rust debugging configuration
    dap.adapters.codelldb = {
      type = 'server',
      port = '${port}',
      executable = {
        command = 'codelldb',
        args = { '--port', '${port}' },
      },
    }

    dap.configurations.rust = {
      {
        type = 'codelldb',
        request = 'launch',
        name = 'Launch file',
        program = function()
          return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        args = {},
        runInTerminal = false,
      },
      {
        type = 'codelldb',
        request = 'launch',
        name = 'Launch with args',
        program = function()
          return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        args = function()
          local args_string = vim.fn.input('Program arguments: ')
          return vim.split(args_string, ' ', true)
        end,
        runInTerminal = false,
      },
    }

    -- Enhanced breakpoint visualization with better colors
    vim.fn.sign_define('DapBreakpoint', { text = '🔴', texthl = 'DapBreakpoint', linehl = '', numhl = '' })
    vim.fn.sign_define('DapBreakpointCondition', { text = '🟡', texthl = 'DapBreakpointCondition', linehl = '', numhl = '' })
    vim.fn.sign_define('DapLogPoint', { text = '🟢', texthl = 'DapLogPoint', linehl = '', numhl = '' })
    vim.fn.sign_define('DapStopped', { text = '▶️', texthl = 'DapStopped', linehl = '', numhl = '' })
    vim.fn.sign_define('DapBreakpointRejected', { text = '❌', texthl = 'DapBreakpointRejected', linehl = '', numhl = '' })

    -- Custom highlight groups for better visual feedback
    vim.api.nvim_create_autocmd('ColorScheme', {
      pattern = '*',
      callback = function()
        vim.api.nvim_set_hl(0, 'DapBreakpoint', { fg = '#ff6b6b', bg = 'NONE' })
        vim.api.nvim_set_hl(0, 'DapBreakpointCondition', { fg = '#feca57', bg = 'NONE' })
        vim.api.nvim_set_hl(0, 'DapLogPoint', { fg = '#48dbfb', bg = 'NONE' })
        vim.api.nvim_set_hl(0, 'DapStopped', { fg = '#ff9ff3', bg = 'NONE' })
        vim.api.nvim_set_hl(0, 'DapBreakpointRejected', { fg = '#ff3838', bg = 'NONE' })
      end,
    })

    -- Set initial colors
    vim.api.nvim_set_hl(0, 'DapBreakpoint', { fg = '#ff6b6b', bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'DapBreakpointCondition', { fg = '#feca57', bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'DapLogPoint', { fg = '#48dbfb', bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'DapStopped', { fg = '#ff9ff3', bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'DapBreakpointRejected', { fg = '#ff3838', bg = 'NONE' })
  end,
}
