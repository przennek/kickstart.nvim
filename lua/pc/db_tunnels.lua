-- Connections through an SSH tunnel and / or a proxy, like the SSH/SSL tab of IDEA's data source.
-- A data source with a tunnel is saved with a URL on 127.0.0.1:<local port>; the tunnel is started
-- when the connection is used (Database window, consoles) and stopped when Neovim exits:
--   SSH            ssh -N -L <local>:<db host>:<db port> user@ssh-host (key or ssh-agent, no prompts);
--                  with a proxy, ssh goes through it (ProxyCommand nc -X 5 / connect)
--   proxy only     ncat listens on <local> and connects to the database through the SOCKS5 / HTTP proxy

local M = {}

local jobs = {} -- local port → job id

local function listening(port)
  local tcp = vim.uv.new_tcp()
  local done, ok = false, false
  tcp:connect('127.0.0.1', port, function(err)
    ok, done = not err, true
  end)
  vim.wait(500, function()
    return done
  end, 20)
  tcp:close()
  return ok
end

--- A free local port, from 15400 up
function M.free_port(taken)
  for port = 15400, 15999 do
    if not (taken or {})[port] then
      local tcp = vim.uv.new_tcp()
      local ok = tcp:bind('127.0.0.1', port) == 0
      tcp:close()
      if ok and not listening(port) then
        return port
      end
    end
  end
end

-- The command keeping the tunnel of a data source's settings (see db_connections) open
function M.command(pc)
  local db_host, db_port = pc.host, tostring(pc.port)
  local proxy = pc.proxy and pc.proxy_host ~= '' and pc.proxy_host .. ':' .. pc.proxy_port or nil
  if pc.ssh then
    local cmd = { 'ssh', '-N', '-o', 'ExitOnForwardFailure=yes', '-o', 'BatchMode=yes', '-o', 'ServerAliveInterval=30' }
    vim.list_extend(cmd, { '-L', ('127.0.0.1:%d:%s:%s'):format(pc.local_port, db_host, db_port) })
    if pc.ssh_port and pc.ssh_port ~= '' and pc.ssh_port ~= '22' then
      vim.list_extend(cmd, { '-p', pc.ssh_port })
    end
    if pc.ssh_key and pc.ssh_key ~= '' then
      vim.list_extend(cmd, { '-i', vim.fn.expand(pc.ssh_key) })
    end
    if proxy then
      local kind = pc.proxy_type == 'HTTP' and 'connect' or '5'
      vim.list_extend(cmd, { '-o', ('ProxyCommand=nc -X %s -x %s %%h %%p'):format(kind, proxy) })
    end
    table.insert(cmd, (pc.ssh_user ~= '' and pc.ssh_user .. '@' or '') .. pc.ssh_host)
    return cmd
  elseif proxy then
    local inner = ('ncat --proxy %s --proxy-type %s'):format(proxy, pc.proxy_type == 'HTTP' and 'http' or 'socks5')
    if pc.proxy_user and pc.proxy_user ~= '' then
      inner = inner .. ' --proxy-auth ' .. vim.fn.shellescape(pc.proxy_user .. ':' .. (pc.proxy_password or ''))
    end
    return { 'ncat', '-lk', '127.0.0.1', tostring(pc.local_port), '--sh-exec', ('%s %s %s'):format(inner, db_host, db_port) }
  end
end

--- Starts the tunnel of a connection entry ({ name, url, pc }) if it has one and it is not up;
--- returns true when the connection can be used, or false + error
--- restart = true: the settings changed (Test Connection in the dialog), replace a running tunnel
function M.ensure(entry, restart)
  local pc = entry and entry.pc
  if not pc or not pc.local_port or not (pc.ssh or pc.proxy) then
    return true
  end
  if restart and jobs[pc.local_port] then
    pcall(vim.fn.jobstop, jobs[pc.local_port])
    jobs[pc.local_port] = nil
    vim.wait(2000, function()
      return not listening(pc.local_port)
    end, 100)
  end
  if listening(pc.local_port) then
    if restart then
      return false, ('local port %d is used by another program'):format(pc.local_port)
    end
    return true
  end
  local cmd = M.command(pc)
  if not cmd or vim.fn.executable(cmd[1]) == 0 then
    return false, (cmd and cmd[1] or 'tunnel') .. ' is not installed'
  end
  local stderr = {}
  local job = vim.fn.jobstart(cmd, {
    on_stderr = function(_, data)
      vim.list_extend(stderr, data)
    end,
    on_exit = function()
      jobs[pc.local_port] = nil
    end,
  })
  jobs[pc.local_port] = job
  local up = vim.wait(8000, function()
    return listening(pc.local_port) or vim.fn.jobwait({ job }, 0)[1] ~= -1
  end, 200) and listening(pc.local_port)
  if not up then
    pcall(vim.fn.jobstop, job)
    return false, ('tunnel for %s did not start: %s'):format(entry.name, vim.trim(table.concat(stderr, ' ')))
  end
  return true
end

function M.stop_all()
  for _, job in pairs(jobs) do
    pcall(vim.fn.jobstop, job)
  end
  jobs = {}
end

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = vim.api.nvim_create_augroup('pc-db-tunnels', { clear = true }),
  callback = M.stop_all,
})

return M
