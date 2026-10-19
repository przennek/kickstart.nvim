-- Merge conflicts like IDEA's Resolve Conflicts dialog:
--   <leader>vm      open the merge tool (Diffview: ours | result | theirs, conflicted files in the panel)
--   <leader>vx      continue the merge / rebase / cherry-pick / revert: files without conflict
--                   markers are marked resolved (git add), files with markers left are listed
--   <leader>vX      abort it
--   :ResolveSimpleConflicts   the magic wand: resolves the conflicts where only one side changed,
--                   both made the same change, or the changes touch different lines
-- In the merge tool (result window): ]x / [x next / previous conflict, <leader>ml accept left (ours),
-- <leader>mr accept right (theirs), <leader>mb base, <leader>ma both, <leader>mn none, the same in
-- capitals for the whole file, <leader>mm resolve simple conflicts.

local M = {}

local function git(root, args, stdin)
  local result = vim.system(vim.list_extend({ 'git', '-C', root }, args), { text = true, stdin = stdin }):wait()
  return result.code, result.stdout or '', result.stderr or ''
end

local function repo_root(path)
  local dir = path ~= '' and vim.fs.dirname(path) or vim.fn.getcwd()
  local code, out = git(dir, { 'rev-parse', '--show-toplevel' })
  return code == 0 and vim.trim(out) or nil
end

-- Conflict regions of a list of lines: { first, last, ours, base, theirs } (base = nil without diff3 markers)
local function parse(lines)
  local regions, cur, part = {}, nil, nil
  for i, line in ipairs(lines) do
    if line:match '^<<<<<<<' then
      cur, part = { first = i, ours = {}, theirs = {} }, 'ours'
    elseif cur and line:match '^|||||||' then
      cur.base, part = {}, 'base'
    elseif cur and line:match '^=======$' then
      part = 'theirs'
    elseif cur and line:match '^>>>>>>>' then
      cur.last = i
      table.insert(regions, cur)
      cur = nil
    elseif cur then
      table.insert(cur[part], line)
    end
  end
  return regions
end

local function same(a, b)
  return table.concat(a, '\n') == table.concat(b, '\n')
end

-- Common ancestors of conflicts written without a base section: git merge-file on the index stages
-- with diff3 markers; its regions are matched to the buffer's by their ours / theirs sides
local function fill_bases(path, regions)
  local root = repo_root(path)
  if not root then
    return
  end
  local rel = vim.fs.relpath(root, path) or path
  local tmp = vim.fn.tempname()
  local files = {}
  for stage, name in pairs { [1] = 'base', [2] = 'ours', [3] = 'theirs' } do
    local code, out = git(root, { 'show', (':%d:%s'):format(stage, rel) })
    files[name] = tmp .. '.' .. name
    vim.fn.writefile(vim.split(code == 0 and out or '', '\n', { plain = true }), files[name], 'b')
  end
  local _, out = git(root, { 'merge-file', '-p', '--diff3', files.ours, files.base, files.theirs })
  for _, f in pairs(files) do
    vim.fn.delete(f)
  end
  local with_base = parse(vim.split(out, '\n', { plain = true }))
  for _, r in ipairs(regions) do
    for _, b in ipairs(with_base) do
      if not r.base and b.base and same(r.ours, b.ours) and same(r.theirs, b.theirs) then
        r.base = b.base
        break
      end
    end
  end
end

-- Three-way merge of one conflict; nil when the two sides change the same lines
local function merge_region(r)
  if same(r.ours, r.theirs) then
    return r.ours
  end
  if not r.base then
    return nil
  end
  if same(r.base, r.ours) then
    return r.theirs
  end
  if same(r.base, r.theirs) then
    return r.ours
  end
  local base = table.concat(r.base, '\n') .. '\n'
  local hunks = {}
  for _, side in ipairs { r.ours, r.theirs } do
    local text = #side > 0 and table.concat(side, '\n') .. '\n' or ''
    for _, h in ipairs(vim.diff(base, text, { result_type = 'indices', algorithm = 'histogram' })) do
      local start, count = h[1], h[2]
      -- an insertion sits between base lines, a change covers them
      local lo, hi = start, start + count - 1
      if count == 0 then
        lo, hi = start + 0.5, start + 0.5
      end
      table.insert(hunks, { lo = lo, hi = hi, start = start, count = count, lines = vim.list_slice(side, h[3], h[3] + h[4] - 1) })
    end
  end
  table.sort(hunks, function(a, b)
    return a.lo < b.lo
  end)
  local merged, pos, prev = {}, 1, nil
  for _, h in ipairs(hunks) do
    if prev and h.lo <= prev.hi then
      if not (h.lo == prev.lo and h.hi == prev.hi and same(h.lines, prev.lines)) then
        return nil
      end
    else
      local upto = h.count == 0 and h.start or h.start - 1
      vim.list_extend(merged, r.base, pos, upto)
      vim.list_extend(merged, h.lines)
      pos = h.count == 0 and h.start + 1 or h.start + h.count
      prev = h
    end
  end
  vim.list_extend(merged, r.base, pos, #r.base)
  return merged
end

--- Resolves the simple conflicts in a buffer; returns resolved, total
function M.resolve_simple(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local regions = parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if #regions == 0 then
    vim.notify('No conflicts in this file', vim.log.levels.INFO)
    return 0, 0
  end
  if vim.iter(regions):any(function(r)
    return not r.base
  end) then
    fill_bases(vim.api.nvim_buf_get_name(buf), regions)
  end
  local resolved = 0
  for i = #regions, 1, -1 do
    local r = regions[i]
    local lines = merge_region(r)
    if lines then
      vim.api.nvim_buf_set_lines(buf, r.first - 1, r.last, false, lines)
      resolved = resolved + 1
    end
  end
  vim.notify(('Resolved %d of %d conflicts'):format(resolved, #regions), vim.log.levels.INFO)
  return resolved, #regions
end

-- What is in progress: { name, continue, abort } or nil
local function operation(root)
  local _, gitdir = git(root, { 'rev-parse', '--absolute-git-dir' })
  gitdir = vim.trim(gitdir)
  local function has(f)
    return vim.uv.fs_stat(gitdir .. '/' .. f) ~= nil
  end
  if has 'rebase-merge' or has 'rebase-apply' then
    return { name = 'rebase', continue = { 'rebase', '--continue' }, abort = { 'rebase', '--abort' } }
  elseif has 'MERGE_HEAD' then
    return { name = 'merge', continue = { 'commit', '--no-edit' }, abort = { 'merge', '--abort' } }
  elseif has 'CHERRY_PICK_HEAD' then
    return { name = 'cherry-pick', continue = { 'cherry-pick', '--continue' }, abort = { 'cherry-pick', '--abort' } }
  elseif has 'REVERT_HEAD' then
    return { name = 'revert', continue = { 'revert', '--continue' }, abort = { 'revert', '--abort' } }
  end
end

local function unmerged(root)
  local _, out = git(root, { 'diff', '--name-only', '--diff-filter=U' })
  return vim.tbl_filter(function(f)
    return f ~= ''
  end, vim.split(out, '\n'))
end

local function close_merge_tool()
  if package.loaded['diffview'] and require('diffview.lib').get_current_view() then
    vim.cmd 'DiffviewClose'
  end
end

local function reload_buffers()
  vim.cmd 'silent! checktime'
  if package.loaded['neogit'] then
    pcall(function()
      require('neogit').dispatch_refresh()
    end)
  end
end

function M.open()
  local root = repo_root(vim.api.nvim_buf_get_name(0))
  if not root then
    return vim.notify('Not in a git repository', vim.log.levels.WARN)
  end
  if #unmerged(root) == 0 then
    return vim.notify('No conflicts', vim.log.levels.INFO)
  end
  vim.cmd 'DiffviewOpen'
end

function M.continue()
  local root = repo_root(vim.api.nvim_buf_get_name(0))
  local op = root and operation(root)
  if not op then
    return vim.notify('No merge, rebase, cherry-pick or revert in progress', vim.log.levels.INFO)
  end
  vim.cmd 'silent! wall'
  local left = {}
  for _, f in ipairs(unmerged(root)) do
    local ok, lines = pcall(vim.fn.readfile, root .. '/' .. f)
    if ok and #parse(lines) > 0 then
      table.insert(left, f)
    else
      git(root, { 'add', '--', f })
    end
  end
  if #left > 0 then
    return vim.notify('Conflicts left in:\n  ' .. table.concat(left, '\n  '), vim.log.levels.WARN)
  end
  close_merge_tool()
  vim.env.GIT_EDITOR = 'true'
  local code, out, err = git(root, op.continue)
  vim.env.GIT_EDITOR = nil
  reload_buffers()
  local msg = vim.trim(err ~= '' and err or out)
  if code ~= 0 then
    -- the next commit of a rebase can conflict again
    if #unmerged(root) > 0 then
      vim.notify(op.name .. ': new conflicts', vim.log.levels.WARN)
      return M.open()
    end
    return vim.notify(op.name .. ' --continue: ' .. msg, vim.log.levels.ERROR)
  end
  vim.notify(op.name .. ' finished', vim.log.levels.INFO)
end

function M.abort()
  local root = repo_root(vim.api.nvim_buf_get_name(0))
  local op = root and operation(root)
  if not op then
    return vim.notify('No merge, rebase, cherry-pick or revert in progress', vim.log.levels.INFO)
  end
  if vim.fn.confirm('Abort the ' .. op.name .. '?', '&Abort\n&Cancel', 2) ~= 1 then
    return
  end
  close_merge_tool()
  local code, out, err = git(root, op.abort)
  reload_buffers()
  vim.notify(op.name .. (code == 0 and ' aborted' or ' --abort: ' .. vim.trim(err ~= '' and err or out)), code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
end

vim.api.nvim_create_user_command('ResolveSimpleConflicts', function()
  M.resolve_simple()
end, { desc = 'Resolve the conflicts where the changes do not overlap' })

return M
