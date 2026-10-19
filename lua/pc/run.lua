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

-- JUnit XML -> { {classname, name, failure, body} }  (pytest, node --test, vitest)
local function read_junit(xml_file)
  local f = io.open(xml_file)
  if not f then
    return nil
  end
  local xml = f:read '*a'
  f:close()
  os.remove(xml_file)
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
    local failure = body:match '<failure[^>]-message="([^"]*)"' or body:match '<error[^>]-message="([^"]*)"'
    if not failure and body:match '<failure' then
      failure = body:match '<failure[^>]*>%s*([^\n<]*)' or 'failed'
    end
    table.insert(cases, {
      classname = attrs:match 'classname="([^"]*)"',
      name = xml_unescape(attrs:match '%f[%w]name="([^"]*)"' or ''),
      -- one line: "Expected values to be strictly equal: 30 !== 27"
      failure = failure and vim.trim(xml_unescape(failure):gsub('%s*\n%s*', ' ')):sub(1, 160),
      body = body,
    })
    pos = e + 1
  end
  return cases
end

--- ✓ / ✗ next to the tests, failures in the Find window.
--- results: { {file, name, failure?, lnum?} }; find_line(lines, name) -> line number of the test
local function show_test_results(results, find_line)
  local qf, passed, failed, cleared = {}, 0, 0, {}
  for _, r in ipairs(results) do
    local buf = r.file and vim.fn.bufnr(r.file)
    local line
    if buf and buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
      if not cleared[buf] then
        vim.api.nvim_buf_clear_namespace(buf, results_ns, 0, -1)
        cleared[buf] = true
      end
      line = find_line(vim.api.nvim_buf_get_lines(buf, 0, -1, false), r.name)
      if line then
        vim.api.nvim_buf_set_extmark(buf, results_ns, line - 1, 0, {
          virt_text = { r.failure and { '  ✗ ' .. r.failure, 'PcTestFailed' } or { '  ✓', 'PcTestPassed' } },
        })
      end
    end
    if r.failure then
      failed = failed + 1
      table.insert(qf, { filename = r.file, lnum = r.lnum or line or 1, text = r.name .. ': ' .. r.failure })
    else
      passed = passed + 1
    end
  end
  if #qf > 0 then
    vim.fn.setqflist({}, ' ', { title = 'Test failures', items = qf })
  end
  vim.notify(
    ('Tests: %d passed, %d failed%s'):format(passed, failed, failed > 0 and ' (Alt+3: failures)' or ''),
    failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO
  )
end

local function show_pytest_results(xml_file, dir)
  local results = {}
  for _, case in ipairs(read_junit(xml_file) or {}) do
    -- tests.test_calc.TestX -> tests/test_calc.py
    local parts = vim.split(case.classname or '', '.', { plain = true })
    local file
    for n = #parts, 1, -1 do
      local candidate = vim.fs.joinpath(dir, table.concat(vim.list_slice(parts, 1, n), '/') .. '.py')
      if vim.uv.fs_stat(candidate) then
        file = candidate
        break
      end
    end
    local lnum = case.failure and case.body:match(vim.pesc(vim.fn.fnamemodify(file or '', ':t')) .. ':(%d+)')
    table.insert(results, {
      file = file,
      name = case.name:gsub('%[.*$', ''), -- parametrized: test_x[1] -> test_x
      failure = case.failure,
      lnum = tonumber(lnum),
    })
  end
  show_test_results(results, function(lines, name)
    for lnum, line in ipairs(lines) do
      if line:match('^%s*def%s+' .. vim.pesc(name) .. '%s*%(') or line:match('^%s*async%s+def%s+' .. vim.pesc(name) .. '%s*%(') then
        return lnum
      end
    end
  end)
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

---------------------------------------------------------------------------
-- JavaScript / TypeScript (Node): files, npm scripts, tests (node --test, Jest, Vitest)
---------------------------------------------------------------------------

local function read_package_json(dir)
  local f = io.open(vim.fs.joinpath(dir, 'package.json'))
  if not f then
    return {}
  end
  local ok, pkg = pcall(vim.json.decode, f:read '*a')
  f:close()
  return ok and type(pkg) == 'table' and pkg or {}
end

local function test_runner(pkg)
  local deps = vim.tbl_extend('force', pkg.dependencies or {}, pkg.devDependencies or {})
  return deps.vitest and 'vitest' or deps.jest and 'jest' or 'node'
end

-- name of the it('…') / test('…') around the cursor
local function enclosing_js_test()
  local ok, node = pcall(vim.treesitter.get_node)
  while ok and node do
    if node:type() == 'call_expression' then
      local fn = node:field('function')[1]
      local fname = fn and vim.treesitter.get_node_text(fn, 0):match '^([%w_]+)'
      local args = node:field('arguments')[1]
      local first = args and args:named_child(0)
      if (fname == 'it' or fname == 'test') and first and (first:type() == 'string' or first:type() == 'template_string') then
        return vim.treesitter.get_node_text(first, 0):sub(2, -2)
      end
    end
    node = node:parent()
  end
end

local function js_test_line(lines, name)
  for lnum, line in ipairs(lines) do
    if line:find('[\'"`]' .. vim.pesc(name) .. '[\'"`]') and (line:match '%f[%w]it%s*[%.(]' or line:match '%f[%w]test%s*[%.(]') then
      return lnum
    end
  end
end

local function show_js_results(file, runner, report)
  local results = {}
  if runner == 'jest' then
    local f = io.open(report)
    local ok, data = f and pcall(vim.json.decode, f:read '*a')
    if f then
      f:close()
      os.remove(report)
    end
    for _, suite in ipairs(ok and data.testResults or {}) do
      for _, t in ipairs(suite.assertionResults or {}) do
        if t.status == 'passed' or t.status == 'failed' then
          table.insert(results, {
            file = suite.name,
            name = t.title,
            failure = t.status == 'failed' and ((t.failureMessages or {})[1] or 'failed'):gsub('\27%[[%d;]*m', ''):gsub('\n.*', '') or nil,
          })
        end
      end
    end
  else
    for _, case in ipairs(read_junit(report) or {}) do
      -- node --test also reports the describe() suites; keep the tests
      if case.name ~= '' and js_test_line(vim.fn.readfile(file), case.name) then
        local lnum = case.failure and case.body:match(vim.pesc(vim.fs.basename(file)) .. ':(%d+)')
        table.insert(results, { file = file, name = case.name, failure = case.failure, lnum = tonumber(lnum) })
      end
    end
  end
  show_test_results(results, js_test_line)
end

local function js_test_command(runner, file, name, report)
  local f = vim.fn.shellescape(file)
  if runner == 'jest' then
    return ('npx jest %s %s --json --outputFile=%s'):format(f, name and ('-t ' .. vim.fn.shellescape(name)) or '', report)
  elseif runner == 'vitest' then
    return ('npx vitest run %s %s --reporter=default --reporter=junit --outputFile.junit=%s'):format(
      f,
      name and ('-t ' .. vim.fn.shellescape(name)) or '',
      report
    )
  end
  local pattern = name and ('--test-name-pattern=' .. vim.fn.shellescape('^' .. vim.fn.escape(name, '^$.*+?()[]{}|\\') .. '$')) or ''
  return ('node --test %s --test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=%s %s'):format(
    pattern,
    report,
    f
  )
end

local function js_test_debug_config(runner, dir, file, name)
  local config = { type = 'pwa-node', request = 'launch', name = 'Debug test', cwd = dir, console = 'integratedTerminal' }
  if runner == 'jest' then
    config.program = vim.fs.joinpath(dir, 'node_modules', 'jest', 'bin', 'jest.js')
    config.args = { '--runInBand', file, name and '-t' or nil, name }
  elseif runner == 'vitest' then
    config.program = vim.fs.joinpath(dir, 'node_modules', 'vitest', 'vitest.mjs')
    config.args = { 'run', file, '--no-file-parallelism', name and '-t' or nil, name }
  else
    config.runtimeArgs = { '--test', name and ('--test-name-pattern=^' .. vim.fn.escape(name, '^$.*+?()[]{}|\\') .. '$') or nil }
    config.program = file
  end
  return config
end

local function js_items(callback)
  local items = {}
  local path = vim.fn.expand '%:p'
  local name = vim.fn.expand '%:t'
  local dir = root { 'package.json', '.git' }
  local pkg = read_package_json(dir)
  local runner = test_runner(pkg)

  local function run_tests(test)
    return function()
      local report = vim.fn.tempname() .. (runner == 'jest' and '.json' or '.xml')
      M.run_in_console(js_test_command(runner, path, test, report), dir, function()
        show_js_results(path, runner, report)
      end)
    end
  end
  local function debug_tests(test)
    return function()
      require('dap').run(js_test_debug_config(runner, dir, path, test))
    end
  end

  local is_test = name:match '%.test%.[jt]sx?$' or name:match '%.spec%.[jt]sx?$' or path:match '/__tests__/'
  if is_test then
    local test = enclosing_js_test()
    if test then
      table.insert(items, { label = RUN .. name .. '::' .. test, run = at_cursor(run_tests(test)) })
      table.insert(items, { label = DEBUG .. name .. '::' .. test, run = at_cursor(debug_tests(test)) })
    end
    table.insert(items, { label = RUN .. name .. ' (all tests)', run = run_tests(nil) })
    table.insert(items, { label = DEBUG .. name .. ' (all tests)', run = debug_tests(nil) })
  end
  if vim.bo.filetype ~= 'json' then
    table.insert(items, { label = RUN .. name, run = task('node ' .. vim.fn.shellescape(path), dir) })
    table.insert(items, {
      label = DEBUG .. name,
      run = at_cursor(function()
        local dap = require 'dap'
        dap.run(dap.configurations[vim.bo.filetype:gsub('react$', '')][1])
      end),
    })
  end
  -- npm scripts from package.json, like IDEA's npm tool window
  local scripts = vim.tbl_keys(pkg.scripts or {})
  table.sort(scripts)
  for _, script in ipairs(scripts) do
    table.insert(items, { label = TASK .. 'npm run ' .. script, run = task('npm run ' .. script, dir) })
  end
  callback(items)
end

local function json_items(callback)
  if vim.fn.expand '%:t' == 'package.json' then
    return js_items(callback)
  end
  callback {}
end

local providers = {
  java = java_items,
  python = python_items,
  c = c_items,
  cpp = c_items,
  javascript = js_items,
  typescript = js_items,
  javascriptreact = js_items,
  typescriptreact = js_items,
  json = json_items,
}

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
