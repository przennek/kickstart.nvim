-- pc.plugin_sync: checkouts that differ from lazy-lock.json are found, restored before the
-- plugins load (once), and a failed restore is reported. Prints "OK …" or "FAIL …" and quits.
local sync = require 'pc.plugin_sync'
local problems = {}
local function check(label, ok)
  if not ok then
    table.insert(problems, label)
  end
end

local dir = vim.fn.tempname()
local function plugin(name, commit)
  vim.fn.mkdir(dir .. '/lazy/' .. name .. '/.git', 'p')
  vim.fn.writefile({ commit }, dir .. '/lazy/' .. name .. '/.git/HEAD')
end
local A, B = ('a'):rep(40), ('b'):rep(40)
plugin('same.nvim', A)
plugin('old.nvim', B)
local lock = dir .. '/lazy-lock.json'
vim.fn.writefile({ vim.json.encode { ['same.nvim'] = { branch = 'main', commit = A }, ['old.nvim'] = { branch = 'main', commit = A }, ['missing.nvim'] = { branch = 'main', commit = A } } }, lock)

local function stale()
  return sync.stale(lock, dir .. '/lazy')
end
check('stale: only the plugin at another commit, got ' .. vim.inspect(stale()), vim.deep_equal(stale(), { 'old.nvim' }))
check('stale: a broken lock file is no plugins', #sync.stale(dir .. '/none.json', dir .. '/lazy') == 0)

local runs = 0
sync.sync {
  stale = stale,
  restore = function()
    runs = runs + 1
    plugin('old.nvim', A)
    return true, ''
  end,
}
check('sync: restores once, got ' .. runs, runs == 1)
check('sync: nothing stale afterwards', #stale() == 0)
sync.sync {
  stale = stale,
  restore = function()
    runs = runs + 1
    return true, ''
  end,
}
check('sync: nothing to do the second time, got ' .. runs, runs == 1)
check('sync: the lock is released', vim.uv.fs_stat(vim.fn.stdpath 'data' .. '/plugin-sync.lock') == nil)

vim.fn.delete(dir, 'rf')
vim.defer_fn(function()
  io.stdout:write('\n' .. (#problems == 0 and 'OK plugin_sync' or ('FAIL plugin_sync: ' .. table.concat(problems, '; '))) .. '\n')
  vim.cmd 'qa!'
end, 200)
