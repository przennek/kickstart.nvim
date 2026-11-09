-- Plugins follow lazy-lock.json by themselves: a machine that pulled this config but never ran
-- :Lazy restore kept old plugins (the Mac: telescope 0.1.x warned every session for a week, and
-- neo-tree's filter popup did not close on Esc). Plugins whose checkout differs from the lock are
-- restored in the background after startup; a restart loads them.

local function stale()
  local ok, lock = pcall(vim.json.decode, table.concat(vim.fn.readfile(vim.fn.stdpath 'config' .. '/lazy-lock.json'), '\n'))
  if not ok then
    return {}
  end
  local git = require 'lazy.manage.git'
  local names = {}
  for name, plugin in pairs(require('lazy.core.config').plugins) do
    local locked = lock[name]
    if locked and plugin._.installed and not plugin.dev and not plugin._.is_local then
      local info = git.info(plugin.dir)
      if info and info.commit ~= locked.commit then
        table.insert(names, name)
      end
    end
  end
  table.sort(names)
  return names
end

vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.defer_fn(function()
      local names = stale()
      if #names == 0 then
        return
      end
      require('lazy').restore { plugins = names, show = false, wait = false }
      vim.notify(('%d plugin(s) brought to lazy-lock.json (%s): restart Neovim to use them'):format(#names, table.concat(names, ', ')), vim.log.levels.INFO)
    end, 2000)
  end,
})
