-- Refactorings save the files they change, like IDEA: a rename, move or code action of a
-- language server edits files that may not even be open (they are loaded in the background);
-- left unsaved, git, Maven and the tests would still see the old code. Files that had unsaved
-- edits of yours before the refactoring are left unsaved.
-- Files a refactoring creates or renames (Rename of a class renames its file) are added to git
-- (intent to add) when the project is a git repository, as IDEA adds them to VCS: otherwise a
-- commit would take the deletion of Order.java but not the new PurchaseOrder.java.

local apply_workspace_edit = vim.lsp.util.apply_workspace_edit

-- the files an edit creates or renames to (paths), and of renames whether the old one was in git
local function new_files(edit)
  local files = {}
  for _, change in ipairs(edit and edit.documentChanges or {}) do
    if change.kind == 'rename' and change.newUri then
      table.insert(files, { path = vim.uri_to_fname(change.newUri), old = vim.uri_to_fname(change.oldUri) })
    elseif change.kind == 'create' and change.uri then
      table.insert(files, { path = vim.uri_to_fname(change.uri) })
    end
  end
  return files
end

local function git(dir, args)
  local r = vim.system(vim.list_extend({ 'git', '-C', dir }, args), { text = true }):wait()
  return r.code == 0, vim.trim(r.stdout or '')
end

-- before the edit: was the old file of each rename tracked?
local function tracked(file)
  local dir = vim.fs.dirname(file)
  return vim.uv.fs_stat(dir) ~= nil and (git(dir, { 'ls-files', '--error-unmatch', '--', file }))
end

local function add_to_git(files)
  for _, f in ipairs(files) do
    local dir = vim.fs.dirname(f.path)
    if vim.uv.fs_stat(f.path) and (f.old == nil or f.was_tracked) and git(dir, { 'rev-parse', '--is-inside-work-tree' }) then
      local ignored = git(dir, { 'check-ignore', '-q', '--', f.path })
      if not ignored and not git(dir, { 'ls-files', '--error-unmatch', '--', f.path }) then
        git(dir, { 'add', '--intent-to-add', '--', f.path })
      end
    end
  end
end

vim.lsp.util.apply_workspace_edit = function(edit, ...)
  local created = new_files(edit)
  for _, f in ipairs(created) do
    f.was_tracked = f.old and tracked(f.old)
  end
  local dirty = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    dirty[buf] = vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified
  end
  local result = apply_workspace_edit(edit, ...)
  vim.schedule(function()
    if #created > 0 then
      add_to_git(created)
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if not dirty[buf] and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified and vim.bo[buf].buftype == '' and vim.api.nvim_buf_get_name(buf) ~= '' then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd 'silent! update'
        end)
      end
    end
  end)
  return result
end
