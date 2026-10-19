-- Inheritance navigation, like IDEA's Hierarchy tool window and gutter icons.
--   Alt+8       Hierarchy window (toggle) for the type at the cursor (or the type the cursor is in);
--   gH          show the hierarchy of the type at the cursor (also when the window is open);
--               inside: t = type hierarchy, s = supertypes, c = subtypes (children),
--               Enter / double-click = go to the type, q / Alt+8 = close
--   gutter      ↑ overrides / implements something above, ↓ has overrides / implementations
--               below (↕ both). Click it: ↑ goes up, ↓ lists what is below.
--   Alt+U       Go to Super Method / super type (Cmd+U); gI lists implementations / subtypes
-- Works with language servers that support type hierarchy (jdtls for Java).

local M = {}

local ns = vim.api.nvim_create_namespace 'pc-hierarchy-gutter'
local TYPE_KINDS = { [5] = true, [10] = true, [11] = true, [23] = true } -- class, enum, interface, struct
local METHOD_KINDS = { [6] = true, [9] = true } -- method, constructor
local IGNORED_SUPERS = { Object = true, Enum = true, Record = true }

vim.api.nvim_set_hl(0, 'PcHierarchySign', { link = 'Function', default = true })
vim.api.nvim_set_hl(0, 'PcHierarchyRoot', { link = 'Title', default = true })

---------------------------------------------------------------------------
-- LSP helpers (run inside a coroutine)
---------------------------------------------------------------------------

local function client_for(buf)
  return vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/prepareTypeHierarchy' })[1]
end

local function await(client, method, params, buf)
  local co = assert(coroutine.running())
  client:request(method, params, function(err, result)
    vim.schedule(function()
      coroutine.resume(co, not err and result or nil)
    end)
  end, buf)
  return coroutine.yield()
end

local function async(fn)
  coroutine.wrap(fn)()
end

local function pos_params(buf, pos)
  return { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = pos }
end

local function prepare(client, buf, pos)
  local items = await(client, 'textDocument/prepareTypeHierarchy', pos_params(buf, pos), buf)
  return items and items[1]
end

local function supertypes(client, buf, item)
  return vim.tbl_filter(function(i)
    return not IGNORED_SUPERS[i.name]
  end, await(client, 'typeHierarchy/supertypes', { item = item }, buf) or {})
end

local function subtypes(client, buf, item)
  return await(client, 'typeHierarchy/subtypes', { item = item }, buf) or {}
end

-- Position of the type declaration the cursor is in (treesitter), for prepareTypeHierarchy
local function enclosing_type_pos(buf)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf })
  while ok and node do
    if node:type():match 'class' or node:type():match 'interface' or node:type():match 'enum' or node:type():match 'record' then
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

local view = { buf = nil, win = nil, origin = nil, root = nil, client = nil, src = nil, mode = 'type', lines = {} }

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
    end
  end
  for lnum, row in pairs(view.lines) do
    if row.root and window_open() then
      vim.api.nvim_win_set_cursor(view.win, { lnum, 0 })
    end
  end
end

local function row(item, depth, is_root)
  local icon = ({ [5] = '󰠱 ', [10] = ' ', [11] = ' ', [23] = '󰙅 ' })[item.kind] or '  '
  local pkg = item.detail and item.detail ~= '' and ('  ' .. item.detail) or ''
  return { item = item, root = is_root, text = string.rep('  ', depth) .. (is_root and '● ' or '') .. icon .. item.name .. pkg }
end

-- Build the rows for the current mode (inside a coroutine)
local function build()
  local c, b, root = view.client, view.src, view.root
  local rows, seen, budget = {}, {}, 300

  local function key(i)
    return i.uri .. ':' .. i.name
  end
  local function down(item, depth)
    for _, sub in ipairs(subtypes(c, b, item)) do
      if budget <= 0 or seen[key(sub)] or depth > 8 then
        return
      end
      seen[key(sub)] = true
      budget = budget - 1
      table.insert(rows, row(sub, depth))
      down(sub, depth + 1)
    end
  end
  local function up(item, depth)
    for _, sup in ipairs(supertypes(c, b, item)) do
      if budget <= 0 or seen[key(sup)] or depth > 10 then
        return
      end
      seen[key(sup)] = true
      budget = budget - 1
      table.insert(rows, row(sup, depth))
      up(sup, depth + 1)
    end
  end

  seen[key(root)] = true
  if view.mode == 'sub' then
    table.insert(rows, row(root, 0, true))
    down(root, 1)
  elseif view.mode == 'super' then
    table.insert(rows, row(root, 0, true))
    up(root, 1)
  else
    -- the chain of supertypes of the same kind (classes for a class) above, subtypes below
    local chain, item = {}, root
    while #chain < 10 do
      local sups = supertypes(c, b, item)
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
    down(root, #chain + 1)
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
    map('<CR>', go)
    map('o', go)
    map('<2-LeftMouse>', go)
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
  local client = client_for(buf)
  if not client then
    return vim.notify('No type hierarchy for this file (language server without support)', vim.log.levels.WARN)
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  async(function()
    local item = prepare(client, buf, { line = cursor[1] - 1, character = cursor[2] })
    if not item then
      local pos = enclosing_type_pos(buf)
      item = pos and prepare(client, buf, pos)
    end
    if not item then
      return vim.notify('No type at the cursor', vim.log.levels.WARN)
    end
    view.root, view.client, view.src, view.origin = item, client, buf, win
    view.mode = 'type' -- like IDEA, a new hierarchy starts as the full type hierarchy
    open_window()
    refresh()
  end)
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

function M.refresh_gutter(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local client = client_for(buf)
  if not client or running[buf] then
    return
  end
  running[buf] = true
  async(function()
    local tick = vim.b[buf].changedtick
    local symbols = await(client, 'textDocument/documentSymbol', { textDocument = { uri = vim.uri_from_bufnr(buf) } }, buf) or {}
    local found = {}
    local function walk(list)
      for _, s in ipairs(list) do
        local pos = (s.selectionRange or (s.location and s.location.range) or {}).start
        if pos and (TYPE_KINDS[s.kind] or METHOD_KINDS[s.kind]) then
          local m = { up = false, down = false, pos = pos, method = METHOD_KINDS[s.kind] ~= nil }
          if m.method and s.kind == 6 then
            local impls = await(client, 'textDocument/implementation', pos_params(buf, pos), buf) or {}
            m.down = #vim.tbl_filter(function(l)
              local range = l.range or l.targetSelectionRange
              return not (l.uri == vim.uri_from_bufnr(buf) and range and range.start.line == pos.line)
            end, impls) > 0
            if client.name == 'jdtls' then
              local sup = await(client, 'java/findLinks', { type = 'superImplementation', position = pos_params(buf, pos) }, buf)
              m.up = sup ~= nil and #sup > 0
            end
          elseif not m.method then
            local item = prepare(client, buf, pos)
            if item then
              m.up = #supertypes(client, buf, item) > 0
              m.down = #subtypes(client, buf, item) > 0
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
  local client = client_for(buf)
  if not client then
    return
  end
  if m.method then
    if client.name == 'jdtls' then
      return require('jdtls').super_implementation()
    end
    return
  end
  async(function()
    local item = prepare(client, buf, m.pos)
    local sups = item and supertypes(client, buf, item) or {}
    if #sups == 0 then
      return vim.notify 'No supertypes'
    end
    pick(sups, 'Go to supertype', function(i)
      jump_to(i)
    end)
  end)
end

local function go_down(buf, m)
  vim.api.nvim_win_set_cursor(0, { m.pos.line + 1, m.pos.character })
  if m.method then
    return require('telescope.builtin').lsp_implementations()
  end
  local client = client_for(buf)
  async(function()
    local item = prepare(client, buf, m.pos)
    local subs = item and subtypes(client, buf, item) or {}
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

--- Go to Super (Alt+U): the method / type at the cursor line, else the enclosing method / type
function M.go_super()
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.fn.line '.' - 1
  local m = (marks[buf] or {})[lnum]
  if m and m.up then
    return go_up(buf, m)
  end
  local client = client_for(buf)
  if client and client.name == 'jdtls' then
    return require('jdtls').super_implementation()
  end
  local pos = enclosing_type_pos(buf)
  if pos then
    go_up(buf, { pos = pos, method = false })
  end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

--- Alt+8: the Hierarchy tool window, again closes it
function M.toggle()
  if window_open() then
    return M.close_window()
  end
  M.open()
end

local group = vim.api.nvim_create_augroup('pc-hierarchy', { clear = true })
vim.api.nvim_create_autocmd('LspAttach', {
  group = group,
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if not (client and client:supports_method 'textDocument/prepareTypeHierarchy') then
      return
    end
    local buf = event.buf
    vim.keymap.set('n', '<M-8>', M.toggle, { buffer = buf, desc = 'Hierarchy window' })
    vim.keymap.set('n', 'gH', M.open, { buffer = buf, desc = 'Type hierarchy' })
    vim.keymap.set('n', '<M-u>', M.go_super, { buffer = buf, desc = 'Go to super method / type' })
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

-- Clicking a hierarchy marker in the sign column (the first 4 screen columns of a window with
-- signcolumn=yes:2) navigates; any other click works as usual
vim.keymap.set('n', '<LeftMouse>', function()
  local mouse = vim.fn.getmousepos()
  if mouse.winid ~= 0 and mouse.line > 0 and mouse.wincol <= 4 then
    local buf = vim.api.nvim_win_get_buf(mouse.winid)
    if (marks[buf] or {})[mouse.line - 1] then
      vim.schedule(function()
        vim.api.nvim_set_current_win(mouse.winid)
        marker_action(buf, mouse.line - 1)
      end)
      return ''
    end
  end
  return '<LeftMouse>'
end, { expr = true, desc = 'Click: hierarchy marker or move cursor' })

return M
