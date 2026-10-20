return { -- Autoformat
  'stevearc/conform.nvim',
  cmd = { 'ConformInfo' },
  event = 'BufWritePre',
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
    -- off by default; Settings → Editor → "Reformat code on save" turns it on
    format_on_save = function()
      if vim.g.pc_format_on_save then
        return { timeout_ms = 1500, lsp_format = 'fallback' }
      end
    end,
    -- Normally no format on save: like in IDEA, code is reformatted on demand with Alt+Shift+L,
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
