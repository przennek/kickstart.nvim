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

-- Moves a file and lets the servers rewrite the imports (workspace/willRenameFiles)
function M.move_file(old, new)
  old, new = vim.fn.fnamemodify(old, ':p'), vim.fn.fnamemodify(new, ':p')
  if old == new then
    return
  end
  if vim.uv.fs_stat(new) then
    return vim.notify('Move: ' .. relative(new) .. ' already exists', vim.log.levels.WARN)
  end
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
  vim.fn.mkdir(vim.fs.dirname(new), 'p')
  vim.lsp.util.rename(old, new)
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client:supports_method 'workspace/didRenameFiles' then
      client:notify('workspace/didRenameFiles', params)
    end
  end
  -- files whose imports changed are saved, like IDEA does after a refactoring
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

-- jdtls applies the Move's edits to buffers; save them afterwards like IDEA does
local save_after_edit = 0
local apply_workspace_edit = vim.lsp.util.apply_workspace_edit
vim.lsp.util.apply_workspace_edit = function(...)
  local result = apply_workspace_edit(...)
  if vim.uv.now() < save_after_edit then
    save_after_edit = 0
    vim.schedule(function()
      vim.cmd 'silent! wall'
    end)
  end
  return result
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
        -- the package / class prompt can take a while
        save_after_edit = vim.uv.now() + 120000
        vim.lsp.buf.code_action { filter = is_move, apply = true }
      else
        -- nothing to move under the cursor: the file itself (jdtls updates package and imports)
        prompt_file()
      end
    end)
  end)
end

return M
