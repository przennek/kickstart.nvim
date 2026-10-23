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
  -- Eclipse's project files in .idea/nvim/eclipse (pc.project_store)
  local workspace = require('pc.project_store').jdtls_workspace(root_dir)

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
        -- never suggested / auto-imported: jdtls' defaults + your IDEA auto-import exclusions
        filteredTypes = {
          'java.awt.*',
          'com.sun.*',
          'sun.*',
          'jdk.*',
          'org.graalvm.*',
          'io.micrometer.shaded.*',
          'org.hamcrest.CoreMatchers',
          'org.hamcrest.EasyMock2Matchers.equalTo',
          'org.hamcrest.JMock1Matchers',
        },
      },
      -- Go to Symbol / Search Everywhere → Symbols find methods too, not only classes
      symbols = { includeSourceMethodDeclarations = true },
      -- Generate (equals / hashCode, …) like your IDEA: instanceof in equals, braces always
      codeGeneration = {
        hashCodeEquals = { useInstanceof = true, useJava7Objects = true },
        useBlocks = true,
      },
    },
  }

  local java_home = jdk_home()
  jdtls.start_or_attach {
    name = 'jdtls',
    cmd = {
      mason .. '/bin/jdtls',
      '--jvm-arg=-javaagent:' .. mason .. '/packages/jdtls/lombok.jar',
      -- Eclipse's .project / .classpath / .settings / .factorypath go into the workspace, not into
      -- the project root (a system property of jdtls' filesystem plugin, not a setting)
      '--jvm-arg=-Djava.import.generatesMetadataFilesAtProjectRoot=false',
      '-data',
      workspace,
    },
    cmd_env = java_home and { JAVA_HOME = java_home, PATH = java_home .. '/bin:' .. vim.env.PATH } or nil,
    root_dir = root_dir,
    -- files changed outside nvim (an LLM agent, git, the terminal) reach jdtls' index too;
    -- Neovim leaves file watching off on Linux by default
    capabilities = vim.tbl_deep_extend('force', require('cmp_nvim_lsp').default_capabilities(), {
      workspace = {
        didChangeWatchedFiles = { dynamicRegistration = true },
        -- X.java renamed / moved in the tree: jdtls renames the class and updates its uses and
        -- the package line (pc.move.will_rename)
        fileOperations = { willRename = true, didRename = true },
      },
    }),
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
      -- test results in the Test Runner window (pc.test_runner) instead of the REPL
      require('pc.test_runner').setup()

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
      -- Like IDEA: without a selection the expression under the cursor is taken (a literal, a
      -- call, an operation…), and the new variable / constant / method gets its name in the
      -- rename box right away (the suggested name selected: type to replace it, Enter keeps it)
      local EXPRESSION = { '_literal$', '_expression$', '^method_invocation$', '^field_access$', '^array_access$', '^object_creation_expression$' }
      local function select_expression()
        local ok, node = pcall(vim.treesitter.get_node)
        while ok and node do
          for _, pattern in ipairs(EXPRESSION) do
            if node:type():match(pattern) then
              local sr, sc, er, ec = node:range()
              vim.fn.setpos("'<", { 0, sr + 1, sc + 1, 0 })
              vim.fn.setpos("'>", { 0, er + 1, ec, 0 })
              return true
            end
          end
          node = node:parent()
        end
        return false
      end
      local function extract(fn)
        return function()
          local visual = vim.fn.mode():match '^[vV\22]' ~= nil
          if visual then
            vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'nx', false)
          else
            visual = select_expression()
          end
          fn {
            visual = visual,
            name = function()
              vim.schedule(function()
                vim.lsp.buf.rename(nil, { name = 'jdtls' })
              end)
            end,
          }
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
