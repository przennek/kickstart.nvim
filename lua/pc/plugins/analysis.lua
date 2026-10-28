-- SonarLint (the SonarQube for IDE plugin): on-the-fly analysis with Sonar's default rules
-- for every language it has an analyzer for. Issues show up as diagnostics (F2 / Alt+6).
-- Checkstyle and PMD are in lint.lua.

local filetypes = {
  java = 'sonarjava',
  python = 'sonarpython',
  javascript = 'sonarjs',
  javascriptreact = 'sonarjs',
  typescript = 'sonarjs',
  typescriptreact = 'sonarjs',
  terraform = 'sonariac',
  dockerfile = 'sonariac',
  yaml = 'sonariac',
  xml = 'sonarxml',
  html = 'sonarhtml',
}

return {
  url = 'https://gitlab.com/schrieveslaach/sonarlint.nvim',
  ft = vim.tbl_keys(filetypes),
  dependencies = { 'neovim/nvim-lspconfig', 'mfussenegger/nvim-jdtls' },
  config = function()
    local dir = vim.fn.stdpath 'data' .. '/mason/share/sonarlint-analyzers/'
    local cmd = { 'sonarlint-language-server', '-stdio', '-analyzers' }
    local enabled = {}
    for ft, analyzer in pairs(filetypes) do
      local jar = dir .. analyzer .. '.jar'
      if vim.uv.fs_stat(jar) then
        if not vim.tbl_contains(cmd, jar) then
          table.insert(cmd, jar)
        end
        table.insert(enabled, ft)
      end
    end
    if #enabled == 0 then
      return vim.notify('sonarlint-language-server is not installed yet (:Mason)', vim.log.levels.WARN)
    end
    require('sonarlint').setup {
      server = { cmd = cmd },
      filetypes = enabled,
    }
    --     require('pc.lsp_guard').sonarlint()
  end,
}
