-- Debugger values like IDEA's Variables view:
--   Copy Value   Alt+C / yv on a variable in Variables or Watches, <leader>xy in the editor
--                (expression under the cursor or the selection); objects are copied as their
--                toString() / str(), not as the debugger's summary
--   Add to Watches   w on a variable, <leader>xw in the editor (word or selection)
--   Set Value    F2 on a variable: the box at the cursor, then an assignment in the stopped
--                frame (Java, Python; java-debug sets only primitives and strings itself, IDEA
--                takes any expression: new BigDecimal("100")); other debuggers: nvim-dap-ui's edit
--                (e works everywhere)
--   Inspect      <leader>xi: expandable tree of the expression in a float (like IDEA's Inspect)

local M = {}

local function session()
  local s = require('dap').session()
  if not s or not s.current_frame then
    vim.notify('Debugger: not stopped at a breakpoint', vim.log.levels.WARN)
    return nil
  end
  return s
end

local function evaluate(s, expression, context, callback)
  s:request('evaluate', { expression = expression, frameId = s.current_frame.id, context = context }, function(err, resp)
    vim.schedule(function()
      callback(err, resp)
    end)
  end)
end

-- Text of an expression's value; objects as their string form, like IDEA's Copy Value
local function value_text(expression, callback)
  local s = session()
  if not s then
    return
  end
  local context = s.capabilities and s.capabilities.supportsClipboardContext and 'clipboard' or 'repl'
  evaluate(s, expression, context, function(err, resp)
    if err or not resp then
      return callback(nil, err and err.message or 'no value')
    end
    local ft = s.config and s.config.type
    if (resp.variablesReference or 0) > 0 and ft == 'java' then
      return evaluate(s, 'String.valueOf(' .. expression .. ')', 'repl', function(err2, resp2)
        local text = not err2 and resp2 and resp2.result or resp.result
        callback((text:gsub('^"(.*)"$', '%1')))
      end)
    end
    -- a string value as its text, like IDEA (the clipboard context quotes it)
    callback(ft == 'java' and (resp.result:gsub('^"(.*)"$', '%1')) or resp.result)
  end)
end

local function copy(expression)
  value_text(expression, function(text, err)
    if not text then
      return vim.notify('Copy Value: ' .. err, vim.log.levels.WARN)
    end
    vim.fn.setreg('+', text)
    vim.fn.setreg('"', text)
    local shown = #text > 60 and text:sub(1, 57) .. '…' or text
    vim.notify(('Copied %s = %s'):format(expression, shown:gsub('\n', ' ')))
  end)
end

-- The expression under the cursor in the editor, or the visual selection
local function editor_expression()
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' then
    local lines = vim.fn.getregion(vim.fn.getpos 'v', vim.fn.getpos '.', { type = mode })
    vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'nx', false)
    return vim.trim(table.concat(lines, '\n'))
  end
  -- a.b.c under the cursor, up to the word the cursor is on
  local line, col = vim.api.nvim_get_current_line(), vim.fn.col '.'
  local s, e = col, col
  while s > 1 and line:sub(s - 1, s - 1):match '[%w_.$]' do
    s = s - 1
  end
  while e <= #line and line:sub(e, e):match '[%w_$]' do
    e = e + 1
  end
  local expr = line:sub(s, e - 1):gsub('^%.+', '')
  if expr == '' then
    vim.notify('No expression under the cursor', vim.log.levels.INFO)
    return nil
  end
  return expr
end

-- dapui object lines know their evaluateName and hand it to "watch" (w); catch it there
local capture
local function hook_watches()
  local ok, dapui = pcall(require, 'dapui')
  if not ok or not dapui.elements.watches or type(dapui.elements.watches.add) ~= 'function' or dapui.elements.watches.pc_hooked then
    return
  end
  local watches = dapui.elements.watches
  local add = watches.add
  watches.add = function(expression)
    if capture then
      local fn = capture
      capture = nil
      return fn(expression)
    end
    return add(expression)
  end
  watches.pc_hooked = true
end

-- a variable of the scope itself (not a field): its name is the expression
local function top_level_name()
  local line = vim.api.nvim_get_current_line()
  return line:match '^ [▸▾] ([%w_$]+) ' or line:match '^   ([%w_$]+) '
end

local function variable_under_cursor(fn)
  hook_watches()
  local map = vim.fn.maparg('w', 'n', false, true)
  if not map.callback then
    return vim.notify('Not on a variable', vim.log.levels.INFO)
  end
  local name = top_level_name()
  capture = fn
  map.callback()
  -- dapui runs its mappings asynchronously; for plain values it may hand over nothing
  vim.defer_fn(function()
    if capture == fn then
      capture = nil
      if name then
        return fn(name)
      end
      vim.notify('Not on a variable', vim.log.levels.INFO)
    end
  end, 500)
end

function M.copy_variable()
  local line = vim.api.nvim_get_current_line()
  -- objects (▸ / ▾): their toString(); plain values are shown whole on the line
  if line:match '^%s*[▸▾]' then
    return variable_under_cursor(copy)
  end
  local name, value = line:match '^%s*([^%s]+).- = (.*)$'
  if not value then
    return vim.notify('Not on a variable', vim.log.levels.INFO)
  end
  value = value:gsub('^"(.*)"$', '%1')
  vim.fn.setreg('+', value)
  vim.fn.setreg('"', value)
  vim.notify(('Copied %s = %s'):format(name, value))
end

-- name = value in the stopped frame, then Variables / Watches are fetched again
local function assign(expression, current)
  local s = session()
  if not s then
    return
  end
  require('pc.input').open({ prompt = 'Set Value: ' .. expression, default = current or '', history = 'set value' }, function(value)
    if not value or vim.trim(value) == '' then
      return
    end
    evaluate(s, ('%s = %s'):format(expression, value), 'repl', function(err, resp)
      if err or not resp then
        return vim.notify('Set Value: ' .. (err and err.message or 'no answer'), vim.log.levels.WARN)
      end
      vim.notify(('%s = %s'):format(expression, resp.result))
      -- Variables and Watches show the new value (as after a step)
      pcall(s._request_scopes, s, s.current_frame)
    end)
  end)
end

function M.set_variable()
  local s = require('dap').session()
  local type = s and s.config and s.config.type
  if type ~= 'java' and type ~= 'python' and type ~= 'debugpy' then
    local edit = vim.fn.maparg('e', 'n', false, true)
    return edit.callback and edit.callback()
  end
  local line = vim.api.nvim_get_current_line()
  -- a primitive / string starts from its value; an object from nothing (its summary,
  -- BigDecimal@13, is no expression)
  local current = not line:match '^%s*[▸▾]' and line:match ' = (.*)$' or nil
  variable_under_cursor(function(expression)
    assign(expression, current)
  end)
end

function M.copy_expression()
  local expr = editor_expression()
  if expr then
    copy(expr)
  end
end

function M.add_watch()
  local expr = editor_expression()
  if not expr then
    return
  end
  require('dapui').elements.watches.add(expr)
  vim.notify('Watching ' .. expr)
end

function M.inspect()
  local expr = editor_expression()
  if expr and session() then
    require('dap.ui.widgets').hover(expr, { border = 'rounded', title = ' ' .. expr .. ' ' })
  end
end

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'dapui_scopes', 'dapui_watches' },
  group = vim.api.nvim_create_augroup('pc-dap-values', { clear = true }),
  callback = function(event)
    local function map(lhs, fn, desc)
      vim.keymap.set('n', lhs, fn, { buffer = event.buf, desc = desc })
    end
    map('<M-c>', M.copy_variable, 'Copy Value')
    map('yv', M.copy_variable, 'Copy Value')
    map('<F2>', M.set_variable, 'Set Value')
  end,
})

vim.keymap.set({ 'n', 'v' }, '<leader>xy', M.copy_expression, { desc = 'Debug: Copy value' })
vim.keymap.set({ 'n', 'v' }, '<leader>xw', M.add_watch, { desc = 'Debug: Add to watches' })
vim.keymap.set({ 'n', 'v' }, '<leader>xi', M.inspect, { desc = 'Debug: Inspect' })

return M
