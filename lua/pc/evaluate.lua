-- Evaluate Expression like IDEA's (Alt+F8 there, <leader>xe here) while debugging: a box at the
-- cursor (pc.input) with the word under it (or the selection) to edit, Enter evaluates it in the
-- current frame (result as an expandable tree, dap-ui), Esc closes; Up / Down go through the
-- expressions evaluated before.

local M = {}

--- The Evaluate box for the word under the cursor / the selection
function M.open()
  if not (package.loaded.dap and require('dap').session()) then
    return vim.notify('Evaluate: no debug session', vim.log.levels.WARN)
  end
  local word = vim.fn.expand '<cexpr>'
  local mode = vim.fn.mode()
  if mode:match '^[vV\22]' then
    -- the selection, on one line
    word = table.concat(vim.tbl_map(vim.trim, vim.fn.getregion(vim.fn.getpos 'v', vim.fn.getpos '.', { type = mode })), ' ')
    vim.cmd 'normal! \27'
  end
  require('pc.input').open({ title = 'Evaluate', default = word, history = 'evaluate' }, function(expression)
    if expression and vim.trim(expression) ~= '' then
      require('dapui').eval(vim.trim(expression), { enter = true })
    end
  end)
end

return M
