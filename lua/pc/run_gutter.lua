-- Run icons in the gutter, like IDEA's ▶ next to tests and main methods: click one to get
-- the Run / Debug choices for exactly that test, test class or program.
--   Java    @Test / @ParameterizedTest methods, test classes, main()
--   Python  test_* functions, Test* classes, `if __name__ == "__main__":`
--   C/C++   main()
-- The same configurations are on F10 / Ctrl+Shift+F10 (run.lua).

local M = {}

local ns = vim.api.nvim_create_namespace 'pc-run-gutter'
vim.api.nvim_set_hl(0, 'PcRunSign', { link = 'DiagnosticOk', default = true })

---@type table<integer, table<integer, {kind: string, name: string, col: integer}>>
local markers = {}

local function text(node, buf)
  return node and vim.treesitter.get_node_text(node, buf) or ''
end

local function add(found, node, kind, name)
  local row, col = node:start()
  found[row] = found[row] or { kind = kind, name = name, col = col }
end

local detectors = {}

function detectors.java(buf, root, found)
  local function walk(node, class)
    for child in node:iter_children() do
      local t = child:type()
      if t == 'class_declaration' then
        walk(child, child)
      elseif t == 'method_declaration' then
        local mods = text(child:field('modifiers')[1] or child:child(0), buf)
        local name = child:field('name')[1]
        if mods:match '@Test%f[%W]' or mods:match '@ParameterizedTest' or mods:match '@RepeatedTest' then
          add(found, name, 'test', text(name, buf))
          if class then
            local cname = class:field('name')[1]
            add(found, cname, 'class', text(cname, buf))
          end
        elseif text(name, buf) == 'main' and mods:match 'static' then
          add(found, name, 'main', text(class and class:field('name')[1], buf))
        end
      elseif child:named_child_count() > 0 then
        walk(child, class)
      end
    end
  end
  walk(root, nil)
end

function detectors.python(buf, root, found)
  local test_file = vim.fs.basename(vim.api.nvim_buf_get_name(buf)):match '^test_' ~= nil
    or vim.fs.basename(vim.api.nvim_buf_get_name(buf)):match '_test%.py$' ~= nil
  local function walk(node, in_test_class)
    for child in node:iter_children() do
      local t = child:type()
      local def = t == 'decorated_definition' and child:field('definition')[1] or child
      local dt = def:type()
      if dt == 'class_definition' then
        local name = def:field('name')[1]
        local is_test = test_file and text(name, buf):match '^Test' ~= nil
        if is_test then
          add(found, name, 'class', text(name, buf))
        end
        walk(def:field('body')[1] or def, is_test)
      elseif dt == 'function_definition' then
        local name = def:field('name')[1]
        if test_file and text(name, buf):match '^test' and (in_test_class or node:type() == 'module') then
          add(found, name, 'test', text(name, buf))
        end
      elseif t == 'if_statement' and text(child:field('condition')[1], buf):match '__name__' then
        add(found, child, 'main', '')
      end
    end
  end
  walk(root, false)
end

function detectors.c(buf, root, found)
  for child in root:iter_children() do
    if child:type() == 'function_definition' then
      local declarator = child:field('declarator')[1]
      local name = declarator and declarator:field('declarator')[1]
      if text(name, buf) == 'main' then
        add(found, name, 'main', 'main')
      end
    end
  end
end
detectors.cpp = detectors.c

function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local detect = detectors[vim.bo[buf].filetype]
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not detect or not ok or not parser then
    return
  end
  local found = {}
  detect(buf, parser:parse()[1]:root(), found)
  markers[buf] = found
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for row in pairs(found) do
    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { sign_text = '▶', sign_hl_group = 'PcRunSign', priority = 8 })
  end
end

-- Which run configurations belong to a marker (labels come from run.lua)
local function filter_for(buf, m)
  local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
  local stem = vim.fn.fnamemodify(file, ':r')
  return function(label)
    local what = label:gsub('^%S+ ', '')
    if m.kind == 'test' then
      return what:match('[.:]' .. vim.pesc(m.name) .. '$') ~= nil
    elseif m.kind == 'class' then
      return what:match '%(all tests%)$' ~= nil
    elseif vim.bo[buf].filetype == 'java' then
      return what == m.name
    else
      return what == file or what == 'make run'
    end
  end
end

require('pc.gutter').on_click(function(buf, lnum)
  local m = (markers[buf] or {})[lnum]
  if not m then
    return false
  end
  vim.api.nvim_win_set_cursor(0, { lnum + 1, m.col })
  require('pc.run').pick_for(filter_for(buf, m))
  return true
end)

vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
  group = vim.api.nvim_create_augroup('pc-run-gutter', { clear = true }),
  pattern = { '*.java', '*.py', '*.c', '*.cpp', '*.cc' },
  callback = function(event)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(event.buf) then
        M.refresh(event.buf)
      end
    end)
  end,
})

return M
