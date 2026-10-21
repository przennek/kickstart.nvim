-- Copy Class / Copy File (F5), like IDEA: a dialog with the new name and where to put it
-- (Java: the package, created when missing; other files: the directory). The copy opens in the
-- editor. Java: the class name (declaration, constructors, references to itself) and the package
-- line are changed in the copy. In the file tree (neo-tree) F5 copies the file under the cursor.
-- While debugging F5 is still Continue.

local M = {}

local function relative(path)
  return vim.fn.fnamemodify(path, ':~:.')
end

-- The file's package and its source root (…/src/main/java), from the package line
local function java_package(path, lines)
  for _, line in ipairs(lines) do
    local pkg = line:match '^%s*package%s+([%w_.]+)%s*;'
    if pkg then
      local dir = vim.fs.dirname(path)
      local sub = pkg:gsub('%.', '/')
      if dir:sub(-#sub) == sub then
        return pkg, dir:sub(1, -#sub - 2)
      end
      return pkg, nil
    end
  end
  return '', vim.fs.dirname(path)
end

local function read(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  return vim.fn.readfile(path)
end

-- Classes of the old package the copy uses: in another package they need imports
local function sibling_imports(path, lines, old_name, old_pkg)
  local text = table.concat(lines, '\n')
  local imports = {}
  for name, type in vim.fs.dir(vim.fs.dirname(path)) do
    local class = type == 'file' and name:match '^(.+)%.java$'
    if class and class ~= old_name and vim.fn.match(text, '\\C\\<' .. class .. '\\>') >= 0 then
      table.insert(imports, ('import %s.%s;'):format(old_pkg, class))
    end
  end
  table.sort(imports)
  return imports
end

-- The copy's lines: Java gets the new class name and package (+ imports from the old one)
local function java_copy(lines, old_name, new_name, old_pkg, new_pkg, imports)
  local out = {}
  for _, line in ipairs(lines) do
    if old_pkg ~= new_pkg and line:match '^%s*package%s' then
      line = new_pkg ~= '' and ('package ' .. new_pkg .. ';') or ''
    else
      -- whole words only: Order → Invoice leaves OrderLine alone
      line = vim.fn.substitute(line, '\\C\\<' .. old_name .. '\\>', new_name, 'g')
    end
    table.insert(out, line)
  end
  if old_pkg == '' and new_pkg ~= '' then
    table.insert(out, 1, 'package ' .. new_pkg .. ';')
    table.insert(out, 2, '')
  end
  if old_pkg ~= new_pkg and old_pkg ~= '' and #imports > 0 then
    -- after the last import, else after the package line
    local at = 0
    for i, line in ipairs(out) do
      if line:match '^import%s' or (at == 0 and line:match '^package%s') then
        at = i
      end
    end
    for i, imp in ipairs(imports) do
      table.insert(out, at + i, imp)
    end
    if at > 0 and not out[at]:match '^import%s' then
      table.insert(out, at + 1, '')
    end
  end
  return out
end

--- Opens the Copy dialog for `path` (default: the current file)
function M.copy(path)
  path = vim.fn.fnamemodify(path or vim.api.nvim_buf_get_name(0), ':p')
  if path == '' or vim.fn.filereadable(path) == 0 then
    return vim.notify('Copy: not a file', vim.log.levels.WARN)
  end
  local java = path:match '%.java$' ~= nil
  local lines = read(path)
  local ext = vim.fn.fnamemodify(path, ':e')
  local old_name = vim.fn.fnamemodify(path, ':t:r')
  local values = { name = old_name .. (java and '1' or '_copy') }
  local old_pkg, root
  if java then
    old_pkg, root = java_package(path, lines)
    values.package = old_pkg
  end
  if not root then
    java, values.package = false, nil
  end
  if not java then
    values.directory = relative(vim.fs.dirname(path))
  end

  local function target(v)
    local dir = java and vim.fs.joinpath(root, (v.package:gsub('%.', '/'))) or vim.fn.fnamemodify(v.directory, ':p')
    return vim.fs.normalize(vim.fs.joinpath(dir, v.name .. (ext ~= '' and ('.' .. ext) or '')))
  end

  require('pc.form').open {
    title = java and 'Copy Class' or 'Copy File',
    values = values,
    focus = 'name',
    fields = {
      { key = 'from', label = 'Copy', readonly = true, value = function()
        return relative(path)
      end },
      { key = 'name', label = java and 'New name' or 'New name (no extension)' },
      java and { key = 'package', label = 'To package' } or { key = 'directory', label = 'To directory' },
      { key = 'to', label = 'Creates', readonly = true, value = function(v)
        return relative(target(v))
      end },
    },
    buttons = {
      {
        label = 'OK',
        key = '<C-s>',
        run = function(v, form)
          v.name = vim.trim(v.name or '')
          if java and not v.name:match '^[%a_$][%w_$]*$' then
            return form:say('Not a valid class name', vim.log.levels.ERROR)
          elseif v.name == '' then
            return form:say('Enter a name', vim.log.levels.ERROR)
          elseif java and not (v.package or ''):match '^[%w_.]*$' then
            return form:say('Not a valid package', vim.log.levels.ERROR)
          end
          local new = target(v)
          if vim.uv.fs_stat(new) then
            return form:say(relative(new) .. ' already exists', vim.log.levels.ERROR)
          end
          local out = java and java_copy(lines, old_name, v.name, old_pkg, v.package, sibling_imports(path, lines, old_name, old_pkg)) or lines
          vim.fn.mkdir(vim.fs.dirname(new), 'p')
          vim.fn.writefile(out, new)
          require('pc.git_track').add(new)
          form:close()
          vim.cmd.edit(vim.fn.fnameescape(new))
          vim.notify('Copied to ' .. relative(new))
        end,
      },
    },
  }
end

vim.api.nvim_create_user_command('CopyClass', function(opts)
  M.copy(opts.args ~= '' and opts.args or nil)
end, { nargs = '?', complete = 'file', desc = 'Copy Class / File (F5)' })

return M
