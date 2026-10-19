-- Run / Debug Configurations, IDEA style:
--   F10         pick a configuration (recently used first)
--   Shift+F10   rerun the last configuration
--   Ctrl+Shift+F10  run the test under the cursor (or pick, outside tests)
-- Configurations are built from the current file: Java main classes and tests (jdtls),
-- Maven/Gradle goals, Python files and tests, C files and Makefiles.
-- Programs that don't run in the debugger (Python, C, Maven…) print into the Run window at
-- the bottom (Alt+4), which stays open after they finish. pytest results are shown like
-- jdtls shows JUnit ones: ✓ / ✗ next to the test functions, failures in the Find window.

local M = {}

-- Recently run configurations, most recent first (per Neovim session)
local history = {}
local HISTORY_SIZE = 5

local RUN, DEBUG, TASK = '▶ ', '🐞 ', '⚙ '

---------------------------------------------------------------------------
-- Run window: one terminal split at the bottom, reused by every run
---------------------------------------------------------------------------

local console = { win = nil, buf = nil }
local last_run = 'console' -- which Run window Alt+4 toggles: 'console' or 'dap'

local function console_open()
  return console.win and vim.api.nvim_win_is_valid(console.win)
end

local function show_console()
  if not console_open() then
    local prev = vim.api.nvim_get_current_win()
    vim.cmd 'botright 12split'
    console.win = vim.api.nvim_get_current_win()
    vim.wo[console.win].winfixheight = true
    if console.buf and vim.api.nvim_buf_is_valid(console.buf) then
      vim.api.nvim_win_set_buf(console.win, console.buf)
    end
    vim.api.nvim_set_current_win(prev)
  end
end

--- Run `cmd` (shell string) in the Run window; on_exit(code) runs when it finishes
function M.run_in_console(cmd, cwd, on_exit)
  last_run = 'console'
  local prev = vim.api.nvim_get_current_win()
  show_console()
  local old = console.buf
  console.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(console.win, console.buf)
  if old and vim.api.nvim_buf_is_valid(old) then
    pcall(vim.api.nvim_buf_delete, old, { force = true })
  end
  vim.api.nvim_set_current_win(console.win)
  vim.fn.jobstart(cmd, {
    term = true,
    cwd = cwd,
    on_exit = function(_, code)
      vim.schedule(function()
        if on_exit then
          on_exit(code)
        end
      end)
    end,
  })
  vim.bo[console.buf].filetype = 'pcrun'
  vim.cmd 'normal! G'
  -- keep editing while it runs, like IDEA
  if vim.api.nvim_win_is_valid(prev) then
    vim.api.nvim_set_current_win(prev)
  end
end

--- Alt+4: the Run window that was used last (console, or the debugger's console for Java)
function M.toggle_run_window(dap_toggle)
  if last_run == 'console' and console.buf and vim.api.nvim_buf_is_valid(console.buf) then
    if console_open() then
      vim.api.nvim_win_close(console.win, true)
      console.win = nil
    else
      show_console()
    end
  else
    dap_toggle()
  end
end

--- for Hide All Windows (hide_windows.lua)
function M.console_visible()
  return console_open()
end
function M.hide_console()
  if console_open() then
    vim.api.nvim_win_close(console.win, true)
  end
  console.win = nil
end
M.show_console = show_console

function M.note_dap_run()
  last_run = 'dap'
end

-- Run a shell command in the Run window
local function task(cmd, cwd)
  return function()
    M.run_in_console(cmd, cwd)
  end
end

---------------------------------------------------------------------------
-- pytest results: ✓ / ✗ next to the tests, failures in the Find window
---------------------------------------------------------------------------

local results_ns = vim.api.nvim_create_namespace 'pc-test-results'
vim.api.nvim_set_hl(0, 'PcTestPassed', { link = 'DiagnosticOk', default = true })
vim.api.nvim_set_hl(0, 'PcTestFailed', { link = 'DiagnosticError', default = true })

local function xml_unescape(s)
  return (s:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"'):gsub('&#10;', '\n'):gsub('&apos;', "'"):gsub('&amp;', '&'))
end

local function show_pytest_results(xml_file, dir)
  local f = io.open(xml_file)
  if not f then
    return
  end
  local xml = f:read '*a'
  f:close()
  os.remove(xml_file)
  local qf, passed, failed = {}, 0, 0
  local cleared = {}
  -- passed tests are self-closing <testcase …/>, others have a body up to </testcase>
  local cases, pos = {}, 1
  while true do
    local s, e, attrs = xml:find('<testcase ([^>]*)>', pos)
    if not s then
      break
    end
    local body = ''
    if attrs:sub(-1) ~= '/' then
      local close = xml:find('</testcase>', e, true)
      body = xml:sub(e + 1, (close or #xml + 1) - 1)
    end
    table.insert(cases, { attrs = attrs, body = body })
    pos = e + 1
  end
  for _, case in ipairs(cases) do
    local attrs, body = case.attrs, case.body
    local classname, name = attrs:match 'classname="([^"]*)"', attrs:match ' name="([^"]*)"'
    name = name and name:gsub('%[.*$', '') -- parametrized: test_x[1] -> test_x
    local failure = body:match '<failure message="([^"]*)"' or body:match '<error message="([^"]*)"'
    -- tests.test_calc.TestX -> tests/test_calc.py
    local parts = vim.split(classname or '', '.', { plain = true })
    local file
    for n = #parts, 1, -1 do
      local candidate = vim.fs.joinpath(dir, table.concat(vim.list_slice(parts, 1, n), '/') .. '.py')
      if vim.uv.fs_stat(candidate) then
        file = candidate
        break
      end
    end
    local buf = file and vim.fn.bufnr(file)
    if buf and buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
      if not cleared[buf] then
        vim.api.nvim_buf_clear_namespace(buf, results_ns, 0, -1)
        cleared[buf] = true
      end
      for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line:match('^%s*def%s+' .. vim.pesc(name) .. '%s*%(') or line:match('^%s*async%s+def%s+' .. vim.pesc(name) .. '%s*%(') then
          vim.api.nvim_buf_set_extmark(buf, results_ns, lnum - 1, 0, {
            virt_text = { failure and { '  ✗ ' .. xml_unescape(failure):gsub('\n.*', ''), 'PcTestFailed' } or { '  ✓', 'PcTestPassed' } },
          })
          break
        end
      end
    end
    if failure then
      failed = failed + 1
      local lnum = body:match(vim.pesc(vim.fn.fnamemodify(file or '', ':t')) .. ':(%d+)')
      table.insert(qf, { filename = file, lnum = tonumber(lnum) or 1, text = name .. ': ' .. xml_unescape(failure):gsub('\n.*', '') })
    else
      passed = passed + 1
    end
  end
  if #qf > 0 then
    vim.fn.setqflist({}, ' ', { title = 'pytest failures', items = qf })
  end
  vim.notify(
    ('Tests: %d passed, %d failed%s'):format(passed, failed, failed > 0 and ' (Alt+3: failures)' or ''),
    failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO
  )
end

local function pytest(python, target, dir)
  return function()
    local xml = vim.fn.tempname() .. '.xml'
    M.run_in_console(('%s -m pytest %s --junitxml=%s'):format(python, target, xml), dir, function()
      show_pytest_results(xml, dir)
    end)
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
        dap = true,
        run = at_cursor(function()
          jdtls.test_nearest_method { config_overrides = { noDebug = true } }
        end),
      })
      table.insert(items, { label = DEBUG .. name, run = at_cursor(jdtls.test_nearest_method) })
    end
    table.insert(items, {
      label = RUN .. file .. ' (all tests)',
      dap = true,
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
        dap = true,
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
      table.insert(items, { label = RUN .. name .. '::' .. fn, run = pytest(python, vim.fn.shellescape(path .. '::' .. fn), dir) })
      table.insert(items, {
        label = DEBUG .. name .. '::' .. fn,
        run = at_cursor(function()
          dap_python().test_method()
        end),
      })
    end
    table.insert(items, { label = RUN .. name .. ' (all tests)', run = pytest(python, vim.fn.shellescape(path), dir) })
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
  table.insert(items, { label = TASK .. 'pytest (all)', run = pytest(python, '', dir) })
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
    for _, target in ipairs { 'run', 'test' } do
      if vim.fn.system({ 'make', '-C', dir, '-n', target }):match 'No rule' == nil and vim.v.shell_error == 0 then
        table.insert(items, { label = TASK .. 'make ' .. target, run = task('make ' .. target, dir) })
      end
    end
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
  -- runs in the debugger (Java, every Debug) show their output in the debugger's console
  if item.dap or item.label:sub(1, #DEBUG) == DEBUG then
    M.note_dap_run()
  end
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

--- Configurations for the current file whose label passes `filter` (gutter ▶ icons)
function M.pick_for(filter)
  local provider = providers[vim.bo.filetype]
  if not provider then
    return
  end
  provider(function(items)
    local list = vim.tbl_filter(function(item)
      return filter(item.label)
    end, items)
    if #list == 0 then
      return M.pick()
    end
    vim.ui.select(list, {
      prompt = 'Run',
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
