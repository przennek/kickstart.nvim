return {

  { -- Linting
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local lint = require 'lint'
      lint.linters_by_ft = {
        markdown = { 'markdownlint' },
        dockerfile = { 'hadolint' },
      }

      -- Checkstyle and PMD for Java (CheckStyle-IDEA / PMDPlugin). They are slow, so they run
      -- on save only. Checkstyle needs the project's own config; PMD uses the project's ruleset
      -- if there is one, otherwise PMD's quickstart rules.
      local function project_file(names)
        local root = vim.fs.root(0, { 'pom.xml', 'build.gradle', 'build.gradle.kts', '.git' })
        for _, name in ipairs(root and names or {}) do
          local path = root .. '/' .. name
          if vim.uv.fs_stat(path) then
            return path
          end
        end
      end
      local function java_linters()
        local linters = {}
        local checkstyle = project_file { 'checkstyle.xml', 'config/checkstyle/checkstyle.xml', '.checkstyle.xml' }
        if checkstyle and vim.fn.executable 'checkstyle' == 1 then
          require('lint.linters.checkstyle').config_file = checkstyle
          table.insert(linters, 'checkstyle')
        end
        if vim.fn.executable 'pmd' == 1 then
          require('lint.linters.pmd').rulesets = project_file { 'pmd.xml', 'pmd-ruleset.xml', 'config/pmd/ruleset.xml' }
            or 'rulesets/java/quickstart.xml'
          table.insert(linters, 'pmd')
        end
        return linters
      end
      vim.api.nvim_create_autocmd('BufWritePost', {
        group = vim.api.nvim_create_augroup('lint-java', { clear = true }),
        pattern = '*.java',
        callback = function()
          lint.try_lint(java_linters(), { ignore_errors = true })
        end,
      })

      -- To allow other plugins to add linters to require('lint').linters_by_ft,
      -- instead set linters_by_ft like this:
      -- lint.linters_by_ft = lint.linters_by_ft or {}
      -- lint.linters_by_ft['markdown'] = { 'markdownlint' }
      --
      -- However, note that this will enable a set of default linters,
      -- which will cause errors unless these tools are available:
      -- {
      --   clojure = { "clj-kondo" },
      --   dockerfile = { "hadolint" },
      --   inko = { "inko" },
      --   janet = { "janet" },
      --   json = { "jsonlint" },
      --   markdown = { "vale" },
      --   rst = { "vale" },
      --   ruby = { "ruby" },
      --   terraform = { "tflint" },
      --   text = { "vale" }
      -- }
      --
      -- You can disable the default linters by setting their filetypes to nil:
      -- lint.linters_by_ft['clojure'] = nil
      -- lint.linters_by_ft['dockerfile'] = nil
      -- lint.linters_by_ft['inko'] = nil
      -- lint.linters_by_ft['janet'] = nil
      -- lint.linters_by_ft['json'] = nil
      -- lint.linters_by_ft['markdown'] = nil
      -- lint.linters_by_ft['rst'] = nil
      -- lint.linters_by_ft['ruby'] = nil
      -- lint.linters_by_ft['terraform'] = nil
      -- lint.linters_by_ft['text'] = nil

      -- Create autocommand which carries out the actual linting
      -- on the specified events.
      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = lint_augroup,
        callback = function()
          -- linters that aren't installed (e.g. markdownlint) are skipped silently
          lint.try_lint(nil, { ignore_errors = true })
        end,
      })
    end,
  },
}
