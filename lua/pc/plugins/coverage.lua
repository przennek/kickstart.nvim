-- Run with Coverage like IDEA (Ctrl+F9): runs the tests with coverage and colours the gutter
-- (green covered, red not covered, yellow partly), with a summary per file.
--   Ctrl+F9 / <leader>xk   run the project's tests with coverage (Java: Maven + JaCoCo, Python:
--                          coverage.py + pytest from the project's .venv)
--   <leader>xK             toggle the coverage marks, :CoverageSummary for the table
return {
  'andythigpen/nvim-coverage',
  -- the JaCoCo report is read with neotest's XML parser
  dependencies = { 'nvim-lua/plenary.nvim', { 'nvim-neotest/neotest', dependencies = { 'nvim-neotest/nvim-nio' } } },
  cmd = { 'Coverage', 'CoverageLoad', 'CoverageShow', 'CoverageHide', 'CoverageToggle', 'CoverageSummary', 'CoverageClear' },
  keys = {
    { '<C-F9>', function() require('pc.coverage').run() end, desc = 'Run with Coverage' },
    { '<F33>', function() require('pc.coverage').run() end, desc = 'Run with Coverage' },
    { '<leader>xk', function() require('pc.coverage').run() end, desc = 'Run with Coverage' },
    { '<leader>xK', '<cmd>CoverageToggle<CR>', desc = 'Toggle coverage marks' },
  },
  opts = {
    commands = true,
    auto_reload = true,
    lang = {
      java = { coverage_file = 'target/site/jacoco/jacoco.xml', dir_prefix = 'src/main/java' },
      python = { only_open_buffers = false },
    },
  },
}
