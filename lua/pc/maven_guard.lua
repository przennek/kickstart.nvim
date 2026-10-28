-- jdtls stays out of a Maven build: jdtls (m2e) builds into the same target/classes and
-- target/test-classes as Maven, and rebuilt / deleted classes mid-build when `./mvnw clean test`
-- ran in the terminal (NoClassDefFoundError, "package … does not exist" at random). While a Maven
-- process started from this Neovim runs (terminal, Run window), jdtls' auto-build is off; after
-- it, on again. Completion, go to definition and diagnostics of open files keep working.
-- `ps` instead of /proc, so it works on macOS too.

local M = {}

local INTERVAL = 1000
local paused = false
local timer

-- mvn / mvnw as the program or the script a shell runs (`/bin/sh ./mvnw test`), or Maven's JVM
local function maven(command)
  local first, second = command:match '^(%S+)%s*(%S*)'
  for _, word in ipairs { first or '', second or '' } do
    local name = word:match '[^/]+$'
    if name == 'mvn' or name == 'mvnw' or name == 'mvnDebug' then
      return true
    end
  end
  return command:match 'plexus%-classworlds' ~= nil or command:match 'maven%-wrapper' ~= nil
end

--- Is a Maven process a descendant of this Neovim? (`ps` output: "pid ppid command" lines)
function M.maven_running(ps_output)
  local parent, nvim = {}, vim.fn.getpid()
  local candidates = {}
  for line in ps_output:gmatch '[^\n]+' do
    local pid, ppid, command = line:match '^%s*(%d+)%s+(%d+)%s+(.*)$'
    if pid then
      parent[tonumber(pid)] = tonumber(ppid)
      if maven(command) then
        table.insert(candidates, tonumber(pid))
      end
    end
  end
  for _, pid in ipairs(candidates) do
    local p, depth = parent[pid], 0
    while p and p > 1 and depth < 32 do
      if p == nvim then
        return true
      end
      p, depth = parent[p], depth + 1
    end
  end
  return false
end

local function jdtls_clients()
  return vim.lsp.get_clients { name = 'jdtls' }
end

local function set_autobuild(enabled)
  for _, client in ipairs(jdtls_clients()) do
    client.settings = vim.tbl_deep_extend('force', client.settings or {}, { java = { autobuild = { enabled = enabled } } })
    client:notify('workspace/didChangeConfiguration', { settings = client.settings })
  end
end

local function check()
  if #jdtls_clients() == 0 then
    paused = false
    return
  end
  vim.system({ 'ps', 'axo', 'pid=,ppid=,command=' }, { text = true }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        return
      end
      local running = M.maven_running(out.stdout or '')
      if running == paused then
        return
      end
      paused = running
      set_autobuild(not running)
      vim.notify(running and 'Maven build running: jdtls auto-build paused' or 'Maven build done: jdtls auto-build on again', vim.log.levels.DEBUG, { title = 'jdtls' })
    end)
  end)
end

function M.paused()
  return paused
end

function M.start()
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  timer:start(INTERVAL, INTERVAL, vim.schedule_wrap(check))
end

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('pc-maven-guard', { clear = true }),
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client.name == 'jdtls' then
      M.start()
      -- a jdtls (re)started during a build starts paused too
      if paused then
        set_autobuild(false)
      end
    end
  end,
})

return M
