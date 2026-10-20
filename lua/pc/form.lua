-- Settings dialogs like IDEA's: a floating form with labelled fields and buttons.
--   j / k, Tab / Shift+Tab   move between fields
--   Enter / i               edit the field (text, password, choice), toggle a checkbox
--   Space                   toggle a checkbox / next choice
--   the buttons' keys (shown at the bottom, e.g. Ctrl+S OK, Ctrl+T Test), q / Esc cancels
--
-- require('pc.form').open {
--   title = 'Data Source',
--   fields = {
--     { header = 'General' },
--     { key = 'host', label = 'Host', default = 'localhost' },
--     { key = 'password', label = 'Password', secret = true },
--     { key = 'kind', label = 'Type', choices = { 'a', 'b' } },
--     { key = 'ssh', label = 'Use SSH tunnel', check = true },
--     { key = 'ssh_host', label = 'SSH host', visible = function(v) return v.ssh end },
--     { key = 'url', label = 'URL', readonly = true, value = function(v) return … end },
--   },
--   buttons = { { label = 'OK', key = '<C-s>', run = function(values, form) … form:close() end } },
--   on_change = function(values, key) end,   -- after a field changed (e.g. default port per type)
-- }

local M = {}

local Form = {}
Form.__index = Form

local LABEL_WIDTH = 22

local function shown(field, values)
  return not field.visible or field.visible(values)
end

function Form:value_text(field)
  if field.value then
    return field.value(self.values) or ''
  end
  local v = self.values[field.key]
  if field.check then
    return v and '[x]' or '[ ]'
  elseif field.secret then
    return (v and v ~= '') and string.rep('•', 8) or ''
  end
  return v == nil and '' or tostring(v)
end

function Form:render()
  local lines, hl = {}, {}
  self.rows = {}
  for _, field in ipairs(self.spec.fields) do
    if shown(field, self.values) then
      if field.header then
        if #lines > 0 then
          table.insert(lines, '')
        end
        table.insert(lines, ' ' .. field.header)
        table.insert(hl, { #lines - 1, 'Title' })
      else
        local label = field.label .. ' '
        local text = '   ' .. label .. string.rep('·', math.max(1, LABEL_WIDTH - vim.fn.strdisplaywidth(label))) .. ' '
        table.insert(lines, text .. self:value_text(field))
        self.rows[#lines] = field
        if field.readonly then
          table.insert(hl, { #lines - 1, 'Comment' })
        end
      end
    end
  end
  table.insert(lines, '')
  local keys = {}
  for _, b in ipairs(self.spec.buttons or {}) do
    table.insert(keys, ('[ %s ] %s'):format(b.label, b.hint or b.key:gsub('<C%-(%w)>', 'Ctrl+%1'):gsub('<CR>', 'Enter')))
  end
  table.insert(keys, '[ Cancel ] q')
  table.insert(lines, ' ' .. table.concat(keys, '   '))
  table.insert(hl, { #lines - 1, 'Special' })
  if self.message then
    table.insert(lines, ' ' .. self.message.text)
    table.insert(hl, { #lines - 1, self.message.hl })
  end

  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.bo[self.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(self.buf, self.ns, 0, -1)
  for _, h in ipairs(hl) do
    vim.hl.range(self.buf, self.ns, h[2], { h[1], 0 }, { h[1], -1 })
  end
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_set_height(self.win, #lines)
  end
end

function Form:field_at_cursor()
  return self.rows[vim.api.nvim_win_get_cursor(self.win)[1]]
end

function Form:set(key, value)
  self.values[key] = value
  if self.spec.on_change then
    self.spec.on_change(self.values, key, self)
  end
  self:render()
end

--- A message line under the buttons (Test Connection result, validation errors)
function Form:say(text, level)
  self.message = text and { text = text:gsub('\n', ' '), hl = level == vim.log.levels.ERROR and 'DiagnosticError' or level == vim.log.levels.WARN and 'DiagnosticWarn' or 'DiagnosticOk' } or nil
  self:render()
end

function Form:edit(field)
  field = field or self:field_at_cursor()
  if not field or field.readonly or field.value then
    return
  end
  if field.check then
    return self:set(field.key, not self.values[field.key])
  end
  if field.choices then
    return vim.ui.select(field.choices, { prompt = field.label }, function(choice)
      if choice then
        self:set(field.key, choice)
      end
    end)
  end
  local args = { field.label .. ': ', field.secret and '' or tostring(self.values[field.key] or '') }
  if field.complete and not field.secret then
    table.insert(args, field.complete)
  end
  -- Ctrl+C cancels the edit
  local ok, value = pcall(field.secret and vim.fn.inputsecret or vim.fn.input, unpack(args))
  if ok then
    self:set(field.key, value)
  end
end

function Form:toggle()
  local field = self:field_at_cursor()
  if field and field.check then
    self:set(field.key, not self.values[field.key])
  elseif field and field.choices then
    local i = vim.fn.index(field.choices, self.values[field.key]) + 1
    self:set(field.key, field.choices[i % #field.choices + 1])
  end
end

function Form:jump(dir)
  local row = vim.api.nvim_win_get_cursor(self.win)[1]
  local count = vim.api.nvim_buf_line_count(self.buf)
  local r = row
  repeat
    r = r + dir
    if r < 1 then
      r = count
    elseif r > count then
      r = 1
    end
  until self.rows[r] or r == row
  vim.api.nvim_win_set_cursor(self.win, { r, LABEL_WIDTH + 4 })
end

function Form:close()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
end

function M.open(spec)
  local self = setmetatable({ spec = spec, values = {}, ns = vim.api.nvim_create_namespace 'pc-form' }, Form)
  for _, field in ipairs(spec.fields) do
    if field.key then
      local v = (spec.values or {})[field.key]
      if v == nil then
        v = field.default
      end
      self.values[field.key] = v
    end
  end
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.buf].bufhidden = 'wipe'
  vim.bo[self.buf].filetype = 'pcform'
  self:render()
  local width = math.min(84, vim.o.columns - 4)
  self.win = vim.api.nvim_open_win(self.buf, true, {
    relative = 'editor',
    width = width,
    height = vim.api.nvim_buf_line_count(self.buf),
    row = math.floor(vim.o.lines * 0.15),
    col = math.floor((vim.o.columns - width) / 2),
    border = 'rounded',
    title = ' ' .. spec.title .. ' ',
    title_pos = 'center',
    style = 'minimal',
  })
  vim.wo[self.win].cursorline = true
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = self.buf, nowait = true, desc = desc })
  end
  map('<CR>', function()
    self:edit()
  end, 'Edit field')
  map('i', function()
    self:edit()
  end, 'Edit field')
  map('<Space>', function()
    self:toggle()
  end, 'Toggle')
  map('<Tab>', function()
    self:jump(1)
  end, 'Next field')
  map('<S-Tab>', function()
    self:jump(-1)
  end, 'Previous field')
  map('q', function()
    self:close()
  end, 'Cancel')
  map('<Esc>', function()
    self:close()
  end, 'Cancel')
  for _, b in ipairs(spec.buttons or {}) do
    map(b.key, function()
      b.run(self.values, self)
    end, b.label)
  end
  -- start on the first field
  for row = 1, vim.api.nvim_buf_line_count(self.buf) do
    if self.rows[row] then
      vim.api.nvim_win_set_cursor(self.win, { row, LABEL_WIDTH + 4 })
      break
    end
  end
  return self
end

return M
