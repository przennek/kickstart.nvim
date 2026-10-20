-- "ft:name | *current … mode=x" of the current tab, for the scenario log
local out = {}
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local b = vim.api.nvim_win_get_buf(w)
  table.insert(out, ('%s%s:%s'):format(w == vim.api.nvim_get_current_win() and '*' or '', vim.bo[b].filetype, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':t')))
end
return table.concat(out, ' | ') .. ' mode=' .. vim.api.nvim_get_mode().mode
