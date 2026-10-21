-- Files the IDE creates, renames or moves (refactorings, Move, the project tree, New…, Copy
-- Class) go into git like IDEA adds them to VCS: `git add --intent-to-add`, so the next commit
-- takes the new file together with the deletion of the old one. Ignored files and files outside
-- a git repository are left alone; a rename / move only when the old file was in git.

local M = {}

local function git(dir, args)
  return vim.system(vim.list_extend({ 'git', '-C', dir }, args), { text = true }):wait().code == 0
end

-- the nearest existing directory of a path (a moved directory is gone)
local function existing_dir(path)
  local dir = vim.fs.dirname(path)
  while dir and not vim.uv.fs_stat(dir) do
    local up = vim.fs.dirname(dir)
    dir = up ~= dir and up or nil
  end
  return dir
end

--- Is the file (or a directory with files) in git? The index knows also after a move.
function M.tracked(path)
  local dir = existing_dir(path)
  return dir ~= nil and git(dir, { 'ls-files', '--error-unmatch', '--', path })
end

--- After `path` was created (old = nil) or renamed from a file that was tracked (`was_tracked`)
function M.add(path, old, was_tracked)
  if old and not was_tracked then
    return
  end
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return
  end
  local files = { path }
  if stat.type == 'directory' then
    -- a moved / renamed directory: its files
    files = vim.fs.find(function()
      return true
    end, { path = path, type = 'file', limit = math.huge })
  end
  local dir = stat.type == 'directory' and path or vim.fs.dirname(path)
  if not git(dir, { 'rev-parse', '--is-inside-work-tree' }) then
    return
  end
  local add = {}
  for _, f in ipairs(files) do
    if not git(dir, { 'check-ignore', '-q', '--', f }) and not git(dir, { 'ls-files', '--error-unmatch', '--', f }) then
      table.insert(add, f)
    end
  end
  if #add > 0 then
    git(dir, vim.list_extend({ 'add', '--intent-to-add', '--' }, add))
  end
  -- the old path was only an intent to add (never committed): its index entry goes, else git
  -- shows it as deleted
  if old and not vim.uv.fs_stat(old) then
    local r = vim.system({ 'git', '-C', dir, 'ls-files', '--full-name', '--', old }, { text = true }):wait()
    for name in (r.stdout or ''):gmatch '[^\n]+' do
      if not git(dir, { 'cat-file', '-e', 'HEAD:' .. name }) then
        git(dir, { 'rm', '--cached', '--quiet', '--ignore-unmatch', '--', ':/' .. name })
      end
    end
  end
end

--- A rename / move done by `fn` (old → new): tracks the new path when the old one was in git
function M.move(old, new, fn)
  local was = M.tracked(old)
  local result = fn()
  M.add(new, old, was)
  return result
end

return M
