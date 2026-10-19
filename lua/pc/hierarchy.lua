-- Inheritance navigation, like IDEA's Hierarchy tool window and gutter icons.
--   Alt+8       Hierarchy window (toggle) for the type at the cursor (or the type the cursor is in)
--   gH          show the hierarchy of the type at the cursor (also when the window is open);
--               inside: t = type hierarchy, s = supertypes, c = subtypes (children),
--               Enter / F4 / double-click = go to the type, q / Alt+8 = close
--   gutter      ↑ overrides / implements something above, ↓ has overrides / implementations
--               below (↕ both). Click it: ↑ goes up, ↓ lists what is below.
--   Alt+U       Go to Super Method / super type (Cmd+U); gI lists implementations / subtypes
-- Java and C++ use the language server's type hierarchy (jdtls, clangd). Python and
-- JavaScript / TypeScript servers have none, so there the hierarchy is read from the code.

local M = {}

local ns = vim.api.nvim_create_namespace 'pc-hierarchy-gutter'
local TYPE_KINDS = { [5] = true, [10] = true, [11] = true, [23] = true } -- class, enum, interface, struct
local METHOD_KINDS = { [6] = true } -- method
local IGNORED_SUPERS = { Object = true, Enum = true, Record = true, object = true }

vim.api.nvim_set_hl(0, 'PcHierarchySign', { link = 'Function', default = true })
vim.api.nvim_set_hl(0, 'PcHierarchyRoot', { link = 'Title', default = true })

---------------------------------------------------------------------------
-- Async helpers (everything below runs inside a coroutine)
---------------------------------------------------------------------------

local function await(client, method, params, buf)
  local co = assert(coroutine.running())
  client:request(method, params, function(err, result)
    vim.schedule(function()
      local ok, msg = coroutine.resume(co, not err and result or nil)
      if not ok then
        vim.notify('hierarchy: ' .. tostring(msg), vim.log.levels.ERROR)
      end
    end)
  end, buf)
  return coroutine.yield()
end

local function async(fn)
  local ok, msg = coroutine.resume(coroutine.create(fn))
  if not ok then
    vim.notify('hierarchy: ' .. tostring(msg), vim.log.levels.ERROR)
  end
end

local function pos_params(buf, pos)
  return { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = pos }
end

local function client_with(buf, method)
  return vim.lsp.get_clients({ bufnr = buf, method = method })[1]
end

local function not_ignored(items)
  return vim.tbl_filter(function(i)
    return not IGNORED_SUPERS[i.name]
  end, items or {})
end

---------------------------------------------------------------------------
-- Providers: prepare(pos) -> item, supertypes(item), subtypes(item), method_supers(pos)
-- Items are LSP TypeHierarchyItem-like: { name, kind, detail, uri, selectionRange }
---------------------------------------------------------------------------

local function lsp_provider(client, buf)
  local p = { name = client.name }
  function p.prepare(pos)
    local items = await(client, 'textDocument/prepareTypeHierarchy', pos_params(buf, pos), buf)
    return items and items[1]
  end
  function p.supertypes(item)
    return not_ignored(await(client, 'typeHierarchy/supertypes', { item = item }, buf))
  end
  function p.subtypes(item)
    return await(client, 'typeHierarchy/subtypes', { item = item }, buf) or {}
  end
  function p.method_supers(pos)
    if client.name ~= 'jdtls' then
      return {}
    end
    local links = await(client, 'java/findLinks', { type = 'superImplementation', position = pos_params(buf, pos) }, buf) or {}
    return vim.tbl_map(function(l)
      return { name = l.displayName or '', uri = l.uri, selectionRange = l.range, kind = 6 }
    end, links)
  end
  return p
end

-- Languages whose servers have no type hierarchy (Python, JavaScript / TypeScript): read it
-- from the code — base classes from the class declaration (treesitter), subclasses by
-- searching the project (ripgrep), super methods by looking into the base classes.
local function names_in(node, bufnr, types, out)
  for child in node:iter_children() do
    if types[child:type()] then
      table.insert(out, (vim.treesitter.get_node_text(child, bufnr):match '([%w_$]+)$'))
    elseif child:named_child_count() > 0 and child:type() ~= 'type_arguments' then
      names_in(child, bufnr, types, out)
    end
  end
  return out
end

local SPECS = {
  python = {
    roots = { 'pyproject.toml', 'setup.py', 'setup.cfg', '.git' },
    rg_types = { 'py' },
    lang = function()
      return 'python'
    end,
    class_types = { class_definition = true },
    method_types = { function_definition = true },
    bases = function(node, bufnr)
      local bases = node:field('superclasses')[1]
      return bases and names_in(bases, bufnr, { identifier = true, attribute = true }, {}) or {}
    end,
    definition = function(name)
      return [[^\s*class\s+]] .. name .. [[\b]]
    end,
    subclass = function(name)
      return [[^\s*class\s+\w+\s*\([^)]*\b]] .. name .. [[\b]]
    end,
  },
  javascript = {
    roots = { 'package.json', 'tsconfig.json', '.git' },
    rg_types = { 'js', 'ts' },
    lang = function(file)
      local ext = file:match '%.(%w+)$'
      return ({ ts = 'typescript', mts = 'typescript', cts = 'typescript', tsx = 'tsx' })[ext] or 'javascript'
    end,
    class_types = { class_declaration = true, class = true, abstract_class_declaration = true },
    method_types = { method_definition = true },
    bases = function(node, bufnr)
      for child in node:iter_children() do
        if child:type() == 'class_heritage' then
          return names_in(child, bufnr, { identifier = true, type_identifier = true, property_identifier = true }, {})
        end
      end
      return {}
    end,
    definition = function(name)
      return [[\bclass\s+]] .. name .. [[\b]]
    end,
    subclass = function(name)
      return [[\bclass\s+[\w$]+[^{]*\b(extends|implements)\b[^{]*\b]] .. name .. [[\b]]
    end,
  },
}
SPECS.typescript, SPECS.typescriptreact, SPECS.javascriptreact = SPECS.javascript, SPECS.javascript, SPECS.javascript

local function code_provider(buf, spec)
  local root = vim.fs.root(buf, spec.roots) or vim.fn.getcwd()
  local p = { name = 'code' }

  local function parse(bufnr)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      -- only read for analysis: no swap file, so a file open in another Neovim doesn't
      -- trigger the E325 "ATTENTION" prompt
      vim.bo[bufnr].swapfile = false
      if not pcall(vim.fn.bufload, bufnr) then
        return nil
      end
    end
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, spec.lang(vim.api.nvim_buf_get_name(bufnr)))
    return ok and parser:parse()[1]:root()
  end

  local function class_item(bufnr, node)
    local name = node:field('name')[1]
    local row, col, erow, ecol = name:range()
    local file = vim.api.nvim_buf_get_name(bufnr)
    return {
      name = vim.treesitter.get_node_text(name, bufnr),
      kind = 5,
      detail = vim.fs.relpath(root, file) or file,
      uri = vim.uri_from_fname(file),
      selectionRange = { start = { line = row, character = col }, ['end'] = { line = erow, character = ecol } },
    }
  end

  local function class_node_at(bufnr, line, col)
    local tree = parse(bufnr)
    local node = tree and tree:named_descendant_for_range(line, col, line, col)
    while node and not spec.class_types[node:type()] do
      node = node:parent()
    end
    return node
  end

  -- class declarations in the project matching the ripgrep `regex`
  local function search_classes(regex)
    local args = { 'rg', '--json', '-e', regex, root }
    for _, t in ipairs(spec.rg_types) do
      vim.list_extend(args, { '-t', t }, 1, 2)
    end
    local out = vim.system(args, { text = true }):wait()
    local items = {}
    for line in (out.stdout or ''):gmatch '[^\n]+' do
      local ok, msg = pcall(vim.json.decode, line)
      if ok and msg.type == 'match' then
        local text = msg.data.lines.text or ''
        local start, _, name = text:find 'class%s+([%w_$]+)'
        if name then
          local file = msg.data.path.text
          local col = start - 1 + #text:match('class%s+', start)
          table.insert(items, {
            name = name,
            kind = 5,
            detail = vim.fs.relpath(root, file) or file,
            uri = vim.uri_from_fname(vim.fn.fnamemodify(file, ':p')),
            selectionRange = {
              start = { line = msg.data.line_number - 1, character = col },
              ['end'] = { line = msg.data.line_number - 1, character = col + #name },
            },
          })
        end
      end
    end
    return items
  end

  function p.prepare(pos)
    local node = class_node_at(buf, pos.line, pos.character)
    return node and class_item(buf, node)
  end

  function p.supertypes(item)
    local bufnr = vim.uri_to_bufnr(item.uri)
    local node = class_node_at(bufnr, item.selectionRange.start.line, item.selectionRange.start.character)
    local result = {}
    for _, name in ipairs(node and spec.bases(node, bufnr) or {}) do
      if name and not IGNORED_SUPERS[name] then
        vim.list_extend(result, search_classes(spec.definition(name)))
      end
    end
    return result
  end

  function p.subtypes(item)
    return search_classes(spec.subclass(item.name))
  end

  -- methods with the same name in the base classes (nearest first)
  function p.method_supers(pos)
    local tree = parse(buf)
    local node = tree and tree:named_descendant_for_range(pos.line, pos.character, pos.line, pos.character)
    while node and not spec.method_types[node:type()] do
      node = node:parent()
    end
    local method = node and vim.treesitter.get_node_text(node:field('name')[1], buf)
    local cls = node and node:parent()
    while cls and not spec.class_types[cls:type()] do
      cls = cls:parent()
    end
    if not (method and cls) then
      return {}
    end
    local found, seen = {}, {}
    local queue = p.supertypes(class_item(buf, cls))
    while #queue > 0 and #found == 0 do
      local sup = table.remove(queue, 1)
      local key = sup.uri .. sup.name
      if not seen[key] then
        seen[key] = true
        local bufnr = vim.uri_to_bufnr(sup.uri)
        local cnode = class_node_at(bufnr, sup.selectionRange.start.line, sup.selectionRange.start.character)
        local body = cnode and cnode:field('body')[1]
        for child in body and body:iter_children() or function() end do
          local def = child:type() == 'decorated_definition' and child:field('definition')[1] or child
          local name_node = spec.method_types[def:type()] and def:field('name')[1]
          if name_node and vim.treesitter.get_node_text(name_node, bufnr) == method then
            local row, col, erow, ecol = name_node:range()
            table.insert(found, {
              name = sup.name .. '.' .. method,
              kind = 6,
              uri = sup.uri,
              selectionRange = { start = { line = row, character = col }, ['end'] = { line = erow, character = ecol } },
            })
          end
        end
        vim.list_extend(queue, p.supertypes(sup))
      end
    end
    return found
  end

  return p
end

local function provider_for(buf)
  local client = client_with(buf, 'textDocument/prepareTypeHierarchy')
  if client then
    return lsp_provider(client, buf)
  end
  local spec = SPECS[vim.bo[buf].filetype]
  if spec and vim.fn.executable 'rg' == 1 then
    return code_provider(buf, spec)
  end
end

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------

-- Position of the type declaration the cursor is in (treesitter)
local function enclosing_type_pos(buf)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf })
  while ok and node do
    local t = node:type()
    if t:match 'class' or t:match 'interface' or t:match 'enum' or t:match 'record' or t:match 'struct' then
      local name = node:field('name')[1]
      if name then
        local row, col = name:start()
        return { line = row, character = col }
      end
    end
    node = node:parent()
  end
end

local function jump_to(item, win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  vim.lsp.util.show_document({ uri = item.uri, range = item.selectionRange }, 'utf-16', { focus = true })
end

local function pick(items, prompt, on_choice)
  if #items == 1 then
    return on_choice(items[1])
  end
  vim.ui.select(items, {
    prompt = prompt,
    format_item = function(i)
      return i.name .. (i.detail and ('  ' .. i.detail) or '')
    end,
  }, function(i)
    if i then
      on_choice(i)
    end
  end)
end

---------------------------------------------------------------------------
-- Hierarchy window
---------------------------------------------------------------------------

local view = { buf = nil, win = nil, origin = nil, root = nil, provider = nil, mode = 'type', lines = {} }

local function window_open()
  return view.win and vim.api.nvim_win_is_valid(view.win)
end

local function render(rows)
  view.lines = {}
  local text = {
    ({ type = 'Type hierarchy', super = 'Supertypes', sub = 'Subtypes' })[view.mode] .. ' of ' .. view.root.name,
    't type · s supertypes · c subtypes · Enter go · q close',
    '',
  }
  for _, row in ipairs(rows) do
    table.insert(text, row.text)
    view.lines[#text] = row
  end
  vim.bo[view.buf].modifiable = true
  vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, text)
  vim.bo[view.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(view.buf, ns, 0, 0, { end_col = #text[1], hl_group = 'Title' })
  vim.api.nvim_buf_set_extmark(view.buf, ns, 1, 0, { end_col = #text[2], hl_group = 'Comment' })
  for lnum, row in pairs(view.lines) do
    if row.root then
      vim.api.nvim_buf_set_extmark(view.buf, ns, lnum - 1, 0, { end_col = #text[lnum], hl_group = 'PcHierarchyRoot' })
      if window_open() then
        vim.api.nvim_win_set_cursor(view.win, { lnum, 0 })
      end
    end
  end
end

local function row(item, depth, is_root)
  local icon = ({ [5] = '󰠱 ', [10] = ' ', [11] = ' ', [23] = '󰙅 ' })[item.kind] or '  '
  local detail = item.detail and item.detail ~= '' and ('  ' .. item.detail) or ''
  return { item = item, root = is_root, text = string.rep('  ', depth) .. (is_root and '● ' or '') .. icon .. item.name .. detail }
end

-- Build the rows for the current mode (inside a coroutine)
local function build()
  local p, root = view.provider, view.root
  local rows, seen, budget = {}, {}, 300

  local function key(i)
    return i.uri .. ':' .. i.name
  end
  local function walk(item, depth, next_items, limit)
    for _, child in ipairs(next_items(item)) do
      if budget <= 0 or seen[key(child)] or depth > limit then
        return
      end
      seen[key(child)] = true
      budget = budget - 1
      table.insert(rows, row(child, depth))
      walk(child, depth + 1, next_items, limit)
    end
  end

  seen[key(root)] = true
  if view.mode == 'sub' then
    table.insert(rows, row(root, 0, true))
    walk(root, 1, p.subtypes, 8)
  elseif view.mode == 'super' then
    table.insert(rows, row(root, 0, true))
    walk(root, 1, p.supertypes, 10)
  else
    -- the chain of supertypes of the same kind (classes for a class) above, subtypes below
    local chain, item = {}, root
    while #chain < 10 do
      local sups = p.supertypes(item)
      local next_item = vim.tbl_filter(function(s)
        return s.kind == root.kind
      end, sups)[1] or (root.kind ~= 5 and sups[1]) or nil
      if not next_item or seen[key(next_item)] then
        break
      end
      seen[key(next_item)] = true
      table.insert(chain, 1, next_item)
      item = next_item
    end
    for depth, sup in ipairs(chain) do
      table.insert(rows, row(sup, depth - 1))
    end
    table.insert(rows, row(root, #chain, true))
    walk(root, #chain + 1, p.subtypes, 8)
  end
  return rows
end

local function refresh()
  async(function()
    local rows = build()
    if view.buf and vim.api.nvim_buf_is_valid(view.buf) then
      render(rows)
    end
  end)
end

function M.close_window()
  if window_open() then
    vim.api.nvim_win_close(view.win, true)
  end
  view.win = nil
end

local function open_window()
  if not (view.buf and vim.api.nvim_buf_is_valid(view.buf)) then
    view.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[view.buf].filetype = 'pchierarchy'
    vim.bo[view.buf].bufhidden = 'hide'
    local function map(lhs, fn)
      vim.keymap.set('n', lhs, fn, { buffer = view.buf, nowait = true })
    end
    local function go()
      local r = view.lines[vim.fn.line '.']
      if r then
        jump_to(r.item, view.origin)
      end
    end
    for _, lhs in ipairs { '<CR>', 'o', '<F4>', '<2-LeftMouse>' } do
      map(lhs, go)
    end
    for lhs, mode in pairs { t = 'type', s = 'super', c = 'sub' } do
      map(lhs, function()
        view.mode = mode
        refresh()
      end)
    end
    map('q', M.close_window)
    map('<M-8>', M.close_window)
  end
  if not window_open() then
    vim.cmd 'botright 50vsplit'
    view.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(view.win, view.buf)
    for opt, value in pairs { number = false, relativenumber = false, signcolumn = 'no', wrap = false, cursorline = true, winfixwidth = true } do
      vim.wo[view.win][opt] = value
    end
  end
  vim.api.nvim_set_current_win(view.win)
end

--- Hierarchy window for the type at / around the cursor (gH re-targets an open window)
function M.open()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local provider = provider_for(buf)
  if not provider then
    return vim.notify('No type hierarchy for this file', vim.log.levels.WARN)
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  async(function()
    local item = provider.prepare { line = cursor[1] - 1, character = cursor[2] }
    if not item then
      local pos = enclosing_type_pos(buf)
      item = pos and provider.prepare(pos)
    end
    if not item then
      return vim.notify('No type at the cursor', vim.log.levels.WARN)
    end
    view.root, view.provider, view.origin = item, provider, win
    view.mode = 'type' -- like IDEA, a new hierarchy starts as the full type hierarchy
    open_window()
    refresh()
  end)
end

--- Alt+8: the Hierarchy tool window, again closes it
function M.toggle()
  if window_open() then
    return M.close_window()
  end
  M.open()
end

---------------------------------------------------------------------------
-- Gutter markers
---------------------------------------------------------------------------

---@type table<integer, table<integer, {up: boolean, down: boolean, pos: lsp.Position, method: boolean}>>
local marks = {}
local running = {}

local function place(buf, lnum, m)
  local text = (m.up and m.down) and '↕' or (m.up and '↑' or '↓')
  vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { sign_text = text, sign_hl_group = 'PcHierarchySign', priority = 5 })
end

local function has_implementations(client, buf, pos)
  if not client then
    return false
  end
  local impls = await(client, 'textDocument/implementation', pos_params(buf, pos), buf) or {}
  if impls.uri then
    impls = { impls }
  end
  local uri = vim.uri_from_bufnr(buf)
  return #vim.tbl_filter(function(l)
    local range = l.range or l.targetSelectionRange
    return not ((l.uri or l.targetUri) == uri and range and range.start.line == pos.line)
  end, impls) > 0
end

function M.refresh_gutter(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local provider = provider_for(buf)
  local symbols_client = client_with(buf, 'textDocument/documentSymbol')
  if not provider or not symbols_client or running[buf] then
    return
  end
  local impl_client = client_with(buf, 'textDocument/implementation')
  running[buf] = true
  async(function()
    local tick = vim.b[buf].changedtick
    local symbols = await(symbols_client, 'textDocument/documentSymbol', { textDocument = { uri = vim.uri_from_bufnr(buf) } }, buf) or {}
    local found = {}
    local function walk(list)
      for _, s in ipairs(list) do
        local pos = (s.selectionRange or (s.location and s.location.range) or {}).start
        if pos and (TYPE_KINDS[s.kind] or METHOD_KINDS[s.kind]) then
          local m = { up = false, down = false, pos = pos, method = METHOD_KINDS[s.kind] ~= nil }
          if m.method then
            m.down = has_implementations(impl_client, buf, pos)
            m.up = #provider.method_supers(pos) > 0
          else
            local item = provider.prepare(pos)
            if item then
              m.up = #provider.supertypes(item) > 0
              m.down = #provider.subtypes(item) > 0
            end
          end
          if m.up or m.down then
            found[pos.line] = m
          end
        end
        if s.children then
          walk(s.children)
        end
      end
    end
    walk(symbols)
    running[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].changedtick ~= tick then
      return
    end
    marks[buf] = found
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for lnum, m in pairs(found) do
      place(buf, lnum, m)
    end
  end)
end

---------------------------------------------------------------------------
-- Navigation: up (Go to Super) / down (implementations, subtypes)
---------------------------------------------------------------------------

local function go_up(buf, m)
  local provider = provider_for(buf)
  if not provider then
    return
  end
  async(function()
    local targets
    if m.method then
      targets = provider.method_supers(m.pos)
    else
      local item = provider.prepare(m.pos)
      targets = item and provider.supertypes(item) or {}
    end
    if #targets == 0 then
      return vim.notify 'Nothing above'
    end
    pick(targets, 'Go to super', function(i)
      jump_to(i)
    end)
  end)
end

local function go_down(buf, m)
  vim.api.nvim_win_set_cursor(0, { m.pos.line + 1, m.pos.character })
  if m.method then
    return require('telescope.builtin').lsp_implementations()
  end
  local provider = provider_for(buf)
  async(function()
    local item = provider.prepare(m.pos)
    local subs = item and provider.subtypes(item) or {}
    if #subs == 0 then
      return vim.notify 'No subtypes'
    end
    pick(subs, 'Go to subtype', function(i)
      jump_to(i)
    end)
  end)
end

local function marker_action(buf, lnum)
  local m = (marks[buf] or {})[lnum]
  if not m then
    return false
  end
  vim.api.nvim_win_set_cursor(0, { lnum + 1, m.pos.character })
  if m.up and m.down then
    vim.ui.select({ 'Go to super', 'Show overriding / subtypes' }, { prompt = 'Hierarchy' }, function(choice)
      if choice == 'Go to super' then
        go_up(buf, m)
      elseif choice then
        go_down(buf, m)
      end
    end)
  elseif m.up then
    go_up(buf, m)
  else
    go_down(buf, m)
  end
  return true
end

--- Go to Super (Alt+U): the method / type on the cursor line, else the enclosing method / type
function M.go_super()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local m = (marks[buf] or {})[cursor[1] - 1]
  if m and m.up then
    return go_up(buf, m)
  end
  local ok, node = pcall(vim.treesitter.get_node)
  while ok and node do
    local t = node:type()
    if t:match 'method' or t == 'function_definition' then
      return go_up(buf, { pos = { line = cursor[1] - 1, character = cursor[2] }, method = true })
    end
    if t:match 'class' or t:match 'interface' then
      break
    end
    node = node:parent()
  end
  local pos = enclosing_type_pos(buf)
  if pos then
    go_up(buf, { pos = pos, method = false })
  end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local group = vim.api.nvim_create_augroup('pc-hierarchy', { clear = true })
vim.api.nvim_create_autocmd('LspAttach', {
  group = group,
  callback = function(event)
    local buf = event.buf
    if vim.b[buf].pc_hierarchy or not provider_for(buf) then
      return
    end
    vim.b[buf].pc_hierarchy = true
    vim.keymap.set('n', '<M-8>', M.toggle, { buffer = buf, desc = 'Type hierarchy' })
    vim.keymap.set('n', 'gH', M.open, { buffer = buf, desc = 'Type hierarchy' })
    vim.keymap.set('n', '<M-u>', M.go_super, { buffer = buf, desc = 'Go to Super Method' })
    -- the project is still being imported when the server attaches
    vim.defer_fn(function()
      M.refresh_gutter(buf)
    end, 3000)
    vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufEnter' }, {
      group = group,
      buffer = buf,
      callback = function()
        M.refresh_gutter(buf)
      end,
    })
  end,
})

-- Clicking a marker navigates (see gutter.lua)
require('pc.gutter').on_click(function(buf, lnum)
  return marker_action(buf, lnum)
end)

return M
