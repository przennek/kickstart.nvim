-- Run / Debug Configurations, IDEA style:
--   F10         pick a configuration (recently used first)
--   Shift+F10   rerun the last configuration
--   Ctrl+Shift+F10  run the test under the cursor (or pick, outside tests)
-- Configurations are built from the current file: Java main classes and tests (jdtls),
-- Maven/Gradle goals, Python files and tests, C files and Makefiles.

local M = {}

-- Recently run configurations, most recent first (per Neovim session)
local history = {}
local HISTORY_SIZE = 5

local RUN, DEBUG, TASK = '▶ ', '🐞 ', '⚙ '

-- Run a shell command in a dedicated terminal (number 9, separate from the Alt+T one)
local function task(cmd, cwd)
  return function()
    require('toggleterm').exec(cmd, 9, nil, cwd)
  end
end

-- Re-establish the file and cursor position the configuration was created from,
-- so it can be rerun later from anywhere
local function at_cursor(fn)
  local file = vim.api.nvim_buf_get_name(0)
  local pos = vim.api.nvim_win_get_cursor(0)
  return function()
    if vim.api.nvim_buf_get_name(0) ~= file then
      vim.cmd.edit(vim.fn.fnameescape(file))
    end
    pcall(vim.api.nvim_win_set_cursor, 0, pos)
    fn()
  end
end

-- Name of the enclosing method / function at the cursor (treesitter)
local function enclosing(types)
  local ok, node = pcall(vim.treesitter.get_node)
  while ok and node do
    if vim.tbl_contains(types, node:type()) then
      local name = node:field('name')[1]
      return name and vim.treesitter.get_node_text(name, 0)
    end
    node = node:parent()
  end
end

local function root(markers)
  return vim.fs.root(0, markers) or vim.fn.getcwd()
end

local function java_items(callback)
  local items = {}
  local file = vim.fn.expand '%:t:r'
  local jdtls = require 'jdtls'
  local dir = root { 'mvnw', 'gradlew', 'pom.xml', 'build.gradle', 'build.gradle.kts', '.git' }

  if vim.fn.expand('%:p'):match '/src/test/' or file:match 'Tests?$' then
    local method = enclosing { 'method_declaration' }
    if method then
      local name = file .. '.' .. method
      table.insert(items, {
        label = RUN .. name,
        run = at_cursor(function()
          jdtls.test_nearest_method { config_overrides = { noDebug = true } }
        end),
      })
      table.insert(items, { label = DEBUG .. name, run = at_cursor(jdtls.test_nearest_method) })
    end
    table.insert(items, {
      label = RUN .. file .. ' (all tests)',
      run = at_cursor(function()
        jdtls.test_class { config_overrides = { noDebug = true } }
      end),
    })
    table.insert(items, { label = DEBUG .. file .. ' (all tests)', run = at_cursor(jdtls.test_class) })
  end

  local build
  if vim.uv.fs_stat(dir .. '/pom.xml') then
    build = vim.uv.fs_stat(dir .. '/mvnw') and './mvnw' or 'mvn'
    for _, goal in ipairs { 'test', 'package', 'clean install', 'compile' } do
      table.insert(items, { label = TASK .. build .. ' ' .. goal, run = task(build .. ' ' .. goal, dir) })
    end
  elseif vim.uv.fs_stat(dir .. '/gradlew') or vim.uv.fs_stat(dir .. '/build.gradle') or vim.uv.fs_stat(dir .. '/build.gradle.kts') then
    build = vim.uv.fs_stat(dir .. '/gradlew') and './gradlew' or 'gradle'
    for _, goal in ipairs { 'test', 'build', 'run', 'clean build' } do
      table.insert(items, { label = TASK .. build .. ' ' .. goal, run = task(build .. ' ' .. goal, dir) })
    end
  end

  -- Main classes are discovered asynchronously by jdtls
  local ok = pcall(require('jdtls.dap').fetch_main_configs, nil, function(configs)
    local mains = {}
    for _, config in ipairs(configs) do
      local name = config.mainClass:match '[^.]+$'
      table.insert(mains, {
        label = RUN .. name,
        run = function()
          require('dap').run(vim.tbl_extend('force', config, { noDebug = true }))
        end,
      })
      table.insert(mains, {
        label = DEBUG .. name,
        run = function()
          require('dap').run(config)
        end,
      })
    end
    vim.schedule(function()
      callback(vim.list_extend(mains, items))
    end)
  end)
  if not ok then
    callback(items)
  end
end

local function python_items(callback)
  local items = {}
  local path = vim.fn.expand '%:p'
  local name = vim.fn.expand '%:t'
  local dir = root { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.venv', '.git' }
  local venv = dir .. '/.venv/bin/python'
  local python = vim.uv.fs_stat(venv) and venv or 'python3'
  local dap_python = function()
    require('lazy').load { plugins = { 'nvim-dap' } }
    return require 'dap-python'
  end

  if name:match '^test_' or name:match '_test%.py$' then
    local fn = enclosing { 'function_definition' }
    if fn then
      table.insert(items, { label = RUN .. name .. '::' .. fn, run = task(python .. ' -m pytest ' .. vim.fn.shellescape(path) .. '::' .. fn, dir) })
      table.insert(items, {
        label = DEBUG .. name .. '::' .. fn,
        run = at_cursor(function()
          dap_python().test_method()
        end),
      })
    end
    table.insert(items, { label = RUN .. name .. ' (all tests)', run = task(python .. ' -m pytest ' .. vim.fn.shellescape(path), dir) })
    table.insert(items, {
      label = DEBUG .. name .. ' (all tests)',
      run = at_cursor(function()
        dap_python().test_class()
      end),
    })
  end
  table.insert(items, { label = RUN .. name, run = task(python .. ' ' .. vim.fn.shellescape(path), dir) })
  table.insert(items, {
    label = DEBUG .. name,
    run = at_cursor(function()
      local dap = require 'dap'
      dap.run(dap.configurations.python[1])
    end),
  })
  table.insert(items, { label = TASK .. 'pytest (all)', run = task(python .. ' -m pytest', dir) })
  callback(items)
end

local function c_items(callback)
  local items = {}
  local path = vim.fn.expand '%:p'
  local name = vim.fn.expand '%:t'
  local exe = vim.fn.expand '%:p:r'
  local compiler = vim.bo.filetype == 'cpp' and 'c++' or 'cc'
  local compile = { compiler, '-g', '-O0', '-Wall', path, '-o', exe }
  local dir = root { 'Makefile', 'CMakeLists.txt', 'compile_commands.json', '.git' }

  table.insert(items, {
    label = RUN .. name,
    run = task(table.concat(vim.tbl_map(vim.fn.shellescape, compile), ' ') .. ' && ' .. vim.fn.shellescape(exe), vim.fn.expand '%:p:h'),
  })
  table.insert(items, {
    label = DEBUG .. name,
    run = function()
      local result = vim.system(compile):wait()
      if result.code ~= 0 then
        vim.notify(result.stderr, vim.log.levels.ERROR, { title = 'Compilation failed' })
        return
      end
      local dap = require 'dap'
      dap.run(vim.tbl_extend('force', dap.configurations.c[1], { program = exe }))
    end,
  })
  if vim.uv.fs_stat(dir .. '/Makefile') then
    table.insert(items, { label = TASK .. 'make', run = task('make', dir) })
    table.insert(items, { label = TASK .. 'make clean', run = task('make clean', dir) })
  end
  table.insert(items, {
    label = DEBUG .. 'executable…',
    run = function()
      local dap = require 'dap'
      dap.run(dap.configurations.c[1])
    end,
  })
  callback(items)
end

local providers = { java = java_items, python = python_items, c = c_items, cpp = c_items }

local function execute(item)
  for i, entry in ipairs(history) do
    if entry.label == item.label then
      table.remove(history, i)
      break
    end
  end
  table.insert(history, 1, item)
  history[HISTORY_SIZE + 1] = nil
  item.run()
end

function M.pick()
  local provider = providers[vim.bo.filetype] or function(cb)
    cb {}
  end
  provider(function(items)
    -- Recently run first, then the configurations for the current file
    local seen, list = {}, {}
    for _, item in ipairs(vim.list_extend(vim.list_slice(history), items)) do
      if not seen[item.label] then
        seen[item.label] = true
        table.insert(list, item)
      end
    end
    if #list == 0 then
      vim.notify('No run configurations for this file', vim.log.levels.WARN)
      return
    end
    vim.ui.select(list, {
      prompt = 'Run / Debug Configurations',
      format_item = function(item)
        return item.label
      end,
    }, function(item)
      if item then
        execute(item)
      end
    end)
  end)
end

function M.rerun()
  if history[1] then
    execute(history[1])
  else
    M.pick()
  end
end

-- Run / Debug the test under the cursor without the picker (Ctrl+Shift+F10 / Ctrl+Shift+F9)
local function context(prefix)
  return function()
    local provider = providers[vim.bo.filetype]
    if not provider then
      return M.pick()
    end
    provider(function(items)
      for _, item in ipairs(items) do
        if item.label:sub(1, #prefix) == prefix then
          return execute(item)
        end
      end
      M.pick()
    end)
  end
end
M.run_context = context(RUN)
M.debug_context = context(DEBUG)

local map = vim.keymap.set
-- Inside tmux Shift+F10 arrives as F22 and Ctrl+Shift+F10 as F46
map('n', '<F10>', M.pick, { desc = 'Run / Debug Configurations' })
map('n', '<S-F10>', M.rerun, { desc = 'Rerun last configuration' })
map('n', '<F22>', M.rerun, { desc = 'Rerun last configuration' })
map('n', '<C-S-F10>', M.run_context, { desc = 'Run context configuration' })
map('n', '<F46>', M.run_context, { desc = 'Run context configuration' })
map('n', '<C-S-F9>', M.debug_context, { desc = 'Debug context configuration' })
map('n', '<F45>', M.debug_context, { desc = 'Debug context configuration' })
map('n', '<leader>xx', M.pick, { desc = 'Run / Debug Configurations' })
map('n', '<leader>xR', M.rerun, { desc = 'Rerun last configuration' })

return M
