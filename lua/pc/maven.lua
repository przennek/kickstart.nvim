-- Maven tool window like IDEA's:
--   <leader>MM   toggle the Maven window (right side) of the module of the current file:
--                Profiles (Enter toggles), Lifecycle and Plugins goals (Enter runs in the Run window),
--                o offline, s skip tests, r reimport, u update folders, g execute goal…, R refresh, q close
--   <leader>Mr   Reimport (jdtls reloads pom.xml of all projects)
--   <leader>Mu   Update folders: mvn generate-sources, then reimport
--   <leader>Mg   Execute Maven goal… (like Ctrl Ctrl in IDEA), with the same profiles / offline / skip tests
--   <leader>Ms   Maven settings of this project (S in the window), like IDEA's Build Tools → Maven:
--                Maven executable, settings.xml, local repository, JDK, threads, extra options and
--                the default offline / skip tests / profiles
-- Plugin goals come from the effective POM and the plugins' descriptors in ~/.m2, loaded in the
-- background the first time the window opens for a module.

local M = {}

local LIFECYCLE = { 'clean', 'validate', 'compile', 'test', 'package', 'verify', 'install', 'site', 'deploy' }

-- Per root pom: chosen profiles; offline / skip tests are global like IDEA's toolbar toggles
local state = { profiles = {}, offline = false, skip_tests = false, defaults = {} }
local plugin_cache = {} -- module pom path → { mtime, plugins = { { prefix, goals } } }
local win = { win = nil, buf = nil, pom = nil }

local function read(file)
  local f = io.open(file, 'r')
  if not f then
    return ''
  end
  local text = f:read '*a'
  f:close()
  return text
end

-- Module pom (nearest) and project root (topmost pom.xml, or where mvnw is)
local function project(path)
  local start = path ~= '' and vim.fs.dirname(path) or vim.fn.getcwd()
  local module = vim.fs.find('pom.xml', { path = start, upward = true })[1]
  if not module then
    return nil
  end
  local root = vim.fs.dirname(module)
  for dir in vim.fs.parents(module) do
    if vim.uv.fs_stat(dir .. '/pom.xml') then
      root = dir
    end
    if vim.uv.fs_stat(dir .. '/mvnw') or vim.uv.fs_stat(dir .. '/.git') then
      break
    end
  end
  return { pom = module, root = root }
end

local function profiles_of(p)
  local ids, seen = {}, {}
  for _, pom in ipairs { p.root .. '/pom.xml', p.pom } do
    local section = read(pom):match '<profiles>(.-)</profiles>' or ''
    for id in section:gmatch '<profile>%s*<id>%s*([^<%s]+)%s*</id>' do
      if not seen[id] then
        seen[id] = true
        table.insert(ids, id)
      end
    end
  end
  return ids
end

---------------------------------------------------------------------------
-- Settings per project (.idea/nvim/maven.json)
---------------------------------------------------------------------------

local store = require 'pc.project_store'

local function settings(p)
  local values = store.get(p.root, 'maven', 'pc_maven.json')
  return type(values) == 'table' and values or {}
end

-- The executable and the options every Maven call of the project gets
local function base_command(p, absolute)
  local s = settings(p)
  local build = (s.executable or '') ~= '' and s.executable ~= 'Wrapper (mvnw) if present' and vim.fn.expand(s.executable) or nil
  if not build then
    local wrapper = vim.uv.fs_stat(p.root .. '/mvnw')
    build = wrapper and (absolute and p.root .. '/mvnw' or './mvnw') or 'mvn'
  end
  local args = { build }
  if (s.settings_file or '') ~= '' then
    vim.list_extend(args, { '-s', vim.fn.expand(s.settings_file) })
  end
  if (s.local_repo or '') ~= '' then
    table.insert(args, '-Dmaven.repo.local=' .. vim.fn.expand(s.local_repo))
  end
  if (s.threads or '') ~= '' then
    vim.list_extend(args, { '-T', s.threads })
  end
  vim.list_extend(args, vim.split(s.options or '', '%s+', { trimempty = true }))
  local env = (s.jdk or '') ~= '' and s.jdk ~= 'Default (JAVA_HOME)' and { JAVA_HOME = vim.fn.expand(s.jdk) } or nil
  return args, env
end

local function jdks()
  local list = { 'Default (JAVA_HOME)' }
  for _, dir in ipairs(vim.fn.glob(vim.env.HOME .. '/.sdkman/candidates/java/*', false, true)) do
    if not dir:match '/current$' then
      table.insert(list, dir)
    end
  end
  vim.list_extend(list, vim.fn.glob('/usr/lib/jvm/*', false, true))
  return list
end

local function command(p, goal)
  local args, env = base_command(p)
  if env then
    table.insert(args, 1, 'env JAVA_HOME=' .. vim.fn.shellescape(env.JAVA_HOME))
  end
  if p.pom ~= p.root .. '/pom.xml' then
    vim.list_extend(args, { '-f', vim.fs.relpath(p.root, p.pom) })
  end
  if state.offline then
    table.insert(args, '-o')
  end
  if state.skip_tests then
    table.insert(args, '-DskipTests')
  end
  local chosen = vim.tbl_filter(function(id)
    return vim.tbl_contains(profiles_of(p), id)
  end, state.profiles[p.root] or {})
  if #chosen > 0 then
    table.insert(args, '-P' .. table.concat(chosen, ','))
  end
  table.insert(args, goal)
  return table.concat(args, ' ')
end

local function run_goal(p, goal, on_exit)
  require('pc.run').run_in_console(command(p, goal), p.root, on_exit)
end

---------------------------------------------------------------------------
-- Plugins and their goals: effective POM + plugin.xml from the local repository
---------------------------------------------------------------------------

local function strip(block, tag)
  return (block:gsub('<' .. tag .. '>.-</' .. tag .. '>', ''))
end

local function plugin_goals(group, artifact, version)
  local repo = vim.env.HOME .. '/.m2/repository/'
  local jar = ('%s%s/%s/%s/%s-%s.jar'):format(repo, group:gsub('%.', '/'), artifact, version, artifact, version)
  if not vim.uv.fs_stat(jar) then
    return nil
  end
  local xml = vim.system({ 'unzip', '-p', jar, 'META-INF/maven/plugin.xml' }, { text = true }):wait().stdout or ''
  local prefix = xml:match '<goalPrefix>([^<]+)</goalPrefix>' or artifact:gsub('%-?maven%-?', ''):gsub('%-plugin$', '')
  local goals = {}
  for goal in (xml:match '<mojos>(.*)</mojos>' or ''):gmatch '<mojo>%s*<goal>([^<]+)</goal>' do
    if goal ~= 'help' then
      table.insert(goals, goal)
    end
  end
  return { prefix = prefix, goals = goals }
end

local function parse_plugins(xml)
  local build = strip(xml:match '<build>(.*)</build>' or '', 'pluginManagement')
  local plugins = {}
  for block in (build:match '<plugins>(.*)</plugins>' or ''):gmatch '<plugin>(.-)</plugin>' do
    for _, tag in ipairs { 'executions', 'dependencies', 'configuration' } do
      block = strip(block, tag)
    end
    local artifact, version = block:match '<artifactId>([^<]+)</artifactId>', block:match '<version>([^<]+)</version>'
    if artifact and version then
      local info = plugin_goals(block:match '<groupId>([^<]+)</groupId>' or 'org.apache.maven.plugins', artifact, version)
      if info and #info.goals > 0 then
        table.insert(plugins, info)
      end
    end
  end
  table.sort(plugins, function(a, b)
    return a.prefix < b.prefix
  end)
  return plugins
end

local function load_plugins(p, done)
  local mtime = (vim.uv.fs_stat(p.pom) or {}).mtime
  local cached = plugin_cache[p.pom]
  if cached and mtime and cached.mtime == mtime.sec then
    return done(cached.plugins)
  end
  local out = vim.fn.tempname()
  local cmd, env = base_command(p, true)
  vim.list_extend(cmd, { '-q', '-N', '-f', p.pom, 'help:effective-pom', '-Doutput=' .. out })
  vim.system(cmd, { text = true, env = env }, function(result)
    vim.schedule(function()
      local plugins = result.code == 0 and parse_plugins(read(out)) or nil
      os.remove(out)
      if plugins then
        plugin_cache[p.pom] = { mtime = mtime and mtime.sec, plugins = plugins }
      end
      done(plugins, result.code ~= 0 and vim.trim(result.stdout or ''):match '[^\n]*$' or nil)
    end)
  end)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function window_open()
  return win.win and vim.api.nvim_win_is_valid(win.win)
end

local actions = {} -- line → function

local function render(p, plugins, err)
  if not (win.buf and vim.api.nvim_buf_is_valid(win.buf)) then
    return
  end
  local lines, hl = {}, {}
  actions = {}
  local function add(text, group, action)
    table.insert(lines, text)
    if group then
      table.insert(hl, { #lines - 1, group })
    end
    actions[#lines] = action
  end
  local name = read(p.pom):gsub('<parent>.-</parent>', ''):match '<artifactId>([^<]+)</artifactId>' or 'project'
  add(' ' .. name, 'Title')
  add(('  offline %s  ·  skip tests %s'):format(state.offline and '●' or '○', state.skip_tests and '●' or '○'), 'Comment')
  local ids = profiles_of(p)
  if #ids > 0 then
    add('', nil)
    add('Profiles', 'Directory')
    local chosen = state.profiles[p.root] or {}
    for _, id in ipairs(ids) do
      add(('  [%s] %s'):format(vim.tbl_contains(chosen, id) and 'x' or ' ', id), nil, function()
        local list = state.profiles[p.root] or {}
        if vim.tbl_contains(list, id) then
          list = vim.tbl_filter(function(x)
            return x ~= id
          end, list)
        else
          table.insert(list, id)
        end
        state.profiles[p.root] = list
        M.refresh()
      end)
    end
  end
  add('', nil)
  add('Lifecycle', 'Directory')
  for _, goal in ipairs(LIFECYCLE) do
    add('  ⚙ ' .. goal, nil, function()
      run_goal(p, goal)
    end)
  end
  add('', nil)
  add('Plugins', 'Directory')
  if not plugins then
    add(err and ('  ' .. err) or '  loading…', err and 'DiagnosticError' or 'Comment')
  end
  for _, plugin in ipairs(plugins or {}) do
    add('  ' .. plugin.prefix, 'Function')
    for _, goal in ipairs(plugin.goals) do
      local full = plugin.prefix .. ':' .. goal
      add('    ⚙ ' .. full, nil, function()
        run_goal(p, full)
      end)
    end
  end
  add('', nil)
  add('Enter run/toggle · g goal… · r reimport · u update folders · o/s toggles · q close', 'Comment')
  vim.bo[win.buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines)
  vim.bo[win.buf].modifiable = false
  local ns = vim.api.nvim_create_namespace 'pc-maven'
  vim.api.nvim_buf_clear_namespace(win.buf, ns, 0, -1)
  for _, h in ipairs(hl) do
    vim.hl.range(win.buf, ns, h[2], { h[1], 0 }, { h[1], -1 })
  end
end

function M.refresh()
  if not win.pom then
    return
  end
  local p = win.project
  local cached = plugin_cache[p.pom]
  render(p, cached and cached.plugins)
  load_plugins(p, function(plugins, err)
    render(p, plugins, err)
  end)
end

-- A buffer jdtls is attached to, for reimport from anywhere
local function jdtls_buffer()
  local client = vim.lsp.get_clients({ name = 'jdtls' })[1]
  if not client then
    return nil
  end
  for buf in pairs(client.attached_buffers) do
    return buf
  end
end

function M.reimport()
  local buf = jdtls_buffer()
  if not buf then
    return vim.notify('Maven: reimport needs a Java file open (jdtls not running)', vim.log.levels.WARN)
  end
  vim.api.nvim_buf_call(buf, function()
    require('jdtls').update_projects_config { select_mode = 'all' }
  end)
  plugin_cache = {}
  vim.notify 'Maven: reimporting projects'
  if window_open() then
    M.refresh()
  end
end

local function current_project()
  if window_open() and vim.api.nvim_get_current_buf() == win.buf then
    return win.project
  end
  local p = project(vim.api.nvim_buf_get_name(0))
  if not p then
    vim.notify('Maven: no pom.xml here', vim.log.levels.WARN)
  end
  return p
end

function M.update_folders()
  local p = current_project()
  if p then
    run_goal(p, 'generate-sources generate-test-sources', function(code)
      if code == 0 then
        M.reimport()
      end
    end)
  end
end

function M.execute_goal()
  local p = current_project()
  if not p then
    return
  end
  vim.ui.input({ prompt = 'Maven goal: ', default = '', completion = 'customlist,v:lua.pc_maven_complete' }, function(goal)
    if goal and vim.trim(goal) ~= '' then
      run_goal(p, vim.trim(goal))
    end
  end)
end

function _G.pc_maven_complete(lead)
  local word = lead:match '%S*$'
  local candidates = vim.list_extend({}, LIFECYCLE)
  for _, c in pairs(plugin_cache) do
    for _, plugin in ipairs(c.plugins) do
      for _, goal in ipairs(plugin.goals) do
        table.insert(candidates, plugin.prefix .. ':' .. goal)
      end
    end
  end
  local before = lead:sub(1, #lead - #word)
  return vim.tbl_map(
    function(c)
      return before .. c
    end,
    vim.tbl_filter(function(c)
      return vim.startswith(c, word)
    end, candidates)
  )
end

function M.settings()
  local p = current_project()
  if not p then
    return
  end
  require('pc.form').open {
    title = 'Maven: ' .. vim.fs.basename(p.root),
    values = settings(p),
    fields = {
      { header = 'Build Tools → Maven' },
      { key = 'executable', label = 'Maven executable', choices = { 'Wrapper (mvnw) if present', 'mvn', '~/.sdkman/candidates/maven/current/bin/mvn' }, default = 'Wrapper (mvnw) if present' },
      { key = 'settings_file', label = 'User settings file', default = '', complete = 'file' },
      { key = 'local_repo', label = 'Local repository', default = '', complete = 'dir' },
      { key = 'jdk', label = 'JDK for Maven', choices = jdks(), default = 'Default (JAVA_HOME)' },
      { key = 'threads', label = 'Threads (-T)', default = '' },
      { key = 'options', label = 'Extra options', default = '' },
      { header = 'Defaults of the Maven window' },
      { key = 'offline', label = 'Work offline', check = true, default = false },
      { key = 'skip_tests', label = 'Skip tests', check = true, default = false },
      { key = 'profiles', label = 'Active profiles (a,b)', default = '' },
      { key = 'command', label = 'Command', readonly = true, value = function(v)
        -- the values in the form, not saved yet
        local exe = v.executable or ''
        local args = { exe:match '^Wrapper' and (vim.uv.fs_stat(p.root .. '/mvnw') and './mvnw' or 'mvn') or exe }
        if (v.settings_file or '') ~= '' then
          vim.list_extend(args, { '-s', v.settings_file })
        end
        if (v.local_repo or '') ~= '' then
          table.insert(args, '-Dmaven.repo.local=' .. v.local_repo)
        end
        if (v.threads or '') ~= '' then
          vim.list_extend(args, { '-T', v.threads })
        end
        if (v.options or '') ~= '' then
          table.insert(args, v.options)
        end
        return table.concat(args, ' ') .. ' <goal>'
      end },
    },
    buttons = {
      {
        label = 'OK',
        key = '<C-s>',
        run = function(values, form)
          store.set(p.root, 'maven', values, 'pc_maven.json')
          state.offline, state.skip_tests = values.offline, values.skip_tests
          state.profiles[p.root] = vim.split(values.profiles or '', '%s*,%s*', { trimempty = true })
          plugin_cache[p.pom] = nil
          form:close()
          if window_open() then
            M.refresh()
          end
          vim.notify 'Maven settings saved'
        end,
      },
    },
  }
end

function M.toggle()
  if window_open() then
    vim.api.nvim_win_close(win.win, true)
    return
  end
  local p = project(vim.api.nvim_buf_get_name(0))
  if not p then
    return vim.notify('Maven: no pom.xml here', vim.log.levels.WARN)
  end
  win.project, win.pom = p, p.pom
  -- the defaults from Maven settings, once per project and session
  if not state.defaults[p.root] then
    state.defaults[p.root] = true
    local s = settings(p)
    if s.offline ~= nil then
      state.offline, state.skip_tests = s.offline, s.skip_tests
    end
    if (s.profiles or '') ~= '' and not state.profiles[p.root] then
      state.profiles[p.root] = vim.split(s.profiles, '%s*,%s*', { trimempty = true })
    end
  end
  win.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.buf].filetype = 'pcmaven'
  vim.bo[win.buf].bufhidden = 'wipe'
  vim.cmd 'botright vsplit'
  win.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win.win, win.buf)
  vim.api.nvim_win_set_width(win.win, 45)
  vim.wo[win.win].number = false
  vim.wo[win.win].relativenumber = false
  vim.wo[win.win].signcolumn = 'no'
  vim.wo[win.win].winfixwidth = true
  vim.wo[win.win].cursorline = true
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = win.buf, desc = desc })
  end
  map('<CR>', function()
    local action = actions[vim.api.nvim_win_get_cursor(0)[1]]
    if action then
      action()
    end
  end, 'Run goal / toggle profile')
  map('o', function()
    state.offline = not state.offline
    M.refresh()
  end, 'Toggle offline')
  map('s', function()
    state.skip_tests = not state.skip_tests
    M.refresh()
  end, 'Toggle skip tests')
  map('r', M.reimport, 'Reimport')
  map('u', M.update_folders, 'Update folders')
  map('g', M.execute_goal, 'Execute goal…')
  map('S', M.settings, 'Maven settings')
  map('R', function()
    plugin_cache[p.pom] = nil
    M.refresh()
  end, 'Refresh')
  map('q', M.toggle, 'Close')
  M.refresh()
  vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
end

vim.keymap.set('n', '<leader>MM', M.toggle, { desc = '[M]aven window (toggle)' })
vim.keymap.set('n', '<leader>Mr', M.reimport, { desc = 'Maven: [r]eimport' })
vim.keymap.set('n', '<leader>Mu', M.update_folders, { desc = 'Maven: [u]pdate folders' })
vim.keymap.set('n', '<leader>Mg', M.execute_goal, { desc = 'Maven: execute [g]oal…' })
vim.keymap.set('n', '<leader>Ms', M.settings, { desc = 'Maven: [s]ettings' })

return M
