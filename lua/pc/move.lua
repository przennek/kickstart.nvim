-- Refactor → Move (F6), like IDEA:
--   Java      jdtls' own Move: on a class name → another package (references and package lines
--             updated), on a static member → another class, on an instance method → a field's type
--   elsewhere move / rename the file to a new path; language servers that support it update the
--             imports (ts_ls: only in files of its project, so with a jsconfig/tsconfig.json)
-- In the file tree (neo-tree) the same is m.

local M = {}

local function relative(path)
  return vim.fn.fnamemodify(path, ':.')
end

-- Before a file / directory is renamed or moved: the language servers' edits for it (imports,
-- Java: the class of X.java and its uses), applied and saved; the number of files edited
function M.will_rename(old, new)
  local params = { files = { { oldUri = vim.uri_from_fname(old), newUri = vim.uri_from_fname(new) } } }
  local edits = 0
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client:supports_method 'workspace/willRenameFiles' then
      local resp = client:request_sync('workspace/willRenameFiles', params, 3000)
      if resp and resp.result then
        vim.lsp.util.apply_workspace_edit(resp.result, client.offset_encoding)
        edits = edits + vim.tbl_count(resp.result.changes or resp.result.documentChanges or {})
      end
    end
  end
  -- saved now, before the file moves away under its buffer (like IDEA after a refactoring)
  if edits > 0 then
    vim.cmd 'silent! wall'
  end
  return edits
end

--- After the rename / move: the servers are told; the moved file's own buffer is saved (the
--- servers' edits to it, e.g. the renamed class, reached it while it was being moved) and gets
--- its filetype back
function M.did_rename(old, new)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and (name == new or vim.startswith(name, new .. '/')) then
      vim.api.nvim_buf_call(buf, function()
        if vim.bo.modified then
          vim.cmd 'silent! update'
        end
        -- the tree renames the buffer without filetype detection: no highlighting, no server
        if vim.bo.filetype == '' then
          vim.cmd 'filetype detect'
        end
      end)
    end
  end
  local params = { files = { { oldUri = vim.uri_from_fname(old), newUri = vim.uri_from_fname(new) } } }
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client:supports_method 'workspace/didRenameFiles' then
      client:notify('workspace/didRenameFiles', params)
    end
  end
end

--- A .java file moved to another package directory (the tree's m): jdtls' Move refactoring, as
--- in IDEA - the package line and the imports of its users change (willRenameFiles has nothing
--- for that). A new directory is created first; jdtls sees it as a package within seconds.
--- true when done (the file is moved by the refactoring itself)
function M.java_move(source, dest)
  local client = vim.lsp.get_clients({ name = 'jdtls' })[1]
  if not client or not source:match '%.java$' or vim.fs.basename(source) ~= vim.fs.basename(dest) or vim.fs.dirname(source) == vim.fs.dirname(dest) then
    return false
  end
  local dir = vim.fs.dirname(dest)
  vim.fn.mkdir(dir, 'p')
  local uri = vim.uri_from_fname(source)
  local target
  -- destinations are workspace paths (/<project>/src/main/java/a/b): the end of the directory
  vim.wait(8000, function()
    local resp = client:request_sync('java/getMoveDestinations', { moveKind = 'moveResource', sourceUris = { uri }, params = vim.NIL }, 3000)
    for _, d in ipairs(resp and resp.result and resp.result.destinations or {}) do
      local tail = d.path:gsub('^/[^/]+', '')
      if tail ~= '' and vim.endswith(dir, tail) and not d.isDefaultPackage then
        target = d
      end
    end
    return target ~= nil
  end, 500)
  if not target then
    return false
  end
  local resp = client:request_sync('java/move', { moveKind = 'moveResource', sourceUris = { uri }, params = vim.NIL, destination = target, updateReferences = true }, 15000)
  local result = resp and resp.result
  if not result or result.errorMessage or not result.edit then
    vim.notify('Move: ' .. (result and result.errorMessage or (resp and resp.err and resp.err.message) or 'jdtls did not answer'), vim.log.levels.WARN)
    return false
  end
  vim.lsp.util.apply_workspace_edit(result.edit, client.offset_encoding)
  vim.cmd 'silent! wall'
  vim.notify(('Moved %s to package %s'):format(vim.fs.basename(source), target.displayName))
  return true
end

-- Moves a file and lets the servers rewrite the imports (workspace/willRenameFiles)
function M.move_file(old, new)
  old, new = vim.fn.fnamemodify(old, ':p'), vim.fn.fnamemodify(new, ':p')
  if old == new then
    return
  end
  if vim.uv.fs_stat(new) then
    return vim.notify('Move: ' .. relative(new) .. ' already exists', vim.log.levels.WARN)
  end
  local edits = M.will_rename(old, new)
  vim.fn.mkdir(vim.fs.dirname(new), 'p')
  require('pc.git_track').move(old, new, function()
    vim.lsp.util.rename(old, new)
  end)
  M.did_rename(old, new)
  vim.cmd 'silent! wall'
  vim.notify(('Moved to %s%s'):format(relative(new), edits > 0 and (' (%d files updated)'):format(edits) or ''))
end

local function prompt_file()
  local old = vim.api.nvim_buf_get_name(0)
  if old == '' then
    return
  end
  vim.ui.input({ prompt = 'Move file to: ', default = relative(old), completion = 'file' }, function(new)
    if new and vim.trim(new) ~= '' then
      -- a directory keeps the file name
      if new:match '/$' or vim.fn.isdirectory(new) == 1 then
        new = (new:match '/$' and new or new .. '/') .. vim.fs.basename(old)
      end
      M.move_file(old, new)
    end
  end)
end

function M.move()
  local java = vim.lsp.get_clients({ bufnr = 0, name = 'jdtls' })[1]
  if not java then
    return prompt_file()
  end
  local function is_move(action)
    return action.title:match '^Move' ~= nil
  end
  local params = vim.lsp.util.make_range_params(0, java.offset_encoding)
  params.context = { diagnostics = {} }
  java:request('textDocument/codeAction', params, function(_, actions)
    vim.schedule(function()
      if vim.iter(actions or {}):any(is_move) then
        -- the files it changes are saved by pc.refactor_save
        vim.lsp.buf.code_action { filter = is_move, apply = true }
      else
        -- nothing to move under the cursor: the file itself (jdtls updates package and imports)
        prompt_file()
      end
    end)
  end)
end

return M
