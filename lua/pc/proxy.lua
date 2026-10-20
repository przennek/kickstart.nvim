-- HTTP Proxy settings like IDEA's (Settings → System Settings → HTTP Proxy), in a dialog (pc.form):
--   :ProxySettings / <leader>tp   No proxy, or a manual HTTP / SOCKS5 proxy with optional login and
--                                 hosts to bypass; Check connection (Ctrl+T) tries a URL through it
-- Applied to Neovim and everything it starts: http(s)_proxy / all_proxy / no_proxy (git, curl,
-- Mason, npm, pip…) and the Java proxy properties in MAVEN_OPTS / JAVA_TOOL_OPTIONS (Maven, jdtls;
-- language servers already running pick it up after a restart). Saved in stdpath('data')/pc_proxy.json.

local M = {}

local FILE = vim.fn.stdpath 'data' .. '/pc_proxy.json'
local VARS = { 'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'MAVEN_OPTS', 'JAVA_TOOL_OPTIONS' }

-- what the environment had before the first apply, to go back to with "No proxy"
local original

local function read()
  local f = io.open(FILE)
  if not f then
    return nil
  end
  local ok, cfg = pcall(vim.json.decode, f:read '*a')
  f:close()
  return ok and cfg or nil
end

local function write(cfg)
  local f = assert(io.open(FILE, 'w'))
  f:write(vim.json.encode(cfg))
  f:close()
  vim.uv.fs_chmod(FILE, tonumber('600', 8))
end

local function encode(s)
  return (s:gsub('[^%w%-%._~]', function(c)
    return ('%%%02X'):format(c:byte())
  end))
end

--- The proxy URL of the settings, or nil for No proxy
function M.url(cfg)
  if not cfg or cfg.mode ~= 'Manual' or (cfg.host or '') == '' then
    return nil
  end
  local auth = ''
  if (cfg.user or '') ~= '' then
    auth = encode(cfg.user) .. ((cfg.password or '') ~= '' and ':' .. encode(cfg.password) or '') .. '@'
  end
  local scheme = cfg.type == 'SOCKS5' and 'socks5h' or 'http'
  return ('%s://%s%s:%s'):format(scheme, auth, cfg.host, cfg.port)
end

local function java_options(cfg)
  local opts = {}
  local no_proxy = (cfg.no_proxy or ''):gsub('%s*,%s*', '|')
  if cfg.type == 'SOCKS5' then
    vim.list_extend(opts, { '-DsocksProxyHost=' .. cfg.host, '-DsocksProxyPort=' .. cfg.port })
  else
    for _, p in ipairs { 'http', 'https' } do
      vim.list_extend(opts, { ('-D%s.proxyHost=%s'):format(p, cfg.host), ('-D%s.proxyPort=%s'):format(p, cfg.port) })
    end
    if no_proxy ~= '' then
      table.insert(opts, '-Dhttp.nonProxyHosts=' .. no_proxy)
    end
  end
  return table.concat(opts, ' ')
end

function M.apply(cfg)
  if not original then
    original = {}
    for _, v in ipairs(VARS) do
      original[v] = vim.env[v]
    end
  end
  local url = M.url(cfg)
  for _, v in ipairs(VARS) do
    vim.env[v] = original[v]
  end
  if not url then
    return
  end
  for _, v in ipairs { 'http_proxy', 'https_proxy', 'all_proxy', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY' } do
    vim.env[v] = url
  end
  if (cfg.no_proxy or '') ~= '' then
    vim.env.no_proxy = cfg.no_proxy
    vim.env.NO_PROXY = cfg.no_proxy
  end
  for _, v in ipairs { 'MAVEN_OPTS', 'JAVA_TOOL_OPTIONS' } do
    vim.env[v] = vim.trim((vim.env[v] or '') .. ' ' .. java_options(cfg))
  end
end

function M.open()
  local manual = function(v)
    return v.mode == 'Manual'
  end
  require('pc.form').open {
    title = 'HTTP Proxy',
    values = read(),
    fields = {
      { key = 'mode', label = 'Proxy', choices = { 'No proxy', 'Manual' }, default = 'No proxy' },
      { key = 'type', label = 'Type', choices = { 'HTTP', 'SOCKS5' }, default = 'HTTP', visible = manual },
      { key = 'host', label = 'Host name', default = '', visible = manual },
      { key = 'port', label = 'Port', default = '8080', visible = manual },
      { key = 'no_proxy', label = 'No proxy for', default = 'localhost,127.0.0.1', visible = manual },
      { header = 'Authentication', visible = manual },
      { key = 'user', label = 'Login', default = '', visible = manual },
      { key = 'password', label = 'Password', secret = true, default = '', visible = manual },
      { header = 'Check connection', visible = manual },
      { key = 'check_url', label = 'URL', default = 'https://github.com', visible = manual },
    },
    on_change = function(values, key)
      if key == 'type' then
        values.port = values.type == 'SOCKS5' and '1080' or '8080'
      end
    end,
    buttons = {
      {
        label = 'Check connection',
        key = '<C-t>',
        run = function(values, form)
          local url = M.url(values)
          local cmd = { 'curl', '-sS', '-o', '/dev/null', '-w', '%{http_code}', '--max-time', '10' }
          vim.list_extend(cmd, url and { '--proxy', url } or { '--noproxy', '*' })
          table.insert(cmd, values.check_url or 'https://github.com')
          form:say 'Checking…'
          vim.system(cmd, { text = true }, function(r)
            vim.schedule(function()
              local ok = r.code == 0 and tonumber(r.stdout) and tonumber(r.stdout) < 500
              form:say(ok and ('Connection successful (HTTP %s)'):format(r.stdout) or ('Connection failed: ' .. vim.trim(r.stderr ~= '' and r.stderr or r.stdout)), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
            end)
          end)
        end,
      },
      {
        label = 'OK',
        key = '<C-s>',
        run = function(values, form)
          write(values)
          M.apply(values)
          form:close()
          vim.notify(M.url(values) and ('Proxy: %s:%s (restart language servers to use it)'):format(values.host, values.port) or 'Proxy: none')
        end,
      },
    },
  }
end

vim.api.nvim_create_user_command('ProxySettings', M.open, { desc = 'HTTP Proxy settings' })
vim.keymap.set('n', '<leader>tp', M.open, { desc = '[T]oggle / settings: HTTP [p]roxy' })

-- saved settings apply from the start, before plugins and servers spawn anything
M.apply(read())

return M
