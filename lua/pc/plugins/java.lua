-- Java via nvim-jdtls: LSP, Lombok, debugging, running tests, refactorings.
-- JDKs come from SDKMAN (~/.sdkman/candidates/java), so this works even when
-- Neovim is started without the SDKMAN shell init (e.g. from the GNOME launcher).

local function jdk_home()
  local sdkman = vim.fs.joinpath(vim.env.HOME, '.sdkman', 'candidates', 'java', 'current')
  if vim.uv.fs_stat(sdkman) then
    return vim.uv.fs_realpath(sdkman)
  end
  return vim.env.JAVA_HOME
end

-- Every installed JDK is offered to jdtls, like IDEA's SDK table; the default one is the
-- project's SDK from Project Structure (pc.project_structure), else SDKMAN's current
local function jdk_runtimes(root)
  local structure = require 'pc.project_structure'
  local default = structure.sdk(root) or jdk_home()
  local runtimes, seen = {}, {}
  for _, home in ipairs(structure.jdks()) do
    local major = structure.java_version(home)
    if major and not seen[major] then
      seen[major] = true
      local name = tonumber(major) <= 8 and ('JavaSE-1.' .. major) or ('JavaSE-' .. major)
      table.insert(runtimes, { name = name, path = home, default = vim.uv.fs_realpath(home) == vim.uv.fs_realpath(default) })
    end
  end
  return runtimes
end

local function start_jdtls()
  local jdtls = require 'jdtls'
  local mason = vim.fn.stdpath 'data' .. '/mason'
  local root_dir = vim.fs.root(0, { 'mvnw', 'gradlew', 'pom.xml', 'build.gradle', 'build.gradle.kts', 'settings.gradle', '.git' })
    or vim.fn.getcwd()
  local workspace = vim.fn.stdpath 'cache' .. '/jdtls/' .. root_dir:gsub('/', '_')

  -- Debugger + test runner extensions
  local bundles = vim.fn.glob(mason .. '/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar', true, true)
  for _, jar in ipairs(vim.fn.glob(mason .. '/packages/java-test/extension/server/*.jar', true, true)) do
    if not jar:match 'com.microsoft.java.test.runner%-jar%-with%-dependencies' and not jar:match 'jacocoagent' then
      table.insert(bundles, jar)
    end
  end

  local settings = {
    java = {
      configuration = { runtimes = jdk_runtimes(root_dir) },
      eclipse = { downloadSources = true },
      maven = { downloadSources = true },
      references = { includeDecompiledSources = true },
      implementationsCodeLens = { enabled = true },
      referencesCodeLens = { enabled = true },
      inlayHints = { parameterNames = { enabled = 'all' } },
      signatureHelp = { enabled = true },
      contentProvider = { preferred = 'fernflower' }, -- decompiler, like IDEA
      sources = { organizeImports = { starThreshold = 5, staticStarThreshold = 3 } },
      completion = {
        -- postfix templates come from lua/pc/postfix.lua (jdtls' .var always says Object)
        postfix = { enabled = false },
        favoriteStaticMembers = {
          'org.junit.jupiter.api.Assertions.*',
          'org.junit.Assert.*',
          'org.mockito.Mockito.*',
          'org.assertj.core.api.Assertions.*',
        },
      },
    },
  }

  local java_home = jdk_home()
  jdtls.start_or_attach {
    name = 'jdtls',
    cmd = {
      mason .. '/bin/jdtls',
      '--jvm-arg=-javaagent:' .. mason .. '/packages/jdtls/lombok.jar',
      '-data',
      workspace,
    },
    cmd_env = java_home and { JAVA_HOME = java_home, PATH = java_home .. '/bin:' .. vim.env.PATH } or nil,
    root_dir = root_dir,
    capabilities = require('cmp_nvim_lsp').default_capabilities(),
    -- settings go in init_options too: jdtls reads some of them only during initialize
    init_options = { bundles = bundles, settings = settings },
    settings = settings,
    -- "Starting…" / "ServiceReady" go to the Notifications window, not the command line
    handlers = {
      ['language/status'] = function(_, result)
        vim.notify(result.message, vim.log.levels.DEBUG, { title = 'jdtls' })
      end,
    },
    on_attach = function(_, bufnr)
      -- Hot code replace on every change, same as RunHotswapAlways in your IDEA debugger settings
      jdtls.setup_dap { hotcodereplace = 'auto' }
      require('jdtls.dap').setup_dap_main_class_configs()

      local map = function(mode, keys, func, desc)
        vim.keymap.set(mode, keys, func, { buffer = bufnr, desc = desc })
      end
      -- Tests (run in the debugger, so breakpoints work)
      map('n', '<leader>xt', jdtls.test_nearest_method, 'Debug nearest test')
      map('n', '<leader>xT', jdtls.test_class, 'Debug test class')
      map('n', '<leader>xp', jdtls.pick_test, 'Pick test')
      -- Refactor > Extract: <leader>e + v(ariable) / c(onstant) / m(ethod)
      -- (Cmd+Alt+V/C/M in IDEA; <leader>c alone is Go to Class)
      -- jdtls reads the selection from the '< '> marks, which are only set once Visual mode ends
      local function extract(fn)
        return function()
          local visual = vim.fn.mode():match '^[vV\22]' ~= nil
          if visual then
            vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'nx', false)
          end
          fn(visual)
        end
      end
      map({ 'n', 'x' }, '<leader>ev', extract(jdtls.extract_variable), 'Extract variable')
      map({ 'n', 'x' }, '<leader>ec', extract(jdtls.extract_constant), 'Extract constant')
      map('x', '<leader>em', extract(jdtls.extract_method), 'Extract method')
      -- Ctrl+Alt+M is Extract Method in your IDEA keymap too (Alacritty sends it as F43:
      -- a terminal can't tell Ctrl+Alt+M from Alt+Enter)
      map('x', '<F43>', extract(jdtls.extract_method), 'Extract method')
      map({ 'n', 'x' }, '<leader>ei', function()
        vim.lsp.buf.code_action { context = { only = { 'refactor.inline' }, diagnostics = {} } }
      end, 'Inline')
      -- Override / Implement Methods (Cmd+O)
      map('n', '<M-o>', function()
        vim.lsp.buf.code_action {
          filter = function(a)
            return a.title:match 'Override' ~= nil
          end,
          context = { only = { 'source' }, diagnostics = {} },
        }
      end, 'Override / implement methods')
      map('n', '<M-O>', jdtls.organize_imports, 'Optimize Imports')
      -- Go to Test (Cmd+Shift+T) / Super method
      map('n', '<M-T>', function()
        require('jdtls.tests').goto_subjects()
      end, 'Go to Test')
      map('n', 'gs', jdtls.super_implementation, 'Go to Super Method')
    end,
  }
end

return {
  'mfussenegger/nvim-jdtls',
  ft = 'java',
  dependencies = { 'mfussenegger/nvim-dap', 'hrsh7th/cmp-nvim-lsp' },
  config = function()
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'java',
      group = vim.api.nvim_create_augroup('pc-jdtls', { clear = true }),
      callback = start_jdtls,
    })
    -- The FileType event that triggered loading this plugin already fired
    if vim.bo.filetype == 'java' then
      start_jdtls()
    end
  end,
}
