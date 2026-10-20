-- Move Statement Up / Down (Alt+Shift+↑ / ↓) like IDEA: the whole statement the cursor is in
-- (a multi-line call chain, an if with its block, a method…) swaps places with the statement
-- next to it; at the edge of a block nothing moves (code never ends up half inside a block).
-- Without a treesitter parser the line moves (Move Line), as do selections.

local M = {}

local function is_comment(node)
  return node:type():match 'comment' ~= nil
end

-- statements, declarations and definitions: the units that move (a comment right above one,
-- e.g. a Javadoc, moves with it)
local function movable(node)
  local t = node:type()
  return t:match 'statement' or t:match 'declaration' or t:match 'definition' or t == 'decorated_definition'
end

-- the innermost movable node around the cursor's first character whose siblings are units too
local function statement_at_cursor()
  local row = vim.fn.line '.' - 1
  -- the tree of the text as it is now (the last move changed it)
  local has_parser, parser = pcall(vim.treesitter.get_parser)
  if not has_parser or not parser then
    return nil
  end
  parser:parse()
  local ok, node = pcall(vim.treesitter.get_node, { pos = { row, math.max(vim.fn.indent '.', 0) } })
  if not ok then
    return nil
  end
  while node do
    if movable(node) and node:parent() then
      return node
    end
    node = node:parent()
  end
end

local function sibling(node, dir)
  local next = dir > 0 and node:next_named_sibling() or node:prev_named_sibling()
  while next and not movable(next) do
    next = dir > 0 and next:next_named_sibling() or next:prev_named_sibling()
  end
  return next
end

-- the lines of a unit: its own, plus the comments right above it (no blank line between)
local function rows(node)
  local sr, _, er, ec = node:range()
  -- a range ending at column 0 ends on the line before
  if ec == 0 and er > sr then
    er = er - 1
  end
  local prev = node:prev_named_sibling()
  while prev and is_comment(prev) and select(3, prev:range()) >= sr - 1 do
    sr = prev:range()
    prev = prev:prev_named_sibling()
  end
  return sr, er
end

function M.move(dir)
  local node = statement_at_cursor()
  if not node then
    return vim.cmd(dir > 0 and 'move .+1' or 'move .-2')
  end
  local other = sibling(node, dir)
  if not other then
    return -- first / last statement of its block: stays (IDEA moves it out of the block)
  end
  local first, second = node, other
  if dir < 0 then
    first, second = other, node
  end
  local a1, a2 = rows(first)
  local b1, b2 = rows(second)
  if a2 >= b1 then
    return -- on one line: nothing sensible to swap
  end
  local buf = vim.api.nvim_get_current_buf()
  local a = vim.api.nvim_buf_get_lines(buf, a1, a2 + 1, false)
  local gap = vim.api.nvim_buf_get_lines(buf, a2 + 1, b1, false)
  local b = vim.api.nvim_buf_get_lines(buf, b1, b2 + 1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local offset = cursor[1] - 1 - select(1, rows(node))
  vim.api.nvim_buf_set_lines(buf, a1, b2 + 1, false, vim.list_extend(vim.list_extend(vim.list_extend({}, b), gap), a))
  -- the moved statement starts where the other one did
  local start = dir > 0 and (a1 + #b + #gap) or a1
  vim.api.nvim_win_set_cursor(0, { start + offset + 1, cursor[2] })
end

return M
