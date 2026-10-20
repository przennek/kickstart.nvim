-- Surround With like IDEA's (Cmd+Option+T): select code, pick a template, type into its fields.
--   lines (V, or a selection over several lines): if / else, while, for, try / catch / finally,
--     synchronized, block… of the language
--   part of a line: ( ), !( ), cast, String.valueOf( ), Optional.of( ), not ( ), str( )…
--   <leader>es (visual) / Cmd+Option+T on the Mac
-- Tab / Shift+Tab move between the fields, like the variables of an IDEA live template.
-- (Tab in Visual mode + a snippet trigger still works for the surround.xml live templates.)

local M = {}

-- $S = the selection; ${1:…} fields, $0 where the cursor ends
local BRACES = {
  { 'if', 'if (${1:condition}) {\n\t$S\n}$0' },
  { 'if / else', 'if (${1:condition}) {\n\t$S\n} else {\n\t$0\n}' },
  { 'while', 'while (${1:condition}) {\n\t$S\n}$0' },
  { 'do / while', 'do {\n\t$S\n} while (${1:condition});$0' },
  { 'for', 'for (${1}) {\n\t$S\n}$0' },
  { '{ }', '{\n\t$S\n}$0' },
}

local STATEMENTS = {
  java = {
    { 'for each', 'for (${1:var} ${2:item} : ${3:items}) {\n\t$S\n}$0' },
    { 'try / catch', 'try {\n\t$S\n} catch (${1:Exception} ${2:e}) {\n\t${0:throw new RuntimeException(e);}\n}' },
    { 'try / finally', 'try {\n\t$S\n} finally {\n\t$0\n}' },
    { 'try / catch / finally', 'try {\n\t$S\n} catch (${1:Exception} ${2:e}) {\n\t${3:throw new RuntimeException(e);}\n} finally {\n\t$0\n}' },
    { 'synchronized', 'synchronized (${1:this}) {\n\t$S\n}$0' },
    { 'Runnable', 'Runnable ${1:runnable} = () -> {\n\t$S\n};$0' },
  },
  javascript = {
    { 'for … of', 'for (const ${1:item} of ${2:items}) {\n\t$S\n}$0' },
    { 'try / catch', 'try {\n\t$S\n} catch (${1:e}) {\n\t$0\n}' },
    { 'try / finally', 'try {\n\t$S\n} finally {\n\t$0\n}' },
    { 'function', 'function ${1:name}(${2}) {\n\t$S\n}$0' },
    { '() => { }', '(${1}) => {\n\t$S\n}$0' },
  },
  c = {
    { '#ifdef', '#ifdef ${1:NAME}\n$R\n#endif$0' },
    { '#if 0', '#if 0\n$R\n#endif$0' },
  },
  python = {
    { 'if', 'if ${1:condition}:\n\t$S$0' },
    { 'if / else', 'if ${1:condition}:\n\t$S\nelse:\n\t${0:pass}' },
    { 'while', 'while ${1:condition}:\n\t$S$0' },
    { 'for', 'for ${1:item} in ${2:items}:\n\t$S$0' },
    { 'try / except', 'try:\n\t$S\nexcept ${1:Exception} as ${2:e}:\n\t${0:raise}' },
    { 'try / finally', 'try:\n\t$S\nfinally:\n\t${0:pass}' },
    { 'with', 'with ${1:resource} as ${2:r}:\n\t$S$0' },
    { 'def', 'def ${1:name}(${2}):\n\t$S$0' },
  },
}

local EXPRESSIONS = {
  java = { '($S)', '!($S)', '((${1:Type}) $S)', 'String.valueOf($S)', 'Optional.ofNullable($S)', 'Optional.of($S)', 'assertThat($S).isEqualTo(${1})' },
  javascript = { '($S)', '!($S)', 'String($S)', 'await $S' },
  c = { '($S)', '!($S)', '((${1:type}) $S)', 'sizeof($S)' },
  python = { '($S)', 'not ($S)', 'str($S)', 'len($S)', 'list($S)' },
}

local ALIAS = { typescript = 'javascript', javascriptreact = 'javascript', typescriptreact = 'javascript', cpp = 'c' }

local function escape(text)
  return (text:gsub('[\\$}]', '\\%0'))
end

-- Templates for the filetype: statements (with braces for C-like languages) or expressions
local function templates(ft, expression)
  ft = ALIAS[ft] or ft
  if expression then
    return vim.tbl_map(function(body)
      return { (body:gsub('%${%d:?([^}]*)}', '%1'):gsub('%$S', '…')), body }
    end, EXPRESSIONS[ft] or { '($S)' })
  end
  if not STATEMENTS[ft] then
    return {}
  end
  local list = ft == 'python' and {} or vim.deepcopy(BRACES)
  return vim.list_extend(list, STATEMENTS[ft])
end

local function expand(body, pos, indent)
  require('lazy').load { plugins = { 'LuaSnip' } }
  require('luasnip').lsp_expand(body, { pos = pos, indent = indent })
end

--- Surround the lines first..last (1-based) with `body`
local function surround_lines(buf, first, last, body)
  local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  local indent = lines[1]:match '^%s*'
  local common
  for _, l in ipairs(lines) do
    if l:match '%S' then
      local ind = #l:match '^%s*'
      common = common and math.min(common, ind) or ind
    end
  end
  local body_lines = vim.tbl_map(function(l)
    return escape(l:sub((common or 0) + 1))
  end, lines)
  -- $S: indented one level (\t, LuaSnip turns it into the buffer's indent)
  body = body:gsub('\t%$S', function()
    return '\t' .. table.concat(body_lines, '\n\t')
  end)
  if body:find '%$R' then
    -- preprocessor lines: at column 0, the code keeps its own indentation
    body = body:gsub('%$R', function()
      return table.concat(vim.tbl_map(escape, lines), '\n')
    end)
    vim.api.nvim_buf_set_lines(buf, first - 1, last, false, { '' })
    return expand(body, { first - 1, 0 }, false)
  end
  vim.api.nvim_buf_set_lines(buf, first - 1, last, false, { indent })
  expand(body, { first - 1, #indent })
end

--- Surround the text between two (0-based, end exclusive) positions on one line
local function surround_text(buf, row, col, end_col, body)
  local text = vim.api.nvim_buf_get_text(buf, row, col, row, end_col, {})[1]
  vim.api.nvim_buf_set_text(buf, row, col, row, end_col, { '' })
  expand((body:gsub('%$S', function()
    return escape(text)
  end)), { row, col })
end

function M.surround()
  local mode = vim.fn.mode()
  if not mode:match '^[vV\22]' then
    return
  end
  vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'nx', false)
  local buf = vim.api.nvim_get_current_buf()
  local s, e = vim.api.nvim_buf_get_mark(buf, '<'), vim.api.nvim_buf_get_mark(buf, '>')
  -- part of one line = an expression; whole lines (V, or a selection over the whole text of the
  -- line or over several lines) = statements
  local expression = false
  if mode == 'v' and s[1] == e[1] then
    local line = vim.api.nvim_buf_get_lines(buf, s[1] - 1, s[1], false)[1]
    local last = math.min(e[2] + 1, #line) -- 1-based start of the last selected character
    local to = last + vim.str_utf_end(line, last) -- end, exclusive (0-based)
    expression = not (line:sub(1, s[2]):match '^%s*$' and line:sub(to + 1):match '^%s*$')
    e[2] = to
  end
  local list = templates(vim.bo.filetype, expression)
  if #list == 0 then
    return vim.notify('Surround With: no templates for ' .. vim.bo.filetype, vim.log.levels.WARN)
  end
  vim.ui.select(list, {
    prompt = 'Surround With',
    format_item = function(item)
      return item[1]
    end,
  }, function(item)
    if not item then
      return
    end
    if expression then
      surround_text(buf, s[1] - 1, s[2], e[2], item[2])
    else
      surround_lines(buf, s[1], e[1], item[2])
    end
  end)
end

vim.keymap.set('x', '<leader>es', M.surround, { desc = 'Surround With…' })
-- Cmd+Option+T on the Mac (Alacritty sends it as Ctrl+Alt+F8)
vim.keymap.set('x', '<C-M-F8>', M.surround, { desc = 'Surround With…' })

return M
