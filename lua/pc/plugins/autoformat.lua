return { -- Autoformat
  'stevearc/conform.nvim',
  cmd = { 'ConformInfo' },
  event = 'BufWritePre',
  keys = {
    {
      -- Reformat Code (Cmd+Shift+L in IDEA; <leader>f is Find Usages)
      '<M-L>',
      function()
        local conform = require 'conform'
        local lsp = #vim.lsp.get_clients { bufnr = 0, method = 'textDocument/formatting' } > 0
        if #conform.list_formatters_to_run(0) == 0 and not lsp then
          -- no formatter installed (prettier / jsonls need npm…): the indentation at least, and why
          -- (it did nothing, silently: the log had JSON re-indented by hand after three tries)
          local view = vim.fn.winsaveview()
          vim.cmd(vim.fn.mode():match '[vV\22]' and 'normal! =' or 'keepjumps normal! gg=G')
          vim.fn.winrestview(view)
          return vim.notify(('Reformat Code: no formatter for %s installed (:Mason), indentation fixed'):format(vim.bo.filetype), vim.log.levels.INFO)
        end
        conform.format({ async = true, lsp_format = 'fallback' }, function(err)
          if err then
            vim.notify('Reformat Code: ' .. err, vim.log.levels.WARN)
          end
        end)
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
