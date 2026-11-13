-- Plugins follow lazy-lock.json by themselves: a machine that pulled this config but never ran
-- :Lazy restore kept old plugins (the Mac: telescope 0.1.x warned every session for a week, and
-- neo-tree's filter popup did not close on Esc).
--
-- init.lua calls M.sync() right before lazy.nvim loads the plugins: checkouts that differ from the
-- lock are restored first, by a second, headless Neovim, and this one waits for it. So a session
-- never runs on plugins that change underneath it (restored in the background after startup, one
-- session had neo-tree's files from two versions: "attempt to call field 'setup_option_autocmds'").
-- Several Neovims starting together: one restores, the others wait for it.

local M = {}

local LOCK_DIR = vim.fn.stdpath 'data' .. '/plugin-sync.lock'
local CHILD = 'PC_PLUGIN_SYNC' -- set in the headless Neovim that restores: it must not sync again

--- Names of the installed plugins whose checkout is not the commit in the lock file
---@param lock_file string? lazy-lock.json
---@param plugins_dir string? where lazy.nvim keeps the plugins
function M.stale(lock_file, plugins_dir)
  lock_file = lock_file or vim.fn.stdpath 'config' .. '/lazy-lock.json'
  plugins_dir = plugins_dir or vim.fn.stdpath 'data' .. '/lazy'
  local read, lines = pcall(vim.fn.readfile, lock_file)
  local decoded, lock = pcall(vim.json.decode, read and table.concat(lines, '\n') or '')
  local has_git, git = pcall(require, 'lazy.manage.git')
  if not decoded or type(lock) ~= 'table' or not has_git then
    return {}
  end
  local names = {}
  for name, locked in pairs(lock) do
    local dir = plugins_dir .. '/' .. name
    -- not installed yet: lazy.nvim installs it at the locked commit itself
    if type(locked) == 'table' and locked.commit and vim.uv.fs_stat(dir .. '/.git') then
      local ok, info = pcall(git.info, dir)
      if ok and info and info.commit and info.commit ~= locked.commit then
        table.insert(names, name)
      end
    end
  end
  table.sort(names)
  return names
end

-- one Neovim restores at a time: true when the lock is ours, false when another one holds it
local function take_lock()
  if vim.uv.fs_mkdir(LOCK_DIR, 448) then
    return true
  end
  -- left behind by a Neovim that was killed while restoring
  local stat = vim.uv.fs_stat(LOCK_DIR)
  if stat and os.time() - stat.mtime.sec > 600 then
    vim.uv.fs_rmdir(LOCK_DIR)
    return vim.uv.fs_mkdir(LOCK_DIR, 448) == true
  end
  return false
end

local function restore()
  local out = vim
    .system({ vim.v.progpath, '--headless', '+Lazy! restore', '+qa' }, { text = true, env = { [CHILD] = '1' } })
    :wait(300000)
  return out.code == 0, vim.trim((out.stderr or '') .. '\n' .. (out.stdout or ''))
end

--- Brings the plugins to lazy-lock.json before they are loaded. `opts` is for the tests:
--- `stale` and `restore` replace the real ones.
function M.sync(opts)
  opts = opts or {}
  -- not in the Neovim that restores, and not in scripts (tests, :Lazy from the shell)
  if vim.env[CHILD] or (not opts.restore and vim.tbl_contains(vim.v.argv, '--headless')) then
    return
  end
  local stale = opts.stale or M.stale
  local names = stale()
  if #names == 0 then
    return
  end
  if not take_lock() then
    -- another Neovim is restoring: wait until it is done (at most 2 minutes)
    vim.wait(120000, function()
      return vim.uv.fs_stat(LOCK_DIR) == nil
    end, 200)
    return
  end
  print(('Bringing %d plugin(s) to lazy-lock.json (%s)…'):format(#names, table.concat(names, ', ')))
  local ran, ok, output = pcall(opts.restore or restore)
  vim.uv.fs_rmdir(LOCK_DIR)
  local left = stale()
  vim.schedule(function()
    if ran and ok and #left == 0 then
      vim.notify(('%d plugin(s) brought to lazy-lock.json: %s'):format(#names, table.concat(names, ', ')), vim.log.levels.INFO)
    else
      local why = tostring(ran and output or ok or ''):sub(-400)
      vim.notify(('Plugins differ from lazy-lock.json and could not be restored (%s): run :Lazy restore\n%s'):format(table.concat(left, ', '), why), vim.log.levels.WARN)
    end
  end)
end

return M
