-- Refactorings save the files they change, like IDEA: a rename, move or code action of a
-- language server edits files that may not even be open (they are loaded in the background);
-- left unsaved, git, Maven and the tests would still see the old code. Files that had unsaved
-- edits of yours before the refactoring are left unsaved.

local apply_workspace_edit = vim.lsp.util.apply_workspace_edit

vim.lsp.util.apply_workspace_edit = function(...)
  local dirty = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    dirty[buf] = vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified
  end
  local result = apply_workspace_edit(...)
  vim.schedule(function()
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
