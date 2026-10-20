-- Code → Inspect Code… like IDEA's (and its Checkstyle tool window's "Check Project"): a dialog
-- (pc.form) with the scope and the tools, results in the Find window (Alt+3) — not only for the
-- open file as while editing.
--   :InspectCode / <leader>xI   scope: whole project, current directory or current file
--   Checkstyle   Java, the project's checkstyle.xml or the Google / Sun rules
--   PMD          Java, when installed (the project's ruleset or the quickstart rules)
--   Ruff         Python
-- Tools come from Mason or the PATH; missing ones are skipped.

local M = {}

local function project_root()
  return vim.fs.root(0, { 'pom.xml', 'build.gradle', 'build.gradle.kts', 'pyproject.toml', '.git' }) or vim.fn.getcwd()
end

local function project_file(root, names)
  for _, name in ipairs(names) do
    if vim.uv.fs_stat(root .. '/' .. name) then
      return root .. '/' .. name
    end
  end
end

-- Each tool: command for a target and a parser of one output line → quickfix item
local TOOLS = {
  checkstyle = {
    cmd = function(target, opts)
      return { 'checkstyle', '-c', opts.checkstyle_config, '-f', 'plain', target }
    end,
    parse = function(line)
      local level, file, lnum, col, text = line:match '^%[(%u+)%]%s+(.-):(%d+):?(%d*):?%s*(.*)$'
      if file then
        return { filename = file, lnum = tonumber(lnum), col = tonumber(col) or 1, text = 'Checkstyle: ' .. text, type = level == 'ERROR' and 'E' or 'W' }
      end
    end,
  },
  pmd = {
    cmd = function(target, opts)
      return { 'pmd', 'check', '--no-progress', '-d', target, '-R', opts.pmd_rules, '-f', 'text' }
    end,
    parse = function(line)
      local file, lnum, rule, text = line:match '^(.-):(%d+):%s*(%S+):%s*(.*)$'
      if file then
        return { filename = file, lnum = tonumber(lnum), col = 1, text = ('PMD %s: %s'):format(rule, text), type = 'W' }
      end
    end,
  },
  ruff = {
    cmd = function(target)
      return { 'ruff', 'check', '--output-format', 'concise', '--no-cache', target }
    end,
    parse = function(line)
      local file, lnum, col, text = line:match '^(.-):(%d+):(%d+):%s*(.*)$'
      if file then
        return { filename = file, lnum = tonumber(lnum), col = tonumber(col), text = 'Ruff: ' .. text, type = 'W' }
      end
    end,
  },
}

local function run(values)
  local root = project_root()
  local target = values.scope == 'Current file' and vim.api.nvim_buf_get_name(0)
    or values.scope == 'Current directory' and vim.fn.expand '%:p:h'
    or root
  local opts = {
    checkstyle_config = values.checkstyle_config,
    pmd_rules = project_file(root, { 'pmd.xml', 'pmd-ruleset.xml', 'config/pmd/ruleset.xml' }) or 'rulesets/java/quickstart.xml',
  }
  local chosen = {}
  for _, name in ipairs { 'checkstyle', 'pmd', 'ruff' } do
    if values[name] and vim.fn.executable(name) == 1 then
      table.insert(chosen, name)
    end
  end
  if #chosen == 0 then
    return vim.notify('Inspect Code: none of the chosen tools is installed', vim.log.levels.WARN)
  end
  local items, pending = {}, #chosen
  vim.notify(('Inspecting %s with %s…'):format(vim.fn.fnamemodify(target, ':~:.'), table.concat(chosen, ', ')))
  for _, name in ipairs(chosen) do
    local tool = TOOLS[name]
    vim.system(tool.cmd(target, opts), { text = true, cwd = root }, function(r)
      vim.schedule(function()
        for _, line in ipairs(vim.split((r.stdout or '') .. '\n' .. (r.stderr or ''), '\n')) do
          local item = tool.parse(line)
          if item and vim.uv.fs_stat(item.filename) then
            table.insert(items, item)
          end
        end
        pending = pending - 1
        if pending == 0 then
          table.sort(items, function(a, b)
            return a.filename == b.filename and a.lnum < b.lnum or a.filename < b.filename
          end)
          vim.fn.setqflist({}, ' ', { title = 'Inspection Results', items = items })
          vim.notify(('Inspection: %d problems (Alt+3: Find window)'):format(#items), #items > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
          if #items > 0 then
            pcall(function()
              require('trouble').open 'quickfix'
            end)
          end
        end
      end)
    end)
  end
end

function M.open()
  local root = project_root()
  local own = project_file(root, { 'checkstyle.xml', 'config/checkstyle/checkstyle.xml', '.checkstyle.xml' })
  local configs = { '/google_checks.xml', '/sun_checks.xml' }
  if own then
    table.insert(configs, 1, own)
  end
  local function have(tool)
    return vim.fn.executable(tool) == 1
  end
  require('pc.form').open {
    title = 'Inspect Code',
    values = {},
    fields = {
      { key = 'scope', label = 'Scope', choices = { 'Whole project', 'Current directory', 'Current file' }, default = 'Whole project' },
      { header = 'Inspections' },
      { key = 'checkstyle', label = 'Checkstyle (Java)', check = true, default = have 'checkstyle' },
      { key = 'checkstyle_config', label = 'Checkstyle rules', choices = configs, default = configs[1], visible = function(v)
        return v.checkstyle
      end },
      { key = 'pmd', label = 'PMD (Java)' .. (have 'pmd' and '' or ' — not installed'), check = true, default = have 'pmd' },
      { key = 'ruff', label = 'Ruff (Python)' .. (have 'ruff' and '' or ' — not installed'), check = true, default = have 'ruff' },
      { key = 'root', label = 'Project', readonly = true, value = function()
        return vim.fn.fnamemodify(root, ':~')
      end },
    },
    buttons = {
      {
        label = 'Analyze',
        key = '<C-s>',
        run = function(values, form)
          form:close()
          run(values)
        end,
      },
    },
  }
end

vim.api.nvim_create_user_command('InspectCode', M.open, { desc = 'Inspect Code…' })
vim.keymap.set('n', '<leader>xI', M.open, { desc = 'Inspect Code…' })

return M
