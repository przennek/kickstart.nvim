-- this file contains multiple plugins, all related to LSP config
-- Java (jdtls) is configured separately in java.lua via nvim-jdtls

return {
  {
    -- `lazydev` configures Lua LSP for your Neovim config, runtime and plugins
    -- used for completion, annotations and signatures of Neovim apis
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        -- Load luvit types when the `vim.uv` word is found
        { path = 'luvit-meta/library', words = { 'vim%.uv' } },
      },
    },
  },
  { 'Bilal2453/luvit-meta', lazy = true },
  {
    -- Main LSP Configuration
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs and related tools to stdpath for Neovim
      { 'mason-org/mason.nvim', config = true }, -- NOTE: Must be loaded before dependants
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- LSP progress goes to the status bar and the Notifications window (pc.notifications)

      -- Allows extra capabilities provided by nvim-cmp
      'hrsh7th/cmp-nvim-lsp',

      -- JSON / YAML schemas (Kubernetes, GitHub Actions, docker-compose, …)
      'b0o/SchemaStore.nvim',
    },
    config = function()
      -- Neovim's built-in gr* LSP maps would make `gr` (references) wait for a second key
      for _, lhs in ipairs { 'grn', 'grr', 'gri', 'grt', 'grx' } do
        pcall(vim.keymap.del, 'n', lhs)
      end
      pcall(vim.keymap.del, { 'n', 'x' }, 'gra')

      --  This function gets run when an LSP attaches to a particular buffer.
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            vim.keymap.set(mode or 'n', keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end
          local builtin = require 'telescope.builtin'

          -- Navigation. To jump back, press <C-o> / <M-h>.
          map('gd', builtin.lsp_definitions, 'Go to Declaration')
          map('gr', builtin.lsp_references, 'Show Usages (popup)')
          map('gI', builtin.lsp_implementations, 'Go to Implementation')
          map('gD', vim.lsp.buf.declaration, 'Go to declaration (C header / forward declaration)')
          -- Go to Declaration (Cmd+B)
          map('<M-b>', builtin.lsp_definitions, 'Go to Declaration')
          map('<leader>D', builtin.lsp_type_definitions, 'Go to Type Declaration')
          map('<leader>ws', builtin.lsp_dynamic_workspace_symbols, 'Go to Symbol')
          -- Find Usages into the Find window at the bottom (Alt+F7; F55 inside tmux).
          -- `gr` is the popup version, like Ctrl+Alt+F7 / Show Usages.
          local function find_usages()
            vim.lsp.buf.references(nil, {
              on_list = function(list)
                vim.fn.setqflist({}, ' ', list)
                require('trouble').open 'quickfix'
              end,
            })
          end
          map('<leader>f', find_usages, 'Find Usages')
          map('<M-F7>', find_usages, 'Find Usages')
          map('<F55>', find_usages, 'Find Usages')
          -- Call Hierarchy (<leader>h in .ideavimrc): callers; <leader>H = callees
          map('<leader>h', builtin.lsp_incoming_calls, 'Call Hierarchy (callers)')
          map('<leader>H', builtin.lsp_outgoing_calls, 'Call Hierarchy (callees)')

          -- Quick Documentation (gh; K is `ciw` from .ideavimrc) / Parameter Info (Cmd+P)
          map('gh', function()
            vim.lsp.buf.hover { border = 'rounded' }
          end, 'Quick Documentation')
          map('<M-p>', function()
            -- a server of this buffer without it (yaml, json…): IDEA's quiet "No parameter info"
            if #vim.lsp.get_clients { bufnr = 0, method = 'textDocument/signatureHelp' } == 0 then
              return vim.api.nvim_echo({ { 'No parameter info' } }, false, {})
            end
            vim.lsp.buf.signature_help { border = 'rounded' }
          end, 'Parameter Info', { 'n', 'i' })

          -- Rename (also Shift+F6; F18 inside tmux)
          map('<leader>rn', vim.lsp.buf.rename, 'Rename')
          map('<S-F6>', vim.lsp.buf.rename, 'Rename')
          map('<F18>', vim.lsp.buf.rename, 'Rename')
          -- Move (F6): jdtls' Move, elsewhere the file to a new path with imports updated
          map('<F6>', function()
            require('pc.move').move()
          end, 'Move')

          -- Show Context Actions (Alt+Enter) / Generate (<leader>g, Alt+Insert)
          -- (no <leader>c… maps: <leader>c alone is Go to Class)
          local actions = require('pc.code_actions').show
          map('<M-CR>', actions, 'Show Context Actions', { 'n', 'x' })
          map('<leader>g', actions, 'Generate', { 'n', 'x' })
          map('<M-Insert>', actions, 'Generate')

          -- Optimize Imports (Shift+Alt+O)
          map('<M-O>', function()
            vim.lsp.buf.code_action { context = { only = { 'source.organizeImports' }, diagnostics = {} }, apply = true }
          end, 'Optimize Imports')

          -- Highlight references of the word under the cursor when it rests there
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- Inlay hints (parameter names etc., like in IDEA)
          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      vim.diagnostic.config {
        severity_sort = true,
        float = { border = 'rounded', source = 'if_many' },
        underline = true,
        virtual_text = { source = 'if_many', spacing = 2 },
        signs = vim.g.have_nerd_font and {
          text = {
            [vim.diagnostic.severity.ERROR] = '󰅚 ',
            [vim.diagnostic.severity.WARN] = '󰀪 ',
            [vim.diagnostic.severity.INFO] = '󰋽 ',
            [vim.diagnostic.severity.HINT] = '󰌶 ',
          },
        } or {},
      }

      -- nvim-cmp adds capabilities, broadcast them to every server (including jdtls); file
      -- operations: renaming / moving a file (tree, F6) asks the servers for their edits first
      -- (pc.move.will_rename) - ts_ls updates imports
      vim.lsp.config('*', {
        capabilities = vim.tbl_deep_extend('force', require('cmp_nvim_lsp').default_capabilities(), {
          workspace = { fileOperations = { willRename = true, didRename = true } },
        }),
      })

      -- Language servers, by lspconfig name. Override config per server here.
      local servers = {
        -- C / C++ (needs compile_commands.json for real projects, e.g. `bear -- make` or CMake)
        clangd = {},
        -- Python: basedpyright (pyright fork: adds Go to Implementation, inlay hints, semantic
        -- highlighting) for types / navigation, ruff for lint / format / imports
        basedpyright = {
          settings = {
            basedpyright = {
              -- "recommended" (the default) is much stricter than IDEA's inspections
              analysis = { typeCheckingMode = 'standard' },
            },
          },
          -- Use the project's .venv as the interpreter, like IDEA's project SDK.
          -- (Settings are changed on the running client: edits made to `config` in
          -- before_init don't reach the server.)
          on_init = function(client)
            local venv = client.root_dir and vim.fs.joinpath(client.root_dir, '.venv', 'bin', 'python')
            if venv and vim.uv.fs_stat(venv) then
              client.settings = vim.tbl_deep_extend('force', client.settings or {}, { python = { pythonPath = venv } })
              client:notify('workspace/didChangeConfiguration', { settings = client.settings })
            end
          end,
        },
        ruff = {},
        gopls = {},
        ts_ls = {},
        eslint = {},
        bashls = {},
        -- YAML / Kubernetes: schemas from SchemaStore, Kubernetes for manifest directories
        yamlls = {
          settings = {
            yaml = {
              schemaStore = { enable = false, url = '' },
              schemas = vim.tbl_extend('force', require('schemastore').yaml.schemas(), {
                kubernetes = {
                  '**/k8s/**/*.yaml',
                  '**/k8s/**/*.yml',
                  '**/*manifests*/**/*.yaml',
                  '**/*manifests*/**/*.yml',
                  '**/deploy/**/*.yaml',
                  '**/deploy/**/*.yml',
                  '**/kustomize/**/*.yaml',
                  '**/kustomize/**/*.yml',
                },
              }),
            },
          },
        },
        jsonls = {
          settings = {
            json = { schemas = require('schemastore').json.schemas(), validate = { enable = true } },
          },
        },
        terraformls = {},
        dockerls = {},
        lua_ls = {
          settings = {
            Lua = {
              completion = {
                callSnippet = 'Replace',
              },
              -- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
              -- diagnostics = { disable = { 'missing-fields' } },
            },
          },
        },
      }
      for name, config in pairs(servers) do
        vim.lsp.config(name, config)
      end

      -- Ensure the servers and tools above are installed (:Mason to check)
      local ensure_installed = vim.tbl_keys(servers)
      vim.list_extend(ensure_installed, {
        'stylua', -- Used to format Lua code
        'tree-sitter-cli', -- Builds parsers for nvim-treesitter (main branch)
        'jdtls', -- Java, started by nvim-jdtls
        'java-debug-adapter',
        'java-test',
        'debugpy',
        'codelldb',
        'js-debug-adapter', -- JavaScript / TypeScript (Node) debugger
        -- linters / formatters / analysers from your IDEA plugins
        'sonarlint-language-server',
        'checkstyle', -- PMD isn't in Mason; lint.lua uses `pmd` when it is on PATH
        'tflint',
        'hadolint',
        'prettier',
      })
      -- Portable setup (Arch / macOS): a system clangd is used when there is one (pacman clang,
      -- brew llvm), Mason's otherwise; tools whose language toolchain is missing are skipped
      -- instead of failing on every start (packages to install: DEPENDENCIES.md)
      local needs = {
        clangd = 'clangd-missing',
        gopls = 'go',
        ts_ls = 'npm',
        eslint = 'npm',
        jsonls = 'npm',
        yamlls = 'npm',
        dockerls = 'npm',
        bashls = 'npm',
        prettier = 'npm',
        basedpyright = 'python3',
        debugpy = 'python3',
        ['js-debug-adapter'] = 'node',
        jdtls = 'java',
        ['java-debug-adapter'] = 'java',
        ['java-test'] = 'java',
        ['sonarlint-language-server'] = 'java',
        checkstyle = 'java',
      }
      local missing = {}
      ensure_installed = vim.tbl_filter(function(name)
        local tool = needs[name]
        if tool == 'clangd-missing' then
          return vim.fn.executable 'clangd' == 0
        end
        if tool and vim.fn.executable(tool) == 0 then
          missing[tool] = true
          return false
        end
        return true
      end, ensure_installed)
      if next(missing) then
        vim.schedule(function()
          vim.notify(
            ('Not installed: %s — some language tools are skipped (see DEPENDENCIES.md)'):format(table.concat(vim.tbl_keys(missing), ', ')),
            vim.log.levels.WARN
          )
        end)
      end
      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      require('mason-lspconfig').setup {
        ensure_installed = {},
        automatic_enable = { exclude = { 'jdtls', 'pyright' } },
      }
      vim.lsp.enable 'clangd'
    end,
  },
}
