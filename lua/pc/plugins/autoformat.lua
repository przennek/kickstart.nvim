return { -- Autoformat
  'stevearc/conform.nvim',
  cmd = { 'ConformInfo' },
  keys = {
    {
      -- Reformat Code (Cmd+Shift+L in IDEA; <leader>f is Find Usages)
      '<M-L>',
      function()
        require('conform').format { async = true, lsp_format = 'fallback' }
      end,
      mode = '',
      desc = 'Reformat Code',
    },
  },
  opts = {
    notify_on_error = false,
    -- No format on save: like in IDEA, code is reformatted on demand with Alt+Shift+L,
    -- so saving never rewrites whole files in shared repositories
    formatters_by_ft = {
      lua = { 'stylua' },
      python = { 'ruff_organize_imports', 'ruff_format' },
      c = { 'clang-format' },
      cpp = { 'clang-format' },
      javascript = { 'prettier' },
      javascriptreact = { 'prettier' },
      typescript = { 'prettier' },
      typescriptreact = { 'prettier' },
      json = { 'prettier' },
      yaml = { 'prettier' },
      markdown = { 'prettier' },
      terraform = { 'terraform_fmt' },
      hcl = { 'terraform_fmt' },
      -- java: no formatter here, falls back to jdtls
    },
  },
}
