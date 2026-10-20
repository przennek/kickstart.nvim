-- File → Invalidate Caches… like IDEA's, in a dialog (pc.form): for when the Java language server
-- gets confused (stale errors, classes not found after a branch switch).
--   :InvalidateCaches (also in Settings, Ctrl+Alt+S)
--   [x] Java language server data of this project (jdtls workspace: index, build state)
--   [ ] Java language server data of all projects
--   [ ] Local History
--   [x] Lua module cache (vim.loader)
--   [x] Restart language servers
-- Only Neovim's own cache / data directories are deleted, never project files.

local M = {}

local CACHE = vim.fn.stdpath 'cache'

local function jdtls_dir(root)
  return CACHE .. '/jdtls/' .. root:gsub('/', '_')
end

-- language servers of the open buffers: stop them, then attach again like opening the files
local function restart_servers()
  local buffers = {}
  for _, client in ipairs(vim.lsp.get_clients()) do
    for buf in pairs(client.attached_buffers) do
      buffers[buf] = true
    end
    client:stop(true)
  end
  -- sonarlint.nvim remembers its client per project and would attach to the stopped one
  if package.loaded.sonarlint then
    require('sonarlint')._client_id_by_root_dir = {}
  end
  vim.defer_fn(function()
    for buf in pairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
        vim.api.nvim_exec_autocmds('FileType', { buffer = buf, modeline = false })
      end
    end
  end, 1500)
  return vim.tbl_count(buffers)
end

function M.open()
  local root = require('pc.project_structure').root()
  require('pc.form').open {
    title = 'Invalidate Caches',
    values = {},
    fields = {
      { header = 'Optional actions' },
      { key = 'jdtls', label = 'Java server data of this project', check = true, default = true },
      { key = 'jdtls_all', label = 'Java server data of all projects', check = true, default = false },
      { key = 'local_history', label = 'Local History', check = true, default = false },
      { key = 'lua', label = 'Lua module cache', check = true, default = true },
      { key = 'restart', label = 'Restart language servers', check = true, default = true },
      { key = 'where', label = 'Project', readonly = true, value = function()
        return vim.fn.fnamemodify(root, ':~')
      end },
    },
    buttons = {
      {
        label = 'Invalidate and Restart',
        key = '<C-s>',
        run = function(values, form)
          form:close()
          local done = {}
          -- jdtls must not hold its workspace while it is deleted
          if values.jdtls or values.jdtls_all then
            for _, client in ipairs(vim.lsp.get_clients { name = 'jdtls' }) do
              client:stop(true)
            end
          end
          if values.jdtls_all then
            vim.fn.delete(CACHE .. '/jdtls', 'rf')
            table.insert(done, 'Java data of all projects')
          elseif values.jdtls then
            vim.fn.delete(jdtls_dir(root), 'rf')
            table.insert(done, 'Java data of this project')
          end
          if values.local_history then
            vim.fn.delete(vim.fn.stdpath 'data' .. '/local_history', 'rf')
            table.insert(done, 'Local History')
          end
          if values.lua then
            vim.loader.reset()
            table.insert(done, 'Lua module cache')
          end
          if values.restart or values.jdtls or values.jdtls_all then
            vim.defer_fn(function()
              local n = restart_servers()
              -- jdtls was stopped already: start it again for the Java buffers
              for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'java' and #vim.lsp.get_clients { bufnr = buf, name = 'jdtls' } == 0 then
                  vim.api.nvim_exec_autocmds('FileType', { buffer = buf, modeline = false })
                end
              end
              vim.notify(('Restarting language servers (%d buffers); the Java project is imported again'):format(n))
            end, 500)
          end
          vim.notify('Invalidated: ' .. (#done > 0 and table.concat(done, ', ') or 'nothing'))
        end,
      },
    },
  }
end

vim.api.nvim_create_user_command('InvalidateCaches', M.open, { desc = 'Invalidate Caches…' })

return M
