-- Project Structure like IDEA's (Ctrl+Alt+Shift+S, Settings → Project Structure, :ProjectStructure):
-- the project's SDK (a JDK from SDKMAN or /usr/lib/jvm) and its language level from pom.xml.
-- The chosen JDK becomes jdtls' default runtime for the project; jdtls restarts to pick it up.
-- Saved per project in .idea/nvim/project.json.

local M = {}

local DEFAULT = 'Default (SDKMAN current)'
local store = require 'pc.project_store'

local function settings(root)
  local values = store.get(root, 'project', 'pc_project.json')
  return type(values) == 'table' and values or {}
end

function M.root(buf)
  return vim.fs.root(buf or 0, { 'mvnw', 'gradlew', 'pom.xml', 'build.gradle', 'build.gradle.kts', 'settings.gradle', '.git' }) or vim.fn.getcwd()
end

--- The project's chosen JDK home, or nil for the default
function M.sdk(root)
  local sdk = settings(root).sdk
  return sdk and sdk ~= DEFAULT and sdk or nil
end

--- Major Java version of a JDK home (from its release file)
function M.java_version(home)
  local f = io.open(home .. '/release')
  if not f then
    return home:match '/(%d+)[^/]*$'
  end
  local text = f:read '*a'
  f:close()
  local v = text:match 'JAVA_VERSION="([^"]+)"'
  return v and (v:match '^1%.(%d+)' or v:match '^(%d+)')
end

--- Every installed JDK: SDKMAN candidates and /usr/lib/jvm
function M.jdks()
  local list = {}
  for _, dir in ipairs(vim.fn.glob(vim.env.HOME .. '/.sdkman/candidates/java/*', false, true)) do
    if not dir:match '/current$' then
      table.insert(list, dir)
    end
  end
  for _, dir in ipairs(vim.fn.glob('/usr/lib/jvm/*', false, true)) do
    if vim.uv.fs_stat(dir .. '/bin/javac') and not vim.uv.fs_lstat(dir).type:match 'link' then
      table.insert(list, dir)
    end
  end
  return list
end

local function language_level(root)
  local f = io.open(root .. '/pom.xml')
  if not f then
    return 'from the build file'
  end
  local pom = f:read '*a'
  f:close()
  local level = pom:match '<maven%.compiler%.release>%s*([^<]-)%s*<'
    or pom:match '<release>%s*([^<]-)%s*</release>'
    or pom:match '<maven%.compiler%.source>%s*([^<]-)%s*<'
    or pom:match '<source>%s*([^<]-)%s*</source>'
  return level and (level .. ' (pom.xml)') or 'Maven default (pom.xml)'
end

-- jdtls reads the runtimes when it starts: stop it and start it again for every Java buffer
function M.restart_jdtls()
  local buffers = {}
  for _, client in ipairs(vim.lsp.get_clients { name = 'jdtls' }) do
    for buf in pairs(client.attached_buffers) do
      table.insert(buffers, buf)
    end
    client:stop()
  end
  vim.defer_fn(function()
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_exec_autocmds('FileType', { buffer = buf, modeline = false })
      end
    end
  end, 1500)
  return #buffers > 0
end

function M.open()
  local root = M.root()
  local choices = vim.list_extend({ DEFAULT }, M.jdks())
  require('pc.form').open {
    title = 'Project Structure: ' .. vim.fs.basename(root),
    values = { sdk = settings(root).sdk or DEFAULT },
    fields = {
      { header = 'Project' },
      { key = 'sdk', label = 'SDK', choices = choices },
      { key = 'version', label = 'SDK version', readonly = true, value = function(v)
        local home = v.sdk ~= DEFAULT and v.sdk or vim.uv.fs_realpath(vim.env.HOME .. '/.sdkman/candidates/java/current') or vim.env.JAVA_HOME
        return home and ('Java ' .. (M.java_version(home) or '?')) or '?'
      end },
      { key = 'level', label = 'Language level', readonly = true, value = function()
        return language_level(root)
      end },
      { key = 'root', label = 'Project root', readonly = true, value = function()
        return vim.fn.fnamemodify(root, ':~')
      end },
    },
    buttons = {
      {
        label = 'OK',
        key = '<C-s>',
        run = function(values, form)
          store.set(root, 'project', { sdk = values.sdk }, 'pc_project.json')
          form:close()
          vim.notify('Project SDK: ' .. values.sdk .. (M.restart_jdtls() and ' (restarting jdtls)' or ''))
        end,
      },
    },
  }
end

vim.api.nvim_create_user_command('ProjectStructure', M.open, { desc = 'Project Structure (SDK)' })
vim.keymap.set('n', '<M-;>', M.open, { desc = 'Project Structure' })

return M
