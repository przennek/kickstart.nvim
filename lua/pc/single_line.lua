-- One-line inputs (Telescope prompts, the fields of pc.form dialogs) behave like a GUI text field:
--   Alt+A (Cmd+A)  selects the whole text; typing, pasting, Backspace or Delete replaces it,
--                  moving the cursor just drops the selection
--   pasting a copied line (or several) never splits the input: lines are joined with a space

local M = {}

local ns = vim.api.nvim_create_namespace 'pc-single-line'
local attached = {} -- buf -> true
local selected -- buffer whose text is selected

-- where the text starts: after the "> " of a prompt buffer
local function text_start(buf)
  return vim.bo[buf].buftype == 'prompt' and #vim.fn.prompt_getprompt(buf) or 0
end

local function unselect()
  if selected and vim.api.nvim_buf_is_valid(selected) then
    vim.api.nvim_buf_clear_namespace(selected, ns, 0, -1)
  end
  selected = nil
end

local function delete_text(buf)
  local from = text_start(buf)
  local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ''
  vim.api.nvim_buf_set_text(buf, 0, from, 0, #line, { '' })
  vim.api.nvim_win_set_cursor(0, { 1, from })
end

local function select_all()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_get_current_line()
  local from = text_start(buf)
  unselect()
  if #line > from then
    selected = buf
    vim.api.nvim_buf_set_extmark(buf, ns, 0, from, { end_col = #line, hl_group = 'Visual' })
  end
end

-- keys that only drop the selection; anything else typed replaces the selected text
local KEEP = {}
for _, k in ipairs { 'Left', 'Right', 'Home', 'End', 'Up', 'Down', 'Esc', 'C-C', 'CR', 'Tab', 'S-Tab', 'C-N', 'C-P', 'C-J', 'C-K', 'M-a' } do
  KEEP['<' .. k .. '>'] = true
end
local DELETE = { ['<BS>'] = true, ['<Del>'] = true, ['<C-H>'] = true, ['<C-W>'] = true, ['<C-U>'] = true }

vim.on_key(function(key, typed)
  if not selected then
    return
  end
  local buf = selected
  unselect()
  if vim.api.nvim_get_current_buf() ~= buf or vim.fn.mode() ~= 'i' then
    return
  end
  local k = vim.fn.keytrans(typed ~= '' and typed or key)
  if KEEP[k] then
    return
  end
  delete_text(buf)
  if DELETE[k] then
    return ''
  end
end, vim.api.nvim_create_namespace 'pc-single-line-keys')

local paste = vim.paste
vim.paste = function(lines, phase)
  local buf = vim.api.nvim_get_current_buf()
  if attached[buf] and vim.fn.mode() == 'i' then
    if selected == buf and phase ~= 2 and phase ~= 3 then
      unselect()
      delete_text(buf)
    end
    -- a whole paste comes in one call (phase -1); a long one in chunks, joined as they are
    local text = phase == -1 and vim.trim(table.concat(vim.tbl_map(vim.trim, lines), ' ')) or table.concat(lines, ' ')
    lines = { text }
  end
  return paste(lines, phase)
end

--- Makes `buf` a one-line input
function M.attach(buf)
  if attached[buf] then
    return
  end
  attached[buf] = true
  vim.keymap.set('i', '<M-a>', select_all, { buffer = buf, desc = 'Select all' })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      attached[buf] = nil
    end,
  })
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('pc-single-line', { clear = true }),
  pattern = 'TelescopePrompt',
  callback = function(event)
    M.attach(event.buf)
  end,
})

return M
