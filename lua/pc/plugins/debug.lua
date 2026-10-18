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
    'mfussenegger/nvim-dap-python',

    -- Modern UI enhancements
    'rcarriga/nvim-dap-ui',
    'theHamsta/nvim-dap-virtual-text',
    'nvim-telescope/telescope-dap.nvim',
    'rcarriga/cmp-dap',
  },
  -- Loaded shortly after startup so per-language test keymaps exist right away
  event = 'VeryLazy',
  keys = function(_, keys)
    -- Look modules up on keypress, so the keys don't force-load everything at startup
    local function dap(fn, ...)
      local args = { ... }
      return function()
        require('dap')[fn](unpack(args))
      end
    end
    local function dapui(fn, ...)
      local args = { ... }
      return function()
        require('dapui')[fn](unpack(args))
      end
    end
    -- Alt+5: hide whatever part of the debug UI is open, or open all of it
    local function toggle_ui()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
        if ft:match '^dapui_' or ft == 'dap-repl' then
          return require('dapui').close()
        end
      end
      require('dapui').open()
    end
    local function tdap(picker)
      return function()
        require('telescope').extensions.dap[picker]()
      end
    end
    local function conditional_breakpoint()
      require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
    end

    -- IntelliJ IDEA (Default for XWin) debugger keys. Inside tmux modified F-keys arrive
    -- as F13+ (Shift +12, Ctrl +24, Ctrl+Shift +36, Alt +48), so both forms are mapped.
    return {
      { '<F5>', dap 'continue', desc = 'Debug: Start/Continue' },
      { '<S-F9>', dap 'continue', desc = 'Debug: Start/Continue' },
      { '<F21>', dap 'continue', desc = 'Debug: Start/Continue' },
      { '<F9>', dap 'continue', desc = 'Debug: Resume' },
      { '<F8>', dap 'step_over', desc = 'Debug: Step Over' },
      { '<F7>', dap 'step_into', desc = 'Debug: Step Into' },
      { '<S-F8>', dap 'step_out', desc = 'Debug: Step Out' },
      { '<F20>', dap 'step_out', desc = 'Debug: Step Out' },
      { '<M-F9>', dap 'run_to_cursor', desc = 'Debug: Run to Cursor' },
      { '<F57>', dap 'run_to_cursor', desc = 'Debug: Run to Cursor' },
      { '<C-F8>', dap 'toggle_breakpoint', desc = 'Debug: Toggle Breakpoint' },
      { '<F32>', dap 'toggle_breakpoint', desc = 'Debug: Toggle Breakpoint' },
      { '<C-S-F8>', conditional_breakpoint, desc = 'Debug: Conditional Breakpoint' },
      { '<F44>', conditional_breakpoint, desc = 'Debug: Conditional Breakpoint' },
      { '<M-F8>', dapui 'eval', mode = { 'n', 'v' }, desc = 'Debug: Evaluate Expression' },
      { '<F56>', dapui 'eval', mode = { 'n', 'v' }, desc = 'Debug: Evaluate Expression' },
      { '<C-F2>', dap 'terminate', desc = 'Debug: Stop' },
      { '<F26>', dap 'terminate', desc = 'Debug: Stop' },
      { '<C-F5>', dap 'restart', desc = 'Debug: Rerun' },
      { '<F29>', dap 'restart', desc = 'Debug: Rerun' },
      -- Debug tool window (Alt+5)
      { '<M-5>', toggle_ui, desc = 'Debug: Toggle UI' },

      { '<leader>b', dap 'toggle_breakpoint', desc = 'Debug: Toggle Breakpoint' },
      { '<leader>B', conditional_breakpoint, desc = 'Debug: Conditional Breakpoint' },

      -- <leader>x: Run / Debug (<leader>d closes the file, like CloseContent in .ideavimrc)
      { '<leader>xu', toggle_ui, desc = 'Debug: Toggle UI' },
      { '<leader>xe', dapui 'eval', mode = { 'n', 'v' }, desc = 'Debug: Evaluate Expression' },
      { '<leader>xc', dap 'clear_breakpoints', desc = 'Debug: Clear All Breakpoints' },
      { '<leader>xC', dap 'run_to_cursor', desc = 'Debug: Run to Cursor' },
      { '<leader>xr', dap 'restart', desc = 'Debug: Restart' },
      { '<leader>xl', dap 'run_last', desc = 'Debug: Run Last' },
      { '<leader>xs', dap 'terminate', desc = 'Debug: Stop' },
      { '<leader>xb', tdap 'list_breakpoints', desc = 'Debug: Breakpoints' },
      { '<leader>xf', tdap 'frames', desc = 'Debug: Frames' },
      { '<leader>xv', tdap 'variables', desc = 'Debug: Variables' },
      { '<leader>xa', tdap 'commands', desc = 'Debug: Commands' },

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

    -- Like IDEA's Run / Debug tool windows: a Run (noDebug) session only opens the console
    -- at the bottom (layout 2); a Debug session opens everything. When the program ends the
    -- console stays with its output and only the debug panels (layout 1) close. Alt+5 hides it.
    -- Hooked on the launch / attach response: in noDebug mode the Java adapter sends no `initialized` event
    local function on_start(session)
      if session.config.noDebug then
        dapui.open { layout = 2 }
      else
        dapui.open()
      end
    end
    dap.listeners.after.launch['dapui_config'] = on_start
    dap.listeners.after.attach['dapui_config'] = on_start
    local function on_end()
      dapui.close { layout = 1 }
    end
    dap.listeners.before.event_terminated['dapui_config'] = on_end
    dap.listeners.before.event_exited['dapui_config'] = on_end

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
          return vim.split(args_string, ' ', { trimempty = true })
        end,
        runInTerminal = false,
      },
    }

    -- C / C++ use the same codelldb launch configurations
    -- (build with -g, e.g. `gcc -g -O0`, to get proper breakpoints and variables)
    dap.configurations.c = dap.configurations.rust
    dap.configurations.cpp = dap.configurations.rust

    -- Python tests: debug the test method / class under the cursor with pytest
    require('dap-python').setup(get_debugpy_path(), { include_configs = false })
    require('dap-python').test_runner = 'pytest'
    local function python_test_maps(buf)
      vim.keymap.set('n', '<leader>xt', require('dap-python').test_method, { buffer = buf, desc = 'Python: Debug nearest test' })
      vim.keymap.set('n', '<leader>xT', require('dap-python').test_class, { buffer = buf, desc = 'Python: Debug test class' })
    end
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'python',
      group = vim.api.nvim_create_augroup('pc-dap-python', { clear = true }),
      callback = function(event)
        python_test_maps(event.buf)
      end,
    })
    -- Python buffers opened before nvim-dap got loaded
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == 'python' then
        python_test_maps(buf)
      end
    end

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
