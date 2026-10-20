-- Test Runner tool window like IDEA's, for Java tests run by jdtls (JUnit 4/5/6, no Maven):
-- a method, a class (F10, <leader>xt / xT) or a scope: <leader>xA / :RunTests (project),
-- :RunTests package, Ctrl+Shift+F10 on a directory in the project tree (:DebugTests to debug).
-- the tree of the run on the left (class → tests, ✓ / ✗ / ◌ live as they run, times),
-- details of the selected test on the right (expected / actual, stack trace; the process
-- output on the root).
--   Enter / F4   go to the test (a failed one: to the line where it failed; on a trace line:
--                to that frame)
--   r / f        rerun all / only the failed tests          p   show / hide passed tests
--   q            close                                      Alt+4 shows it again
-- In the test file: ✓ / ✗ after each test method and the failure as a diagnostic.
-- It replaces the result handling of nvim-jdtls (jdtls.junit), which only printed to the REPL
-- and broke on a class that failed before its tests (e.g. a Dropwizard app not starting).

local M = {}

local ICON = { pending = '○', running = '◌', passed = '✓', failed = '✗', ignored = '⊘' }
local HL = { pending = 'Comment', running = 'DiagnosticInfo', passed = 'DiagnosticOk', failed = 'DiagnosticError', ignored = 'Comment' }
local marks_ns = vim.api.nvim_create_namespace 'pc-test-marks'
local ui_ns = vim.api.nvim_create_namespace 'pc-test-runner'

---@class pc.TestNode
---@field id string
---@field name string        method(Class) or Class
---@field display string
---@field suite boolean
---@field parent? string
---@field children string[]
---@field status string
---@field started? number
---@field ms? number
---@field trace string[]
---@field expected? string
---@field actual? string

local run -- the current / last run
local ui = {} -- tree / details windows and buffers
local hide_passed = false
local last = {} -- what to rerun: { lens, bufnr, debug }
local continuing -- the next run adds to the current tree (rerun of failed tests): its queue
local scope -- the next run is a scope (project / package / directory): { title, queue }

-- "id,name,isSuite,…" with "\," inside values
local function split_fields(s)
  local fields, cur, i = {}, {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == '\\' and s:sub(i + 1, i + 1) == ',' then
      table.insert(cur, ',')
      i = i + 1
    elseif c == ',' then
      table.insert(fields, table.concat(cur))
      cur = {}
    else
      table.insert(cur, c)
    end
    i = i + 1
  end
  table.insert(fields, table.concat(cur))
  return fields
end

-- adds(pl.t.CalcTest) → 'adds', 'pl.t.CalcTest'; pl.t.CalcTest → nil, 'pl.t.CalcTest'
local function split_name(name)
  local method, class = name:match '^(.-)%((.*)%)$'
  if method then
    return method, class
  end
  return nil, name
end

local function node(id)
  return run and run.nodes[id]
end

local function status_of(n)
  if not n.suite or n.status == 'failed' then
    return n.status
  end
  local any, all_done, failed, running = false, true, false, false
  for _, cid in ipairs(n.children) do
    local s = status_of(run.nodes[cid])
    any = true
    failed = failed or s == 'failed'
    running = running or s == 'running'
    all_done = all_done and (s == 'passed' or s == 'failed' or s == 'ignored')
  end
  if failed then
    return 'failed'
  elseif running or (any and not all_done and n.status == 'running') then
    return 'running'
  elseif any and all_done then
    return 'passed'
  end
  return n.status
end

local function counts()
  local c = { passed = 0, failed = 0, ignored = 0, total = 0 }
  for _, n in pairs(run.nodes) do
    if not n.suite then
      c.total = c.total + 1
      c[n.status] = (c[n.status] or 0) + 1
    end
  end
  return c
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function selected()
  if not (valid(ui.tree) and run) then
    return nil
  end
  return ui.rows and ui.rows[vim.api.nvim_win_get_cursor(ui.tree)[1]]
end

local function render_details()
  if not (ui.dbuf and vim.api.nvim_buf_is_valid(ui.dbuf)) or not run then
    return
  end
  local n = selected()
  local lines, hls = {}, {}
  if not n or n == 'root' then
    local c = counts()
    table.insert(lines, ('%s  %d passed, %d failed%s%s'):format(run.title, c.passed, c.failed, c.ignored > 0 and (', ' .. c.ignored .. ' skipped') or '', run.runtime and ('  ·  ' .. run.runtime .. ' ms') or ''))
    table.insert(hls, { 0, 'Title' })
    table.insert(lines, '')
    vim.list_extend(lines, #run.output > 0 and run.output or { '(no output)' })
  else
    local s = status_of(n)
    table.insert(lines, ('%s %s%s'):format(ICON[s], n.display, n.ms and ('  ' .. n.ms .. ' ms') or ''))
    table.insert(hls, { 0, HL[s] })
    if n.expected or n.actual then
      table.insert(lines, '')
      table.insert(lines, 'Expected: ' .. (n.expected or ''):gsub('\n', '⏎'))
      table.insert(lines, 'Actual:   ' .. (n.actual or ''):gsub('\n', '⏎'))
      table.insert(hls, { #lines - 2, 'DiagnosticOk' })
      table.insert(hls, { #lines - 1, 'DiagnosticError' })
    end
    if #n.trace > 0 then
      table.insert(lines, '')
      for _, l in ipairs(n.trace) do
        table.insert(lines, (l:gsub('\t', '    ')))
        if l:match '^%s*at ' and not l:match 'at org%.junit' and not l:match 'at java%.base' then
          table.insert(hls, { #lines - 1, 'Underlined' })
        end
      end
    elseif s == 'passed' then
      table.insert(lines, '')
      table.insert(lines, 'Test passed')
    end
  end
  vim.bo[ui.dbuf].modifiable = true
  vim.api.nvim_buf_set_lines(ui.dbuf, 0, -1, false, lines)
  vim.bo[ui.dbuf].modifiable = false
  vim.api.nvim_buf_clear_namespace(ui.dbuf, ui_ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.hl.range(ui.dbuf, ui_ns, h[2], { h[1], 0 }, { h[1], -1 })
  end
end

local function render()
  if not (ui.tbuf and vim.api.nvim_buf_is_valid(ui.tbuf)) or not run then
    return
  end
  local lines, hls = {}, {}
  ui.rows = {}
  local c = counts()
  local root_status = run.finished and (c.failed > 0 and 'failed' or 'passed') or 'running'
  local head = ('%s %s'):format(ICON[root_status], run.title)
  local info = run.finished and ('%d/%d passed%s'):format(c.passed, c.total, run.runtime and ('  ' .. run.runtime .. ' ms') or '') or ('%d/%s'):format(c.passed + c.failed + c.ignored, run.total or '?')
  table.insert(lines, head .. '  ' .. info)
  table.insert(hls, { 0, 0, #ICON[root_status] + 1, HL[root_status] })
  ui.rows[1] = 'root'
  local function add(id, depth)
    local n = run.nodes[id]
    local s = status_of(n)
    if hide_passed and s == 'passed' then
      return
    end
    local icon = ICON[s] or ICON.pending
    local line = string.rep('  ', depth) .. icon .. ' ' .. n.display
    if n.ms then
      line = line .. '  ' .. n.ms .. ' ms'
    end
    table.insert(lines, line)
    ui.rows[#lines] = n
    local col = #string.rep('  ', depth)
    table.insert(hls, { #lines - 1, col, col + #icon, HL[s] or 'Comment' })
    if n.ms then
      table.insert(hls, { #lines - 1, #line - #(n.ms .. ' ms'), #line, 'Comment' })
    end
    for _, cid in ipairs(n.children) do
      add(cid, depth + 1)
    end
  end
  for _, id in ipairs(run.roots) do
    add(id, 1)
  end
  vim.bo[ui.tbuf].modifiable = true
  vim.api.nvim_buf_set_lines(ui.tbuf, 0, -1, false, lines)
  vim.bo[ui.tbuf].modifiable = false
  vim.api.nvim_buf_clear_namespace(ui.tbuf, ui_ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(ui.tbuf, ui_ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end
  render_details()
end

-- Test class file of a fully qualified name (inner classes → their outer file)
local files = {}
local function class_file(fq)
  fq = fq:gsub('%$.*', '')
  if files[fq] and vim.uv.fs_stat(files[fq]) then
    return files[fq]
  end
  local rel = fq:gsub('%.', '/') .. '.java'
  local root = run and run.root or vim.fn.getcwd()
  local found = vim.fs.find(function(name, path)
    return name == vim.fs.basename(rel) and (path .. '/' .. name):sub(-#rel) == rel
  end, { path = root, limit = 1, type = 'file' })
  files[fq] = found[1]
  return found[1]
end

local function open_in_editor(file, lnum)
  -- the editor window above the runner
  vim.cmd 'wincmd k'
  if vim.bo.buftype ~= '' then
    vim.cmd 'wincmd p'
  end
  vim.cmd.edit(vim.fn.fnameescape(file))
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
    vim.cmd 'normal! ^zz'
  end
end

-- Line of `method` in a Java file
local function method_line(file, method)
  local lines = vim.fn.readfile(file)
  for i, l in ipairs(lines) do
    if l:match('[%s]' .. vim.pesc(method) .. '%s*%(') and not l:match '^%s*//' and not l:match '[;=]%s*$' then
      return i
    end
  end
end

local function goto_node(n)
  if not n or n == 'root' then
    return
  end
  local method, class = split_name(n.name)
  -- a failure: the frame of the test class
  for _, l in ipairs(n.trace) do
    local f_class, f_file, f_line = l:match('at (' .. vim.pesc(class) .. '[%w_.$]*)%.[%w_$<>]+%(([%w_]+%.java):(%d+)%)')
    if f_class and f_file then
      local file = class_file(class)
      if file then
        return open_in_editor(file, tonumber(f_line))
      end
    end
  end
  local file = class_file(class)
  if file then
    open_in_editor(file, method and method_line(file, method) or nil)
  end
end

local function goto_trace_line()
  local line = vim.api.nvim_get_current_line()
  local fq, file, lnum = line:match 'at ([%w_.$]+)%.[%w_$<>]+%(([%w_]+%.java):(%d+)%)'
  if fq then
    local path = class_file(fq)
    if path then
      return open_in_editor(path, tonumber(lnum))
    end
  end
  goto_node(selected())
end

local function open_window()
  if valid(ui.tree) then
    return
  end
  local from = vim.api.nvim_get_current_win()
  if not (ui.tbuf and vim.api.nvim_buf_is_valid(ui.tbuf)) then
    ui.tbuf = vim.api.nvim_create_buf(false, true)
    vim.bo[ui.tbuf].filetype = 'pctestrunner'
    vim.bo[ui.tbuf].bufhidden = 'hide'
    pcall(vim.api.nvim_buf_set_name, ui.tbuf, 'Tests')
    ui.dbuf = vim.api.nvim_create_buf(false, true)
    pcall(vim.api.nvim_buf_set_name, ui.dbuf, 'Test details')
    vim.bo[ui.dbuf].filetype = 'pctestdetails'
    vim.bo[ui.dbuf].bufhidden = 'hide'
    local function map(buf, lhs, fn, desc)
      vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = desc })
    end
    for _, buf in ipairs { ui.tbuf, ui.dbuf } do
      map(buf, 'q', M.close, 'Close')
      map(buf, 'r', M.rerun, 'Rerun')
      map(buf, 'f', M.rerun_failed, 'Rerun failed tests')
      map(buf, 'p', function()
        hide_passed = not hide_passed
        render()
      end, 'Show / hide passed tests')
    end
    for _, lhs in ipairs { '<CR>', '<F4>', '<2-LeftMouse>' } do
      map(ui.tbuf, lhs, function()
        goto_node(selected())
      end, 'Go to the test')
      map(ui.dbuf, lhs, goto_trace_line, 'Go to this frame')
    end
    vim.api.nvim_create_autocmd('CursorMoved', { buffer = ui.tbuf, callback = render_details })
  end
  vim.cmd 'botright 14split'
  ui.tree = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(ui.tree, ui.tbuf)
  vim.cmd 'rightbelow vsplit'
  ui.details = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(ui.details, ui.dbuf)
  vim.api.nvim_win_set_width(ui.tree, math.floor(vim.o.columns * 0.4))
  for _, win in ipairs { ui.tree, ui.details } do
    for opt, value in pairs { number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0', list = false, winfixheight = true, wrap = false, cursorline = win == ui.tree } do
      vim.wo[win][opt] = value
    end
  end
  vim.wo[ui.tree].winbar = '%#Title# Tests %*%#Comment# Enter go to · r rerun · f failed · p passed · q close'
  vim.wo[ui.details].winbar = '%#Comment# Enter on a frame: go to it'
  render()
  if valid(from) then
    vim.api.nvim_set_current_win(from)
  end
end

function M.close()
  for _, win in ipairs { ui.details, ui.tree } do
    if valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  ui.tree, ui.details = nil, nil
end

function M.visible()
  return valid(ui.tree)
end

--- Alt+4 after a test run: the runner window
function M.toggle()
  if M.visible() then
    return M.close()
  end
  if run then
    open_window()
  end
end

function M.has_run()
  return run ~= nil
end

---------------------------------------------------------------------------
-- Results in the test file
---------------------------------------------------------------------------

local function mark_source()
  local by_file = {}
  for _, n in pairs(run.nodes) do
    local method, class = split_name(n.name)
    if method then
      local file = class_file(class)
      if file then
        by_file[file] = by_file[file] or {}
        local s = status_of(n)
        local prev = by_file[file][method]
        if not prev or s == 'failed' then
          by_file[file][method] = { status = s, node = n }
        end
      end
    end
  end
  local diags_ns = marks_ns
  for file, methods in pairs(by_file) do
    local buf = vim.fn.bufnr(file)
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_clear_namespace(buf, marks_ns, 0, -1)
      local diags = {}
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for method, r in pairs(methods) do
        for i, l in ipairs(lines) do
          if l:match('[%s]' .. vim.pesc(method) .. '%s*%(') and not l:match '[;=]%s*$' then
            vim.api.nvim_buf_set_extmark(buf, marks_ns, i - 1, 0, { virt_text = { { ' ' .. ICON[r.status], HL[r.status] } }, invalidate = true })
            break
          end
        end
        if r.status == 'failed' then
          for _, t in ipairs(r.node.trace) do
            local lnum = t:match('%(' .. vim.pesc(vim.fs.basename(file)) .. ':(%d+)%)')
            if lnum then
              table.insert(diags, { lnum = tonumber(lnum) - 1, col = 0, severity = vim.diagnostic.severity.ERROR, source = 'tests', message = r.node.trace[1] or 'failed' })
              break
            end
          end
        end
      end
      vim.diagnostic.set(diags_ns, buf, diags, {})
    end
  end
end

---------------------------------------------------------------------------
-- Protocol of the Eclipse JUnit runner (what jdtls launches)
---------------------------------------------------------------------------

local function handle(line)
  local cur = run.current
  if run.capture then
    if line:match '^%%EXPECTE' or line:match '^%%ACTUALE' then
      run.capture = nil
    elseif cur then
      local key = run.capture
      cur[key] = cur[key] and (cur[key] .. '\n' .. line) or line
    end
    return
  end
  if run.tracing then
    if line:match '^%%TRACEE' then
      run.tracing = false
    elseif cur then
      table.insert(cur.trace, line)
    end
    return
  end
  local tag, rest = line:match '^%%(%u+)%s*(.*)$'
  if not tag then
    return
  end
  if tag == 'TESTC' then
    run.total = tonumber(rest:match '^(%d+)')
  elseif tag == 'TSTTREE' then
    local f = split_fields(rest)
    local id, name, suite, display = f[1], f[2], f[3] == 'true', f[7]
    local parent = run.idmap[f[6]]
    display = display ~= '' and display or name
    -- a test already in the tree (rerun of failed tests) is reused
    local key = (parent or '') .. '|' .. name .. '|' .. display
    local existing = run.by_key[key]
    if existing then
      run.idmap[id] = existing
      local n = run.nodes[existing]
      n.status, n.trace, n.ms, n.started, n.expected, n.actual = 'pending', {}, nil, nil, nil, nil
    else
      local uid = run.seq .. ':' .. id
      run.idmap[id], run.by_key[key] = uid, uid
      run.nodes[uid] = { id = uid, name = name, display = display, suite = suite, parent = parent, children = {}, status = 'pending', trace = {} }
      local p = parent and run.nodes[parent]
      if p then
        table.insert(p.children, uid)
      else
        table.insert(run.roots, uid)
      end
    end
  elseif tag == 'TESTS' then
    local id, name = rest:match '^(%d+),(.*)$'
    local n = id and run.nodes[run.idmap[id] or '']
    if n then
      if name:match '^@Ignore: ' or name:match '^@AssumptionFailure: ' then
        n.status = 'ignored'
      else
        n.status, n.started = 'running', vim.uv.hrtime()
      end
      run.current = n
    end
  elseif tag == 'TESTE' then
    local id = rest:match '^(%d+),'
    local n = id and run.nodes[run.idmap[id] or '']
    if n then
      if n.status == 'running' then
        n.status = 'passed'
      end
      if n.started then
        n.ms = math.floor((vim.uv.hrtime() - n.started) / 1e6)
      end
    end
  elseif tag == 'FAILED' or tag == 'ERROR' then
    local id, name = rest:match '^(%d+),(.*)$'
    local n = id and run.nodes[run.idmap[id] or '']
    if not n then
      -- a failure outside the known tests (class setup): its own entry
      id = run.seq .. ':' .. (id or ('error' .. (#run.roots + 1)))
      n = { id = id, name = name or 'error', display = (name or 'error'):gsub('^.*%.', ''), suite = false, children = {}, status = 'failed', trace = {} }
      run.nodes[id] = n
      table.insert(run.roots, id)
    end
    n.status = 'failed'
    run.current = n
  elseif tag == 'EXPECTS' then
    run.capture = 'expected'
  elseif tag == 'ACTUALS' then
    run.capture = 'actual'
  elseif tag == 'TRACES' then
    run.tracing = true
  elseif tag == 'RUNTIME' then
    run.runtime = tonumber(rest:match '^(%d+)')
  end
end

---------------------------------------------------------------------------
-- nvim-jdtls hook
---------------------------------------------------------------------------

local function start(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  require('pc.run').note_test_run()
  if continuing and run then
    run.queue, continuing = continuing, nil
    run.finished, run.runtime, run.seq = false, nil, run.seq + 1
    run.idmap = {}
    vim.schedule(function()
      open_window()
      render()
    end)
    return
  end
  continuing = nil
  local s = scope
  scope = nil
  run = {
    seq = 1,
    idmap = {},
    by_key = {},
    custom = s ~= nil,
    queue = s and s.queue,
    title = s and s.title or vim.fn.fnamemodify(file, ':t:r'),
    root = vim.fs.root(bufnr, { 'pom.xml', 'build.gradle', 'build.gradle.kts', '.git' }),
    bufnr = bufnr,
    nodes = {},
    roots = {},
    output = {},
  }
  vim.schedule(function()
    open_window()
    render()
  end)
end

-- the replacement of jdtls.junit.mk_test_results
local function mk_test_results(bufnr)
  start(bufnr)
  local pending = ''
  local redraw_scheduled = false
  local function feed(chunk)
    pending = pending .. chunk
    while true do
      local nl = pending:find '\n'
      if not nl then
        break
      end
      handle((pending:sub(1, nl - 1):gsub('\r$', '')))
      pending = pending:sub(nl + 1)
    end
    if not redraw_scheduled then
      redraw_scheduled = true
      vim.defer_fn(function()
        redraw_scheduled = false
        render()
      end, 50)
    end
  end
  return {
    mk_reader = function(sock)
      return vim.schedule_wrap(function(err, chunk)
        if err then
          return
        end
        if chunk then
          feed(chunk)
        else
          sock:close()
          if pending ~= '' then
            handle(pending)
            pending = ''
          end
        end
      end)
    end,
    show = function(lens)
      run.finished = true
      -- tests of a class that failed before them (@BeforeAll, an extension starting the app)
      -- failed with the class' error, as in IDEA
      local function inherit(n, trace)
        for _, cid in ipairs(n.children) do
          local child = run.nodes[cid]
          if child.status == 'pending' or child.status == 'running' then
            child.status, child.trace = 'failed', vim.deepcopy(trace)
          end
          inherit(child, trace)
        end
      end
      for _, n in pairs(run.nodes) do
        if n.suite and n.status == 'failed' and #n.trace > 0 then
          inherit(n, n.trace)
        end
      end
      last.bufnr = bufnr
      if not run.rerunning and not run.custom then
        last.lens = lens
        last.rerun = function()
          M.run_lens(lens, last.debug)
        end
      end
      -- tests that never started (the run was stopped) stay pending
      local items, tests = {}, {}
      for _, n in pairs(run.nodes) do
        if not n.suite then
          local method, class = split_name(n.name)
          table.insert(tests, { fq_class = class, method = method, failed = n.status == 'failed', traces = n.trace })
          local file = n.status == 'failed' and class and class_file(class)
          if file then
            local lnum
            for _, t in ipairs(n.trace) do
              lnum = lnum or t:match('%(' .. vim.pesc(vim.fs.basename(file)) .. ':(%d+)%)')
            end
            table.insert(items, { filename = file, lnum = tonumber(lnum) or method and method_line(file, method) or 1, text = n.display .. ' ' .. (n.trace[1] or '') })
          end
        end
      end
      if #items > 0 then
        vim.fn.setqflist({}, 'r', { title = 'Tests: ' .. run.title, items = items })
      end
      mark_source()
      render()
      local c = counts()
      vim.notify(('%s: %d passed, %d failed'):format(run.title, c.passed, c.failed), c.failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO, { title = 'Tests' })
      -- the next class / package of a rerun of failed tests or of a scope
      if run.queue and #run.queue > 0 then
        local next_item = table.remove(run.queue, 1)
        local queue = run.queue
        vim.schedule(function()
          if next_item.group then
            M.run_group(next_item.group, last.debug, queue)
          else
            M.run_lens(next_item, last.debug, queue)
          end
        end)
      else
        run.rerunning = nil
      end
      return items, tests
    end,
  }
end

--- Runs a jdtls test lens (class or method) of the last test buffer
function M.run_lens(lens, debug, queue)
  local jdtls_dap = require('jdtls.dap').experimental
  local bufnr = last.bufnr
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return vim.notify('Tests: the test file is not open any more', vim.log.levels.WARN)
  end
  local context = jdtls_dap.make_context(bufnr)
  jdtls_dap.fetch_launch_args(lens, context, function(launch_args)
    local config = jdtls_dap.make_config(lens, launch_args, debug and {} or { noDebug = true })
    if queue then
      continuing = queue
      if run then
        run.rerunning = true
      end
    end
    jdtls_dap.run(lens, config, context, {})
  end)
end

function M.rerun()
  if not last.rerun then
    return vim.notify('Tests: nothing to rerun yet', vim.log.levels.INFO)
  end
  last.rerun()
end

function M.rerun_failed()
  if not (run and last.rerun) then
    return vim.notify('Tests: nothing to rerun yet', vim.log.levels.INFO)
  end
  if run.custom then
    -- a scope run: the classes with failures
    local classes, lenses = {}, {}
    for _, n in pairs(run.nodes) do
      local _, class = split_name(n.name)
      if not n.suite and n.status == 'failed' then
        classes[class] = true
      end
    end
    for _, lens in ipairs(last.classes or {}) do
      if classes[lens.fullName] then
        table.insert(lenses, lens)
      end
    end
    if #lenses == 0 then
      return vim.notify('Tests: no failed tests', vim.log.levels.INFO)
    end
    return M.run_group(lenses, last.debug, {})
  end
  local failed = {}
  for _, n in pairs(run.nodes) do
    local method = split_name(n.name)
    if not n.suite and n.status == 'failed' and method then
      failed[method] = true
    end
  end
  local lenses = {}
  for _, child in ipairs(last.lens and last.lens.children or {}) do
    local name = (child.fullName or ''):match '#([^(]+)'
    if name and failed[name] then
      table.insert(lenses, child)
    end
  end
  if #lenses == 0 then
    -- a single test method run, or failures outside methods: the same run again
    if next(failed) or counts().failed > 0 then
      return M.rerun()
    end
    return vim.notify('Tests: no failed tests', vim.log.levels.INFO)
  end
  local first = table.remove(lenses, 1)
  M.run_lens(first, last.debug, lenses)
end

---------------------------------------------------------------------------
-- Scopes: all tests of the project, a package, a directory (IDEA's Run 'All Tests')
---------------------------------------------------------------------------

local function jdtls_client(bufnr)
  return vim.lsp.get_clients({ name = 'jdtls', bufnr = bufnr })[1] or vim.lsp.get_clients({ name = 'jdtls' })[1]
end

local function command(client, name, args, callback)
  client:request('workspace/executeCommand', { command = name, arguments = args }, function(err, result)
    vim.schedule(function()
      if err then
        return vim.notify('Tests: ' .. (err.message or tostring(err)), vim.log.levels.ERROR)
      end
      callback(result or {})
    end)
  end)
end

-- a loaded Java buffer of the project (the run's context: diagnostics, marks)
local function java_buffer(path)
  local cur = vim.api.nvim_get_current_buf()
  if vim.bo[cur].filetype == 'java' then
    return cur
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == 'java' and vim.startswith(vim.api.nvim_buf_get_name(b), path) then
      return b
    end
  end
end

--- Runs the tests of `what`: 'project', 'package' (of the current file) or a directory path
function M.run_tests(what, debug)
  local path = what ~= 'project' and what ~= 'package' and vim.fs.normalize(what) or vim.api.nvim_buf_get_name(0)
  local bufnr = java_buffer(vim.fs.root(path, { 'pom.xml', 'build.gradle', 'build.gradle.kts', '.git' }) or path)
  local client = jdtls_client(bufnr)
  if not (bufnr and client) then
    return vim.notify('Tests: open a Java file of the project first (jdtls)', vim.log.levels.WARN)
  end
  command(client, 'vscode.java.test.findJavaProjects', { vim.uri_from_fname(vim.fn.getcwd()) }, function(projects)
    -- the project the path is in (the deepest one, for multi-module builds)
    local project
    for _, p in ipairs(projects) do
      local dir = vim.uri_to_fname(p.uri)
      if (path == dir or vim.startswith(path, dir .. '/')) and (not project or #dir > #vim.uri_to_fname(project.uri)) then
        project = p
      end
    end
    project = project or (#projects == 1 and projects[1])
    if not project then
      return vim.notify('Tests: no Java project for ' .. vim.fn.fnamemodify(path, ':~:.'), vim.log.levels.WARN)
    end
    command(client, 'vscode.java.test.findTestPackagesAndTypes', { project.jdtHandler }, function(packages)
      local classes = {}
      for _, pkg in ipairs(packages) do
        vim.list_extend(classes, pkg.children or {})
      end
      if #classes == 0 then
        return vim.notify('Tests: no tests in ' .. project.label, vim.log.levels.INFO)
      end
      local title, picked
      if what == 'project' then
        title, picked = 'All tests in ' .. project.label, classes
      else
        local dir = what == 'package' and vim.fs.dirname(path) or path
        picked = vim.tbl_filter(function(c)
          local cdir = vim.fs.dirname(vim.uri_to_fname(c.uri))
          return cdir == dir or (what ~= 'package' and vim.startswith(cdir, dir .. '/'))
        end, classes)
        if #picked == 0 then
          return vim.notify('Tests: no tests in ' .. vim.fn.fnamemodify(dir, ':~:.'), vim.log.levels.INFO)
        end
        local rel = vim.fs.relpath(vim.uri_to_fname(project.uri), dir) or dir
        title = 'Tests in ' .. (rel:match 'src/%w+/java/(.*)' or rel):gsub('/', '.')
      end
      -- one run per test kind (JUnit 4 next to 5 / 6): the first now, the others queued
      local groups, order = {}, {}
      for _, c in ipairs(picked) do
        local key = c.projectName .. '/' .. tostring(c.testKind)
        if not groups[key] then
          groups[key] = {}
          table.insert(order, key)
        end
        table.insert(groups[key], c)
      end
      last.bufnr, last.classes, last.lens = bufnr, classes, nil
      last.rerun = function()
        M.run_tests(what, last.debug)
      end
      local queue = {}
      for i = 2, #order do
        table.insert(queue, { group = groups[order[i]] })
      end
      scope = { title = title, queue = queue }
      M.run_group(groups[order[1]], debug)
    end)
  end)
end

--- Runs test classes of one project and test kind in one JVM (what VS Code does for a folder)
function M.run_group(classes, debug, queue)
  local bufnr = last.bufnr
  local client = jdtls_client(bufnr)
  if not (client and bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return vim.notify('Tests: jdtls is not running', vim.log.levels.WARN)
  end
  local first = classes[1]
  local request = {
    projectName = first.projectName,
    testLevel = 5,
    testKind = first.testKind,
    testNames = vim.tbl_map(function(c)
      return c.fullName
    end, classes),
  }
  command(client, 'vscode.java.test.junit.argument', { vim.fn.json_encode(request) }, function(args)
    args = args.body or args
    if args.errorMessage then
      return vim.notify('Tests: ' .. args.errorMessage, vim.log.levels.WARN)
    end
    -- the test classpath too, as nvim-jdtls does (the launch arguments can miss classes)
    command(client, 'java.project.getClasspaths', { vim.uri_from_bufnr(bufnr), vim.fn.json_encode { scope = 'test' } }, function(resp)
      local seen = {}
      for _, p in ipairs(args.classpath or {}) do
        seen[p] = true
      end
      for _, p in ipairs(resp.classpaths or {}) do
        if not seen[p] then
          table.insert(args.classpath, p)
          seen[p] = true
        end
      end
      local jdtls_dap = require('jdtls.dap').experimental
      local lens = { fullName = #classes == 1 and first.fullName or (first.projectName .. ' tests'), testKind = first.testKind, testLevel = 5, projectName = first.projectName }
      local config = jdtls_dap.make_config(lens, args, debug and {} or { noDebug = true })
      if queue then
        continuing = queue
        if run then
          run.rerunning = true
        end
      end
      jdtls_dap.run(lens, config, jdtls_dap.make_context(bufnr), {})
    end)
  end)
end

function M.setup()
  require('jdtls.junit').mk_test_results = mk_test_results
  local dap = require 'dap'
  -- Run / Debug mode of the last test run (for rerun), output of the test process
  dap.listeners.on_config['pc-test-runner'] = function(config)
    if (config.mainClass or ''):lower():match 'junit' or (config.mainClass or ''):match 'RemoteTestRunner' then
      last.debug = not config.noDebug
    end
    return config
  end
  dap.listeners.after.event_output['pc-test-runner'] = function(session, body)
    local main = session.config and session.config.mainClass or ''
    if run and not run.finished and (main:lower():match 'junit' or main:match 'RemoteTestRunner') and body.category ~= 'telemetry' then
      for _, l in ipairs(vim.split((body.output or ''):gsub('\n$', ''), '\n')) do
        table.insert(run.output, l)
      end
    end
  end
end

vim.keymap.set('n', '<leader>xA', function()
  M.run_tests 'project'
end, { desc = 'Run all tests of the project' })
vim.api.nvim_create_user_command('RunTests', function(o)
  M.run_tests(o.args ~= '' and o.args or 'project')
end, { nargs = '?', complete = function()
  return { 'project', 'package' }
end, desc = 'Run tests: project (default), package or a directory' })
vim.api.nvim_create_user_command('DebugTests', function(o)
  M.run_tests(o.args ~= '' and o.args or 'project', true)
end, { nargs = '?', complete = function()
  return { 'project', 'package' }
end, desc = 'Debug tests: project (default), package or a directory' })

--- Is this dap session a test run (the runner window replaces the console)?
function M.is_test_session(session)
  local main = session and session.config and session.config.mainClass or ''
  return main:lower():match 'junit' ~= nil or main:match 'RemoteTestRunner' ~= nil
end

return M
