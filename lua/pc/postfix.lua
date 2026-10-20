-- Postfix completion like IDEA's: type an expression, then .var / .nn / .if / .for … and the
-- expression is wrapped (order.getLines().for → for (var line : order.getLines()) { … }).
-- They show up in the completion list after the dot (Enter / Tab expands); Tab moves between
-- the fields. Templates per language below; $X is the expression, ${1:…} fields, $0 the end.

local M = {}

local TEMPLATES = {
  java = {
    var = { 'Introduce local variable', 'var ${1:$NAME} = $X;$0' },
    nn = { 'if (expr != null)', 'if ($X != null) {\n\t$0\n}' },
    notnull = { 'if (expr != null)', 'if ($X != null) {\n\t$0\n}' },
    null = { 'if (expr == null)', 'if ($X == null) {\n\t$0\n}' },
    ['if'] = { 'if (expr)', 'if ($X) {\n\t$0\n}' },
    ['else'] = { 'if (!expr)', 'if (!$X) {\n\t$0\n}' },
    ['not'] = { '!expr', '!$X$0' },
    ['for'] = { 'for (var item : expr)', 'for (var ${1:$ITEM} : $X) {\n\t$0\n}' },
    fori = { 'for (int i = 0; i < expr; i++)', 'for (int ${1:i} = 0; $1 < $X; $1++) {\n\t$0\n}' },
    forr = { 'for (int i = expr; i > 0; i--)', 'for (int ${1:i} = $X; $1 > 0; $1--) {\n\t$0\n}' },
    ['while'] = { 'while (expr)', 'while ($X) {\n\t$0\n}' },
    ['return'] = { 'return expr;', 'return $X;$0' },
    sout = { 'System.out.println(expr)', 'System.out.println($X);$0' },
    par = { '(expr)', '($X)$0' },
    cast = { '((Type) expr)', '((${1:Type}) $X)$0' },
    opt = { 'Optional.ofNullable(expr)', 'Optional.ofNullable($X)$0' },
    throw = { 'throw expr;', 'throw $X;$0' },
    new = { 'new Expr()', 'new $X($1)$0' },
    field = { 'this.expr = expr;', 'this.$X = $X;$0' },
    try = { 'try { expr } catch', 'try {\n\t$X;\n} catch (${1:Exception} ${2:e}) {\n\t${0:throw new RuntimeException(e);}\n}' },
  },
  python = {
    var = { 'name = expr', '${1:$NAME} = $X$0' },
    nn = { 'if expr is not None', 'if $X is not None:\n\t$0' },
    null = { 'if expr is None', 'if $X is None:\n\t$0' },
    ['if'] = { 'if expr', 'if $X:\n\t$0' },
    ['not'] = { 'not expr', 'not $X$0' },
    ['for'] = { 'for item in expr', 'for ${1:$ITEM} in $X:\n\t$0' },
    ['while'] = { 'while expr', 'while $X:\n\t$0' },
    ['return'] = { 'return expr', 'return $X$0' },
    print = { 'print(expr)', 'print($X)$0' },
    len = { 'len(expr)', 'len($X)$0' },
    str = { 'str(expr)', 'str($X)$0' },
    par = { '(expr)', '($X)$0' },
  },
  javascript = {
    var = { 'const name = expr', 'const ${1:$NAME} = $X;$0' },
    let = { 'let name = expr', 'let ${1:$NAME} = $X;$0' },
    nn = { 'if (expr != null)', 'if ($X != null) {\n\t$0\n}' },
    null = { 'if (expr == null)', 'if ($X == null) {\n\t$0\n}' },
    ['if'] = { 'if (expr)', 'if ($X) {\n\t$0\n}' },
    ['not'] = { '!expr', '!$X$0' },
    ['for'] = { 'for (const item of expr)', 'for (const ${1:$ITEM} of $X) {\n\t$0\n}' },
    ['return'] = { 'return expr', 'return $X;$0' },
    log = { 'console.log(expr)', 'console.log($X);$0' },
    await = { 'await expr', 'await $X$0' },
    par = { '(expr)', '($X)$0' },
  },
  c = {
    nn = { 'if (expr != NULL)', 'if ($X != NULL) {\n\t$0\n}' },
    null = { 'if (expr == NULL)', 'if ($X == NULL) {\n\t$0\n}' },
    ['if'] = { 'if (expr)', 'if ($X) {\n\t$0\n}' },
    ['not'] = { '!expr', '!$X$0' },
    fori = { 'for (int i = 0; i < expr; i++)', 'for (int ${1:i} = 0; $1 < $X; $1++) {\n\t$0\n}' },
    ['while'] = { 'while (expr)', 'while ($X) {\n\t$0\n}' },
    ['return'] = { 'return expr;', 'return $X;$0' },
    par = { '(expr)', '($X)$0' },
    cast = { '((type) expr)', '((${1:type}) $X)$0' },
  },
}
TEMPLATES.typescript = TEMPLATES.javascript
TEMPLATES.javascriptreact = TEMPLATES.javascript
TEMPLATES.typescriptreact = TEMPLATES.javascript
TEMPLATES.cpp = TEMPLATES.c

local CLOSE = { [')'] = '(', [']'] = '[' }

--- The expression that ends at the end of `text`: names, dots, calls and indexing with their
--- (balanced) arguments, string literals — order.getLines().get(0), "a b", items[i]
function M.expression(text)
  local i, depth = #text, 0
  while i > 0 do
    local c = text:sub(i, i)
    if CLOSE[c] then
      depth = depth + 1
    elseif c == '(' or c == '[' then
      if depth == 0 then
        break
      end
      depth = depth - 1
    elseif c == '"' or c == "'" then
      local open = text:sub(1, i - 1):match('.*()' .. c)
      if not open then
        break
      end
      i = open
    elseif depth == 0 and not c:match '[%w_%.]' then
      break
    end
    i = i - 1
  end
  local expr = text:sub(i + 1)
  return expr ~= '' and not expr:match '^%.' and expr or nil
end

-- A name for the new variable: getLines() → lines, order → order, items → item (for)
local function names(expr)
  local last = expr:match '([%w_]+)%b()$' or expr:match '([%w_]+)%]?$' or 'value'
  last = last:gsub('^get(%u)', '%1'):gsub('^is(%u)', '%1')
  last = last:sub(1, 1):lower() .. last:sub(2)
  local item = last:match '^(.-)ies$' and (last:sub(1, -4) .. 'y') or last:match '^(.-)s$' or 'item'
  if last == expr then
    last = last .. '1'
  end
  return last, item ~= '' and item or 'item'
end

local function resolve(_, line_to_cursor, match)
  local expr = M.expression(line_to_cursor:sub(1, -#match - 1))
  if not expr then
    return nil
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local name, item = names(expr)
  return {
    clear_region = { from = { row - 1, col - #match - #expr }, to = { row - 1, col } },
    env_override = { POSTFIX_X = expr, POSTFIX_NAME = name, POSTFIX_ITEM = item },
  }
end

function M.setup()
  local ls = require 'luasnip'
  for ft, templates in pairs(TEMPLATES) do
    local list = {}
    for key, t in pairs(templates) do
      local body = t[2]:gsub('%$X', '${POSTFIX_X}'):gsub('%$NAME', '${POSTFIX_NAME}'):gsub('%$ITEM', '${POSTFIX_ITEM}')
      table.insert(list, ls.parser.parse_snippet({ trig = '.' .. key, name = '.' .. key, dscr = t[1], wordTrig = false, resolveExpandParams = resolve }, body))
    end
    ls.add_snippets(ft, list, { key = 'pc-postfix-' .. ft })
  end
end

return M
