-- Run with Coverage for the project of the current file (see plugins/coverage.lua):
--   Java    mvn jacoco:prepare-agent test jacoco:report (no pom.xml changes needed)
--   Python  .venv/bin/python -m coverage run -m pytest (the plugin reads .coverage with the same python)
-- The output goes to the Run window; afterwards the marks are loaded and the summary shown.

local M = {}

local JACOCO = 'org.jacoco:jacoco-maven-plugin:0.8.12'

local function show(lang, root, python)
  -- the report's paths are taken from this project, wherever Neovim's working directory is
  local opts = require('coverage.config').opts.lang
  if lang == 'java' then
    opts.java.coverage_file = root .. '/target/site/jacoco/jacoco.xml'
    opts.java.dir_prefix = root .. '/src/main/java'
  elseif vim.fn.getcwd() ~= root then
    -- coverage.py writes paths relative to the project
    vim.cmd.lcd(root)
  end
  opts.python.coverage_file = root .. '/.coverage'
  if python then
    opts.python.coverage_command = vim.fn.shellescape(python) .. ' -m coverage json --fail-under=0 -q -o -'
  end
  vim.cmd 'CoverageLoad'
  vim.defer_fn(function()
    vim.cmd 'CoverageShow'
    vim.notify(('Coverage loaded (%s): marks in the gutter, :CoverageSummary for the table'):format(lang))
  end, 300)
end

function M.run()
  require('lazy').load { plugins = { 'nvim-coverage' } }
  local run = require 'pc.run'
  local ft = vim.bo.filetype
  if ft == 'java' then
    local root = vim.fs.root(0, { 'mvnw', 'pom.xml' })
    if not root or not vim.uv.fs_stat(root .. '/pom.xml') then
      return vim.notify('Coverage: Java needs a Maven project', vim.log.levels.WARN)
    end
    local mvn = vim.uv.fs_stat(root .. '/mvnw') and './mvnw' or 'mvn'
    -- failing tests still give a report, like in IDEA
    local cmd = ('%s %s:prepare-agent test -Dmaven.test.failure.ignore=true %s:report'):format(mvn, JACOCO, JACOCO)
    run.run_in_console(cmd, root, function(code)
      if code == 0 then
        show('java', root)
      else
        vim.notify('Coverage: tests failed, see the Run window', vim.log.levels.WARN)
      end
    end)
  elseif ft == 'python' then
    local root = vim.fs.root(0, { 'pyproject.toml', 'setup.py', 'setup.cfg', '.venv' }) or vim.fn.getcwd()
    local python = vim.uv.fs_stat(root .. '/.venv/bin/python') and root .. '/.venv/bin/python' or 'python3'
    if vim.system({ python, '-c', 'import coverage' }):wait().code ~= 0 then
      return vim.notify(('Coverage: install it in the project: %s -m pip install coverage'):format(python), vim.log.levels.WARN)
    end
    local q = vim.fn.shellescape(python)
    -- failing tests still give a report, like in IDEA
    run.run_in_console(q .. ' -m coverage run -m pytest', root, function(code)
      -- failing tests still give a report, like in IDEA
      show('python', root, python)
      if code ~= 0 then
        vim.notify('Coverage: some tests failed, see the Run window', vim.log.levels.WARN)
      end
    end)
  else
    vim.notify('Run with Coverage: Java (Maven) and Python projects', vim.log.levels.INFO)
  end
end

return M
