-- New… like IDEA's (Ctrl+Enter in the project tree, :New / :NewClass in the editor):
--   Java Class      dialog (pc.form): name (a.b.Name makes sub-packages), kind (Class, Interface,
--                   Enum, Record, Annotation, Exception), package — the file comes with the package
--                   line and the type's skeleton and opens with the cursor inside it
--   Python File / Python Package (directory with __init__.py), File, Directory
-- The package and source root follow the directory: src/main/java, src/test/java, …

local M = {}

local SKELETONS = {
  Class = 'public class %s {\n    \n}',
  Interface = 'public interface %s {\n    \n}',
  Enum = 'public enum %s {\n    \n}',
  Record = 'public record %s() {\n    \n}',
  Annotation = 'public @interface %s {\n    \n}',
  Exception = 'public class %s extends RuntimeException {\n\n    public %s(String message) {\n        super(message);\n    }\n}',
}

-- Source root and package of a directory: …/src/main/java/a/b → …/src/main/java, a.b
local function java_location(dir)
  local root, rest = dir:match '^(.-/src/[^/]+/java)/?(.*)$'
  if not root then
    root, rest = dir:match '^(.-/src)/?(.*)$'
  end
  if not root then
    return dir, ''
  end
  return root, (rest or ''):gsub('/', '.')
end

local function open_at(path, row)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  if row then
    vim.api.nvim_win_set_cursor(0, { row, 4 })
  end
end

local function after_create(on_done)
  if on_done then
    on_done()
  end
  pcall(function()
    require('neo-tree.sources.manager').refresh 'filesystem'
  end)
end

function M.java_class(dir, on_done)
  local root, package = java_location(dir)
  require('pc.form').open {
    title = 'New Java Class',
    values = { package = package },
    fields = {
      { key = 'name', label = 'Name', default = '' },
      { key = 'kind', label = 'Kind', choices = { 'Class', 'Interface', 'Enum', 'Record', 'Annotation', 'Exception' }, default = 'Class' },
      { key = 'package', label = 'Package', default = '' },
      { key = 'file', label = 'File', readonly = true, value = function(v)
        local name = v.name or ''
        local pkg = v.package or ''
        local sub, simple = name:match '^(.*)%.([^.]+)$'
        if sub then
          pkg = pkg ~= '' and (pkg .. '.' .. sub) or sub
          name = simple
        end
        return vim.fn.fnamemodify(root, ':~:.') .. '/' .. (pkg ~= '' and pkg:gsub('%.', '/') .. '/' or '') .. name .. '.java'
      end },
    },
    buttons = {
      {
        label = 'OK',
        key = '<C-s>',
        run = function(values, form)
          local name, pkg = vim.trim(values.name or ''), vim.trim(values.package or '')
          local sub, simple = name:match '^(.*)%.([^.]+)$'
          if sub then
            pkg = pkg ~= '' and (pkg .. '.' .. sub) or sub
            name = simple
          end
          if not name:match '^[%a_$][%w_$]*$' then
            return form:say('Not a valid class name: ' .. name, vim.log.levels.ERROR)
          end
          local target_dir = root .. (pkg ~= '' and '/' .. pkg:gsub('%.', '/') or '')
          local path = target_dir .. '/' .. name .. '.java'
          if vim.uv.fs_stat(path) then
            return form:say(vim.fn.fnamemodify(path, ':.') .. ' already exists', vim.log.levels.ERROR)
          end
          vim.fn.mkdir(target_dir, 'p')
          local body = SKELETONS[values.kind]:gsub('%%s', name)
          local text = (pkg ~= '' and ('package ' .. pkg .. ';\n\n') or '') .. body .. '\n'
          vim.fn.writefile(vim.split(text, '\n', { plain = true }), path)
          form:close()
          -- the empty line inside the type
          local lines = vim.split(text, '\n', { plain = true })
          local row = vim.fn.index(lines, '    ') + 1
          open_at(path, row > 0 and row or nil)
          after_create(on_done)
        end,
      },
    },
  }
end

local function ask(prompt, fn)
  vim.ui.input({ prompt = prompt }, function(name)
    if name and vim.trim(name) ~= '' then
      fn(vim.trim(name))
    end
  end)
end

function M.menu(dir, on_done)
  dir = dir or vim.fn.expand '%:p:h'
  local items = {
    { label = 'Java Class', run = function()
      M.java_class(dir, on_done)
    end },
    { label = 'Python File', run = function()
      ask('New Python file: ', function(name)
        local path = dir .. '/' .. name:gsub('%.py$', '') .. '.py'
        vim.fn.mkdir(vim.fs.dirname(path), 'p')
        if not vim.uv.fs_stat(path) then
          vim.fn.writefile({}, path)
        end
        open_at(path)
        after_create(on_done)
      end)
    end },
    { label = 'Python Package', run = function()
      ask('New Python package: ', function(name)
        local pkg_dir = dir .. '/' .. name:gsub('%.', '/')
        vim.fn.mkdir(pkg_dir, 'p')
        if not vim.uv.fs_stat(pkg_dir .. '/__init__.py') then
          vim.fn.writefile({}, pkg_dir .. '/__init__.py')
        end
        after_create(on_done)
      end)
    end },
    { label = 'File', run = function()
      ask('New file: ', function(name)
        local path = dir .. '/' .. name
        vim.fn.mkdir(vim.fs.dirname(path), 'p')
        open_at(path)
        after_create(on_done)
      end)
    end },
    { label = 'Directory', run = function()
      ask('New directory: ', function(name)
        vim.fn.mkdir(dir .. '/' .. name, 'p')
        after_create(on_done)
      end)
    end },
  }
  vim.ui.select(items, {
    prompt = 'New in ' .. vim.fn.fnamemodify(dir, ':~:.'),
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    if item then
      item.run()
    end
  end)
end

vim.api.nvim_create_user_command('New', function()
  M.menu()
end, { desc = 'New… (in the directory of the current file)' })
vim.api.nvim_create_user_command('NewClass', function()
  M.java_class(vim.fn.expand '%:p:h')
end, { desc = 'New Java Class' })

return M
