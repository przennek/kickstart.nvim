-- Run Anything like IDEA's (Ctrl twice): type any command and run it in the project root, in the
-- Run window (Alt+4). The list suggests recent commands of this project, npm scripts, Maven goals
-- and Makefile targets; Enter runs the highlighted one, or what you typed when nothing matches
-- (Ctrl+Enter / Alt+Enter: always what you typed).
--   <leader>X / :RunAnything

local M = {}

local FILE = vim.fn.stdpath 'data' .. '/pc_run_anything.json'
local HISTORY = 30

local function root()
  return vim.fs.root(0, { '.git', 'pom.xml', 'package.json', 'pyproject.toml', 'Makefile', 'build.gradle' }) or vim.fn.getcwd()
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

local function remember(dir, cmd)
  local all = read_all()
  local list = vim.tbl_filter(function(c)
    return c ~= cmd
  end, all[dir] or {})
  table.insert(list, 1, cmd)
  all[dir] = vim.list_slice(list, 1, HISTORY)
  local f = io.open(FILE, 'w')
  if f then
    f:write(vim.json.encode(all))
    f:close()
  end
end

-- Suggestions for the project: { cmd, kind }
local function suggestions(dir)
  local items, seen = {}, {}
  local function add(cmd, kind)
    if not seen[cmd] then
      seen[cmd] = true
      table.insert(items, { cmd = cmd, kind = kind })
    end
  end
  for _, cmd in ipairs(read_all()[dir] or {}) do
    add(cmd, 'recent')
  end
  local pkg = vim.fs.joinpath(dir, 'package.json')
  if vim.uv.fs_stat(pkg) then
    local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(pkg), '\n'))
    for name in pairs(ok and data.scripts or {}) do
      add('npm run ' .. name, 'npm')
    end
  end
  if vim.uv.fs_stat(vim.fs.joinpath(dir, 'pom.xml')) then
    local mvn = vim.uv.fs_stat(vim.fs.joinpath(dir, 'mvnw')) and './mvnw' or 'mvn'
    for _, goal in ipairs { 'clean install', 'test', 'package', 'compile', 'verify', 'dependency:tree', 'clean' } do
      add(mvn .. ' ' .. goal, 'maven')
    end
  end
  local makefile = vim.fs.joinpath(dir, 'Makefile')
  if vim.uv.fs_stat(makefile) then
    for _, line in ipairs(vim.fn.readfile(makefile)) do
      local target = line:match '^([%w_.-]+):[^=]'
      if target and not target:match '^%.' then
        add('make ' .. target, 'make')
      end
    end
  end
  return items
end

local function run(dir, cmd)
  cmd = vim.trim(cmd or '')
  if cmd == '' then
    return
  end
  remember(dir, cmd)
  require('pc.run').run_in_console(cmd, dir)
end

function M.open()
  local dir = root()
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local actions = require 'telescope.actions'
  local state = require 'telescope.actions.state'
  pickers
    .new({}, {
      prompt_title = 'Run Anything in ' .. vim.fn.fnamemodify(dir, ':~'),
      finder = finders.new_table {
        results = suggestions(dir),
        entry_maker = function(item)
          return { value = item.cmd, display = ('%-7s %s'):format(item.kind, item.cmd), ordinal = item.cmd }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      attach_mappings = function(prompt_bufnr, map)
        local function typed()
          return state.get_current_line()
        end
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          local text = typed()
          actions.close(prompt_bufnr)
          run(dir, entry and entry.value or text)
        end)
        local function run_typed()
          local text = typed()
          actions.close(prompt_bufnr)
          run(dir, text)
        end
        map({ 'i', 'n' }, '<C-CR>', run_typed, { desc = 'Run what was typed' })
        map({ 'i', 'n' }, '<M-CR>', run_typed, { desc = 'Run what was typed' })
        return true
      end,
    })
    :find()
end

vim.keymap.set('n', '<leader>X', M.open, { desc = 'Run Anything…' })
vim.api.nvim_create_user_command('RunAnything', M.open, { desc = 'Run Anything' })

return M
