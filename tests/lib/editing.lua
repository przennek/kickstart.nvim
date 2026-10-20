-- Editing actions on OrderService.java: Move Statement moves whole statements (an if with its
-- block, a call chain), never a line into a block; a Javadoc stays with its method.
-- Prints OK / FAIL and quits.
local problems = {}
local function line(n)
  return vim.trim(vim.api.nvim_buf_get_lines(0, n - 1, n, false)[1] or '')
end
local function expect(what, got, want)
  if got ~= want then
    table.insert(problems, ('%s: got %q, wanted %q'):format(what, got, want))
  end
end
vim.treesitter.start()
local ms = require 'pc.move_statement'
vim.api.nvim_win_set_cursor(0, { 15, 8 }) -- if (spent…) {
ms.move(1)
expect('if down: return comes first', line(15), 'return BigDecimal.ZERO;')
expect('if down: the if with its block below', line(16), 'if (spent.compareTo(new BigDecimal("100")) > 0) {')
ms.move(-1)
expect('if up again', line(15), 'if (spent.compareTo(new BigDecimal("100")) > 0) {')
vim.api.nvim_win_set_cursor(0, { 12, 16 }) -- .filter(…) inside the declaration
ms.move(1)
expect('declaration down: the if comes first', line(11), 'if (spent.compareTo(new BigDecimal("100")) > 0) {')
expect('declaration down: whole chain moved', line(14), 'BigDecimal spent = orders.stream()')
ms.move(-1)
vim.api.nvim_win_set_cursor(0, { 10, 4 }) -- the method: its only member, stays
ms.move(-1)
expect('Javadoc stays above the method', line(9), '/** 5% off when at least 100 was spent in paid orders. */')
io.stdout:write((#problems == 0 and 'OK editing' or ('FAIL editing: ' .. table.concat(problems, '; '))) .. '\n')
vim.cmd 'qa!'
