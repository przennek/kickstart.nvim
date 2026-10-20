-- Copy Reference / Copy Path like IDEA's:
--   <leader>yr      Copy Reference: Java pl.pkg.Class#method, Python pkg.module.Class.method,
--                   elsewhere path:line
--   Alt+Shift+C / <leader>yp   Copy Path/Reference… popup: reference, absolute path, path from
--                   the project root, file name, path:line, and the web URL of the line when the
--                   file is in a git repository with a GitHub / GitLab / Bitbucket remote

local M = {}

local function project_root()
  return vim.fs.root(0, { '.git', 'pom.xml', 'build.gradle', 'pyproject.toml', 'package.json', 'Makefile' }) or vim.fn.getcwd()
end

local function relative()
  return vim.fs.relpath(project_root(), vim.api.nvim_buf_get_name(0)) or vim.fn.expand '%:.'
end

-- Names of the enclosing nodes of the given types, outermost first
local function enclosing_names(types)
  local ok, node = pcall(vim.treesitter.get_node)
  local names = {}
  while ok and node do
    if types[node:type()] then
      local name = node:field('name')[1]
      if name then
        table.insert(names, 1, vim.treesitter.get_node_text(name, 0))
      end
    end
    node = node:parent()
  end
  return names
end

local function java_reference()
  local package
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, 50, false)) do
    package = package or line:match '^%s*package%s+([%w_.]+)%s*;'
  end
  local classes = enclosing_names { class_declaration = true, interface_declaration = true, enum_declaration = true, record_declaration = true }
  local method = enclosing_names({ method_declaration = true, constructor_declaration = true })[1]
  if #classes == 0 then
    classes = { vim.fn.expand '%:t:r' }
  end
  local ref = (package and package .. '.' or '') .. table.concat(classes, '.')
  return method and (ref .. '#' .. method) or ref
end

local function python_reference()
  local root = vim.fs.root(0, { 'pyproject.toml', 'setup.py', 'setup.cfg' }) or project_root()
  local path = vim.fs.relpath(root, vim.api.nvim_buf_get_name(0)) or relative()
  local module = path:gsub('%.py$', ''):gsub('/__init__$', ''):gsub('^src/', ''):gsub('/', '.')
  local names = enclosing_names { class_definition = true, function_definition = true }
  return #names > 0 and (module .. '.' .. table.concat(names, '.')) or module
end

function M.reference()
  local ft = vim.bo.filetype
  if ft == 'java' then
    return java_reference()
  elseif ft == 'python' then
    return python_reference()
  end
  return relative() .. ':' .. vim.fn.line '.'
end

-- https://host/owner/repo/blob/<commit>/<path>#L<line> for the usual hosts
local function web_url()
  local file = vim.api.nvim_buf_get_name(0)
  local dir = vim.fs.dirname(file)
  local function git(args)
    local r = vim.system(vim.list_extend({ 'git', '-C', dir }, args), { text = true }):wait()
    return r.code == 0 and vim.trim(r.stdout) or nil
  end
  local remote = git { 'remote', 'get-url', 'origin' }
  local root = git { 'rev-parse', '--show-toplevel' }
  local commit = git { 'rev-parse', 'HEAD' }
  if not (remote and root and commit) then
    return nil
  end
  local host, path = remote:match '^git@([^:]+):(.-)%.git$'
  if not host then
    host, path = remote:match '^https?://[^@]*@?([^/]+)/(.-)%.git$'
  end
  if not host then
    host, path = remote:match '^https?://([^/]+)/(.-)/?$'
  end
  if not host then
    return nil
  end
  local rel = vim.fs.relpath(root, file)
  local line = vim.fn.line '.'
  if host:find 'gitlab' then
    return ('https://%s/%s/-/blob/%s/%s#L%d'):format(host, path, commit, rel, line)
  elseif host:find 'bitbucket' then
    return ('https://%s/%s/src/%s/%s#lines-%d'):format(host, path, commit, rel, line)
  end
  return ('https://%s/%s/blob/%s/%s#L%d'):format(host, path, commit, rel, line)
end

local function copy(text)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify('Copied ' .. text)
end

function M.copy_reference()
  copy(M.reference())
end

function M.popup()
  local file = vim.api.nvim_buf_get_name(0)
  local items = {
    { label = 'Reference', value = M.reference() },
    { label = 'Absolute Path', value = file },
    { label = 'Path From Project Root', value = relative() },
    { label = 'File Name', value = vim.fs.basename(file) },
    { label = 'Path:Line', value = relative() .. ':' .. vim.fn.line '.' },
  }
  local url = web_url()
  if url then
    table.insert(items, { label = 'Web URL (this commit)', value = url })
  end
  vim.ui.select(items, {
    prompt = 'Copy Path/Reference',
    format_item = function(item)
      return ('%-24s %s'):format(item.label, item.value)
    end,
  }, function(item)
    if item then
      copy(item.value)
    end
  end)
end

vim.keymap.set('n', '<leader>yr', M.copy_reference, { desc = 'Copy [r]eference' })
vim.keymap.set('n', '<leader>yp', M.popup, { desc = 'Copy [p]ath / reference…' })
vim.keymap.set('n', '<M-C>', M.popup, { desc = 'Copy Path/Reference…' })

return M
