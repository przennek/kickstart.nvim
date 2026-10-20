-- AWS Explorer like the AWS Toolkit's tool window, for the profile / region chosen in <leader>A:
--   :AwsExplorer, or "Explorer" in the <leader>A menu   window on the left with
--     S3                buckets → folders → objects; Enter opens an object read-only, d downloads it
--     CloudWatch Logs   log groups; Enter tails the last hour in the Run window and follows new
--                       events, f asks for a filter pattern first
--     Lambda            functions; Enter shows the configuration, Enter on "logs" tails its log group
--   Enter / o expand · R reload the node · y copy name / S3 URI · q close
-- Everything goes through the aws CLI (read-only calls), in the background.

local M = {}

local win = { win = nil, buf = nil }
local roots
local rows = {} -- line → node

local function aws(args, callback)
  local cmd = vim.list_extend({ 'aws' }, args)
  vim.list_extend(cmd, { '--output', 'json', '--no-cli-pager' })
  vim.system(cmd, { text = true }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then
        return callback(nil, vim.trim(r.stderr ~= '' and r.stderr or r.stdout or 'failed'):match '[^\n]*$')
      end
      local ok, data = pcall(vim.json.decode, r.stdout ~= '' and r.stdout or 'null')
      callback(ok and data or nil, not ok and 'unreadable answer' or nil)
    end)
  end)
end

local function human(size)
  for _, unit in ipairs { 'B', 'KB', 'MB', 'GB' } do
    if size < 1024 or unit == 'GB' then
      return unit == 'B' and ('%d B'):format(size) or ('%.1f %s'):format(size, unit)
    end
    size = size / 1024
  end
end

local function window_open()
  return win.win and vim.api.nvim_win_is_valid(win.win)
end

local render

-- Children loaders: call done(children) or done(nil, error)
local LOAD = {}

function LOAD.s3(_, done)
  aws({ 's3api', 'list-buckets' }, function(data, err)
    if not data then
      return done(nil, err)
    end
    done(vim.tbl_map(function(b)
      return { kind = 'prefix', label = b.Name, bucket = b.Name, prefix = '', icon = '󰆼' }
    end, data.Buckets or {}))
  end)
end

function LOAD.prefix(node, done)
  aws({ 's3api', 'list-objects-v2', '--bucket', node.bucket, '--delimiter', '/', '--prefix', node.prefix }, function(data, err)
    if not data then
      return done(nil, err)
    end
    local children = {}
    for _, p in ipairs(data.CommonPrefixes or {}) do
      table.insert(children, { kind = 'prefix', label = p.Prefix:sub(#node.prefix + 1), bucket = node.bucket, prefix = p.Prefix, icon = '' })
    end
    for _, o in ipairs(data.Contents or {}) do
      if o.Key ~= node.prefix then
        table.insert(children, { kind = 'object', label = o.Key:sub(#node.prefix + 1), detail = human(o.Size or 0), bucket = node.bucket, key = o.Key, icon = '󰈔' })
      end
    end
    done(children)
  end)
end

function LOAD.logs(_, done)
  aws({ 'logs', 'describe-log-groups' }, function(data, err)
    if not data then
      return done(nil, err)
    end
    done(vim.tbl_map(function(g)
      return { kind = 'loggroup', label = g.logGroupName, group = g.logGroupName, detail = g.storedBytes and human(g.storedBytes), icon = '󰦨' }
    end, data.logGroups or {}))
  end)
end

function LOAD.lambda(_, done)
  aws({ 'lambda', 'list-functions' }, function(data, err)
    if not data then
      return done(nil, err)
    end
    done(vim.tbl_map(function(f)
      return {
        kind = 'function',
        label = f.FunctionName,
        detail = f.Runtime,
        config = f,
        icon = '󰘧',
        children = {
          { kind = 'loggroup', label = 'logs', group = '/aws/lambda/' .. f.FunctionName, icon = '󰦨' },
        },
      }
    end, data.Functions or {}))
  end)
end

local function expand(node)
  if node.children or not LOAD[node.kind] then
    node.open = not node.open
    return render()
  end
  node.open, node.loading = true, true
  render()
  LOAD[node.kind](node, function(children, err)
    node.loading = false
    node.children = children or {}
    node.error = err
    render()
  end)
end

local function open_object(node)
  local name = ('s3://%s/%s'):format(node.bucket, node.key)
  vim.system({ 'aws', 's3', 'cp', name, '-' }, {}, function(r)
    vim.schedule(function()
      if r.code ~= 0 then
        return vim.notify(name .. ': ' .. vim.trim(r.stderr or ''), vim.log.levels.ERROR)
      end
      vim.cmd 'wincmd l'
      vim.cmd 'enew'
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(r.stdout or '', '\n', { plain = true }))
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.bo[buf].modifiable = false
      pcall(vim.api.nvim_buf_set_name, buf, name)
      local ft = vim.filetype.match { filename = node.key }
      if ft then
        vim.bo[buf].filetype = ft
      end
    end)
  end)
end

local function tail(group, filter)
  local cmd = { 'aws', 'logs', 'tail', vim.fn.shellescape(group), '--since', '1h', '--follow', '--format', 'short' }
  if filter and filter ~= '' then
    vim.list_extend(cmd, { '--filter-pattern', vim.fn.shellescape(filter) })
  end
  require('pc.run').run_in_console(table.concat(cmd, ' '))
end

local function activate(node, filter_first)
  if node.kind == 'object' then
    open_object(node)
  elseif node.kind == 'loggroup' then
    if filter_first then
      local ok, filter = pcall(vim.fn.input, 'Filter pattern: ')
      if ok then
        tail(node.group, filter)
      end
    else
      tail(node.group)
    end
  elseif node.kind == 'function' and node.open then
    vim.lsp.util.open_floating_preview(vim.split(vim.inspect(node.config), '\n'), 'lua', { border = 'rounded', title = ' ' .. node.label .. ' ' })
  else
    expand(node)
  end
end

render = function()
  if not (win.buf and vim.api.nvim_buf_is_valid(win.buf)) then
    return
  end
  local lines, hl = {}, {}
  rows = {}
  local header = (' AWS · %s · %s'):format(vim.env.AWS_PROFILE or 'default', vim.env.AWS_REGION or 'default region')
  table.insert(lines, header)
  table.insert(hl, { 0, 'Title' })
  local function walk(nodes, depth)
    for _, node in ipairs(nodes) do
      local arrow = (node.children or LOAD[node.kind]) and (node.open and '▾ ' or '▸ ') or '  '
      local text = string.rep('  ', depth) .. arrow .. (node.icon and node.icon .. ' ' or '') .. node.label
      if node.detail then
        text = text .. '  ' .. node.detail
      end
      table.insert(lines, text)
      rows[#lines] = node
      if node.open then
        if node.loading then
          table.insert(lines, string.rep('  ', depth + 1) .. '  loading…')
          table.insert(hl, { #lines - 1, 'Comment' })
        elseif node.error then
          table.insert(lines, string.rep('  ', depth + 1) .. '  ' .. node.error)
          table.insert(hl, { #lines - 1, 'DiagnosticError' })
        elseif node.children and #node.children == 0 then
          table.insert(lines, string.rep('  ', depth + 1) .. '  (empty)')
          table.insert(hl, { #lines - 1, 'Comment' })
        else
          walk(node.children or {}, depth + 1)
        end
      end
    end
  end
  walk(roots, 0)
  table.insert(lines, '')
  table.insert(lines, ' Enter open · f filter logs · d download · y copy · R reload · q close')
  table.insert(hl, { #lines - 1, 'Comment' })
  vim.bo[win.buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines)
  vim.bo[win.buf].modifiable = false
  local ns = vim.api.nvim_create_namespace 'pc-aws-explorer'
  vim.api.nvim_buf_clear_namespace(win.buf, ns, 0, -1)
  for _, h in ipairs(hl) do
    vim.hl.range(win.buf, ns, h[2], { h[1], 0 }, { h[1], -1 })
  end
end

local function node_at_cursor()
  return rows[vim.api.nvim_win_get_cursor(0)[1]]
end

function M.toggle()
  if window_open() then
    vim.api.nvim_win_close(win.win, true)
    return
  end
  roots = roots
    or {
      { kind = 's3', label = 'S3', icon = '󰏗' },
      { kind = 'logs', label = 'CloudWatch Logs', icon = '󰦨' },
      { kind = 'lambda', label = 'Lambda', icon = '󰘧' },
    }
  win.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.buf].filetype = 'pcawsexplorer'
  vim.bo[win.buf].bufhidden = 'wipe'
  vim.cmd 'topleft vsplit'
  win.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win.win, win.buf)
  vim.api.nvim_win_set_width(win.win, 45)
  for opt, value in pairs { number = false, relativenumber = false, signcolumn = 'no', winfixwidth = true, cursorline = true, wrap = false } do
    vim.wo[win.win][opt] = value
  end
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = win.buf, desc = desc })
  end
  local function with_node(fn)
    return function()
      local node = node_at_cursor()
      if node then
        fn(node)
      end
    end
  end
  map('<CR>', with_node(activate), 'Open')
  map('o', with_node(activate), 'Open')
  map('f', with_node(function(node)
    activate(node, true)
  end), 'Tail logs with a filter')
  map('R', with_node(function(node)
    node.children, node.error, node.open = nil, nil, false
    expand(node)
  end), 'Reload')
  map('y', with_node(function(node)
    local text = node.key and ('s3://%s/%s'):format(node.bucket, node.key) or node.prefix and ('s3://%s/%s'):format(node.bucket, node.prefix) or node.group or (node.config and node.config.FunctionArn) or node.label
    vim.fn.setreg('+', text)
    vim.notify('Copied ' .. text)
  end), 'Copy name')
  map('d', with_node(function(node)
    if node.kind ~= 'object' then
      return
    end
    local target = vim.fn.getcwd() .. '/' .. vim.fs.basename(node.key)
    vim.system({ 'aws', 's3', 'cp', ('s3://%s/%s'):format(node.bucket, node.key), target }, {}, function(r)
      vim.schedule(function()
        vim.notify(r.code == 0 and ('Downloaded ' .. target) or vim.trim(r.stderr or ''), r.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
      end)
    end)
  end), 'Download')
  map('q', M.toggle, 'Close')
  render()
end

--- After switching profile / region: the tree is reloaded
function M.reset()
  roots = nil
  if window_open() then
    M.toggle()
    M.toggle()
  end
end

vim.api.nvim_create_user_command('AwsExplorer', M.toggle, { desc = 'AWS Explorer' })

return M
