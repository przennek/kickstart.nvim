-- Questions in a small box at the cursor instead of the command line at the bottom, like IDEA's
-- inline rename and its little dialogs. Used for every vim.ui.input (Rename, New Class, Move,
-- Maven goals…) and the debugger's Evaluate.
--   the suggested text is selected: typing or a paste replaces it, an arrow keeps it (Alt+A
--   selects it again, pc.single_line); Enter confirms, Esc / Ctrl+C cancels, Up / Down go
--   through earlier answers to the same question
-- Questions with completion (file paths…) stay in the command line, where Tab completes.

local M = {}

local histories = {} -- prompt -> answers, oldest first

--- opts: prompt, default, title (instead of the prompt), history (key; default: the prompt)
function M.open(opts, on_confirm)
  opts = opts or {}
  local prompt = vim.trim((opts.prompt or ''):gsub('[:%s]+$', ''))
  local default = opts.default or ''
  local key = opts.history or prompt
  local history = histories[key] or {}
  histories[key] = history

  -- leaving Insert mode in the box moves the cursor of the window below one to the left:
  -- put it back, a rename asks the server about the word under it
  local origin, cursor = vim.api.nvim_get_current_win(), vim.api.nvim_win_get_cursor(0)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  require('pc.single_line').attach(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })
  local title = ' ' .. (opts.title or (prompt ~= '' and prompt or 'Input')) .. '  Enter · Esc '
  local width = math.max(vim.fn.strdisplaywidth(title) + 2, math.min(80, vim.fn.strdisplaywidth(default) + 20), 30)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = math.min(width, vim.o.columns - 4),
    height = 1,
    style = 'minimal',
    border = 'rounded',
    title = title,
    title_pos = 'left',
    zindex = 70,
  })
  -- no completion menu here (its Enter would take a suggestion instead of the answer)
  pcall(function()
    require('cmp').setup.buffer { enabled = false }
  end)
  local done = false
  local function finish(value)
    if done then
      return
    end
    done = true
    vim.cmd 'stopinsert'
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if value and value ~= '' and history[#history] ~= value then
      table.insert(history, value)
    end
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(origin) then
        pcall(vim.api.nvim_win_set_cursor, origin, cursor)
      end
      on_confirm(value)
    end)
  end
  local function map(lhs, fn)
    vim.keymap.set({ 'i', 'n' }, lhs, fn, { buffer = buf })
  end
  map('<CR>', function()
    finish(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or '')
  end)
  for _, lhs in ipairs { '<Esc>', '<C-c>' } do
    map(lhs, function()
      finish(nil)
    end)
  end
  local index = #history + 1
  local function walk(step)
    return function()
      local i = index + step
      if i >= 1 and i <= #history + 1 then
        index = i
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { history[i] or default })
        vim.cmd 'startinsert!'
      end
    end
  end
  map('<Up>', walk(-1))
  map('<Down>', walk(1))
  -- clicking elsewhere / leaving the box cancels it
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      finish(nil)
    end,
  })
  vim.cmd 'startinsert!'
  if default ~= '' then
    vim.schedule(require('pc.single_line').select_all)
  end
end

local native = vim.ui.input
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.input = function(opts, on_confirm)
  if opts and opts.completion then
    return native(opts, on_confirm)
  end
  M.open(opts, on_confirm)
end

return M
