-- Project settings live in the project like IDEA's: <root>/.idea/nvim/<name>.json (run
-- configurations, Maven profiles, the project SDK, Run Anything history, bookmarks). The
-- directory carries its own .gitignore (`*`), so nothing of it reaches a commit unless you delete
-- that file. Outside a project (the root is $HOME or /) they stay in stdpath('data').
-- Older versions kept everything in one stdpath('data') file keyed by the root: an entry found
-- there moves into the project the first time it is read.

local M = {}

local function data_file(legacy)
  return vim.fn.stdpath 'data' .. '/' .. legacy
end

local function read_json(path)
  local f = io.open(path)
  if not f then
    return nil
  end
  local text = f:read '*a'
  f:close()
  local ok, value = pcall(vim.json.decode, text)
  return ok and value or nil
end

local function write_json(path, value)
  local f = assert(io.open(path, 'w'))
  f:write(vim.json.encode(value))
  f:close()
end

--- Is the root a project of its own (not the home directory or /)?
local function in_project(root)
  root = vim.fs.normalize(root)
  return root ~= vim.fs.normalize '~' and root ~= '/'
end

--- <root>/.idea/nvim, created with its .gitignore when `create`; nil outside a project
function M.dir(root, create)
  if not in_project(root) then
    return nil
  end
  local dir = vim.fs.joinpath(root, '.idea', 'nvim')
  if create and not vim.uv.fs_stat(dir) then
    vim.fn.mkdir(dir, 'p')
    local f = io.open(dir .. '/.gitignore', 'w')
    if f then
      f:write '# local Neovim settings of the project\n*\n'
      f:close()
    end
  end
  return dir
end

--- The stored value of `name` for the project, or nil. `legacy` is the stdpath('data') file of
--- older versions ({ [root] = value }).
function M.get(root, name, legacy)
  local dir = M.dir(root)
  if not dir then
    return (read_json(data_file(legacy)) or {})[root]
  end
  local value = read_json(dir .. '/' .. name .. '.json')
  if value == nil and legacy then
    local all = read_json(data_file(legacy))
    if type(all) == 'table' and all[root] ~= nil then
      value = all[root]
      M.set(root, name, value, legacy)
    end
  end
  return value
end

--- Stores (nil removes) the value of `name` for the project
function M.set(root, name, value, legacy)
  local dir = M.dir(root, value ~= nil)
  if dir then
    local path = dir .. '/' .. name .. '.json'
    if value == nil then
      os.remove(path)
    else
      write_json(path, value)
    end
  end
  -- the old entry goes (outside a project this is where the value lives)
  local file = legacy and data_file(legacy)
  local all = file and read_json(file)
  if type(all) == 'table' and (all[root] ~= nil or not dir) then
    all[root] = (not dir) and value or nil
    write_json(file, all)
  elseif not dir and file and value ~= nil then
    write_json(file, { [root] = value })
  end
end

return M
