-- Run/Debug Configurations you define yourself, like IDEA's "Edit Configurations…" dialog (pc.form):
-- F10 lists them first (▶ run, 🐞 debug) and ends with "Edit Configurations…".
--   Java application   main class, program arguments, VM options, environment, working directory
--                      (run and debug through jdtls / java-debug)
--   Python script      script, arguments, environment, working directory (debug through debugpy)
--   Shell command      anything: a C binary, make, npm, mvn… (runs in the Run window)
-- Saved per project (git root, else the working directory) in stdpath('data')/run_configs.json.

local M = {}

local FILE = vim.fn.stdpath 'data' .. '/run_configs.json'
local TYPES = { 'Java application', 'Python script', 'Shell command' }

local function project()
  return vim.fs.root(0, { '.git', 'pom.xml', 'build.gradle', 'pyproject.toml', 'package.json', 'Makefile' }) or vim.fn.getcwd()
end

local function read_all()
  local f = io.open(FILE)
  if not f then
    return {}
  end
  local ok, all = pcall(vim.json.decode, f:read '*a')
  f:close()
  return ok and type(all) == 'table' and all or {}
end

local function write_all(all)
  local f = assert(io.open(FILE, 'w'))
  f:write(vim.json.encode(all))
  f:close()
end

function M.list()
  return read_all()[project()] or {}
end

local function save_list(list)
  local all = read_all()
  all[project()] = #list > 0 and list or nil
  write_all(all)
end

-- 'a "b c" d' → { 'a', 'b c', 'd' }
local function split_args(s)
  local args, cur, quote = {}, nil, nil
  for ch in (s or ''):gmatch '.' do
    if quote then
      if ch == quote then
        quote = nil
      else
        cur = (cur or '') .. ch
      end
    elseif ch == '"' or ch == "'" then
      quote, cur = ch, cur or ''
    elseif ch:match '%s' then
      if cur then
        table.insert(args, cur)
        cur = nil
      end
    else
      cur = (cur or '') .. ch
    end
  end
  if cur then
    table.insert(args, cur)
  end
  return args
end

-- 'A=1; B=two' → { A = '1', B = 'two' }
local function parse_env(s)
  local env = {}
  for pair in (s or ''):gmatch '[^;\n]+' do
    local k, v = pair:match '^%s*([%w_]+)%s*=%s*(.-)%s*$'
    if k then
      env[k] = v
    end
  end
  return env
end

local function workdir(c)
  return (c.cwd and c.cwd ~= '') and vim.fn.expand(c.cwd) or project()
end

local function shell_line(c, cmd)
  local env = {}
  for k, v in pairs(parse_env(c.env)) do
    table.insert(env, k .. '=' .. vim.fn.shellescape(v))
  end
  return (#env > 0 and ('env ' .. table.concat(env, ' ') .. ' ') or '') .. cmd
end

local function python_of(dir)
  local venv = dir .. '/.venv/bin/python'
  return vim.uv.fs_stat(venv) and venv or 'python3'
end

local function run_java(c, debug)
  require('lazy').load { plugins = { 'nvim-dap' } }
  local ok = pcall(require('jdtls.dap').fetch_main_configs, nil, function(configs)
    local base
    for _, cfg in ipairs(configs) do
      if cfg.mainClass == c.target or cfg.mainClass:match('[^.]+$') == c.target then
        base = cfg
      end
    end
    vim.schedule(function()
      if not base then
        return vim.notify('Run configuration "' .. c.name .. '": main class ' .. c.target .. ' not found', vim.log.levels.ERROR)
      end
      require('dap').run(vim.tbl_extend('force', base, {
        name = c.name,
        args = c.args or '',
        vmArgs = c.vm_options or '',
        env = parse_env(c.env),
        cwd = workdir(c),
        noDebug = not debug,
      }))
    end)
  end)
  if not ok then
    vim.notify('Java configurations need a Java file open (jdtls)', vim.log.levels.WARN)
  end
end

local function run_config(c, debug)
  local run = require 'pc.run'
  local dir = workdir(c)
  if c.type == 'Java application' then
    run.note_dap_run()
    return run_java(c, debug)
  elseif c.type == 'Python script' then
    local script = vim.fn.expand(c.target)
    script = script:sub(1, 1) == '/' and script or vim.fs.joinpath(project(), script)
    if debug then
      require('lazy').load { plugins = { 'nvim-dap' } }
      run.note_dap_run()
      return require('dap').run {
        type = 'python',
        request = 'launch',
        name = c.name,
        program = script,
        args = split_args(c.args),
        env = parse_env(c.env),
        cwd = dir,
        python = python_of(project()),
      }
    end
    local args = vim.tbl_map(vim.fn.shellescape, split_args(c.args))
    return run.run_in_console(shell_line(c, python_of(project()) .. ' ' .. vim.fn.shellescape(script) .. ' ' .. table.concat(args, ' ')), dir)
  end
  run.run_in_console(shell_line(c, c.target .. ((c.args or '') ~= '' and ' ' .. c.args or '')), dir)
end

--- F10 entries: { label, run } for each saved configuration of this project
function M.items(run_prefix, debug_prefix)
  local items = {}
  for _, c in ipairs(M.list()) do
    table.insert(items, {
      label = run_prefix .. c.name,
      dap = c.type == 'Java application',
      run = function()
        run_config(c, false)
      end,
    })
    if c.type ~= 'Shell command' then
      table.insert(items, {
        label = debug_prefix .. c.name,
        run = function()
          run_config(c, true)
        end,
      })
    end
  end
  return items
end

--- The configuration dialog; config = one to edit, nil for a new one of `kind`
function M.open(config, kind)
  local function is(t)
    return function(v)
      return v.type == t
    end
  end
  local defaults = { type = kind or TYPES[1] }
  if not config and defaults.type == 'Python script' and vim.bo.filetype == 'python' then
    defaults.target = vim.fn.expand '%:.'
    defaults.name = vim.fn.expand '%:t:r'
  elseif not config and defaults.type == 'Java application' and vim.bo.filetype == 'java' then
    defaults.target = vim.fn.expand '%:t:r'
    defaults.name = defaults.target
  end
  require('pc.form').open {
    title = config and ('Run Configuration: ' .. config.name) or ('New ' .. defaults.type),
    values = config or defaults,
    fields = {
      { key = 'name', label = 'Name', default = '' },
      { key = 'type', label = 'Type', choices = TYPES, default = TYPES[1] },
      { key = 'target', label = 'Main class', visible = is 'Java application' },
      { key = 'target', label = 'Script', complete = 'file', visible = is 'Python script' },
      { key = 'target', label = 'Command', complete = 'shellcmd', visible = is 'Shell command' },
      { key = 'args', label = 'Program arguments', default = '' },
      { key = 'vm_options', label = 'VM options', default = '', visible = is 'Java application' },
      { key = 'env', label = 'Environment (A=1; B=2)', default = '' },
      { key = 'cwd', label = 'Working directory', default = '', complete = 'dir' },
    },
    buttons = {
      {
        label = 'OK',
        key = '<C-s>',
        run = function(values, form)
          if (values.name or '') == '' or (values.target or '') == '' then
            return form:say('Name and ' .. (values.type == 'Shell command' and 'command' or values.type == 'Python script' and 'script' or 'main class') .. ' are required', vim.log.levels.ERROR)
          end
          local list = M.list()
          for i = #list, 1, -1 do
            if list[i].name == (config and config.name) or list[i].name == values.name then
              table.remove(list, i)
            end
          end
          table.insert(list, values)
          save_list(list)
          form:close()
          vim.notify(('Run configuration "%s" saved (F10)'):format(values.name))
        end,
      },
      {
        label = 'Remove',
        key = '<C-d>',
        run = function(_, form)
          if config and vim.fn.confirm('Remove "' .. config.name .. '"?', '&Remove\n&Cancel', 2) == 1 then
            save_list(vim.tbl_filter(function(c)
              return c.name ~= config.name
            end, M.list()))
            form:close()
          end
        end,
      },
    },
  }
end

--- Edit Configurations…: pick one to edit, or add a new one
function M.edit()
  local items = {}
  for _, t in ipairs(TYPES) do
    table.insert(items, { label = '+ New ' .. t, kind = t })
  end
  for _, c in ipairs(M.list()) do
    table.insert(items, { label = c.name .. '  (' .. c.type .. ')', config = c })
  end
  vim.ui.select(items, {
    prompt = 'Run/Debug Configurations',
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    if item then
      M.open(item.config, item.kind)
    end
  end)
end

vim.api.nvim_create_user_command('EditConfigurations', M.edit, { desc = 'Edit Run/Debug Configurations' })

return M
