-- A terminal you scrolled or copied from (Normal mode) takes typing again, like IDEA's: the
-- characters you type go to the shell (not "E21: modifiable is off" or a motion), p / P paste
-- the clipboard into it, copying (y) and the wheel down to the end go straight back to typing.
-- Scrolling and selecting keep j k g G / ? n N v V y and the mouse.

local M = {}

-- Normal-mode keys kept for scrolling and copying (j k g G, v V y, search, : commands,
-- Space = leader, i / a back to typing, p paste, Enter opens a link); every other character
-- is typed in the shell: after a mouse-wheel scroll "echo" lost its e to a motion
local KEEP = { j = true, k = true, g = true, G = true, v = true, V = true, y = true, Y = true, ['/'] = true, ['?'] = true, n = true, N = true, [':'] = true, [' '] = true, i = true, a = true, I = true, A = true, p = true, P = true }
local SPECIAL = { ['<'] = '<lt>', ['\\'] = '<Bslash>', ['|'] = '<Bar>' }
local TYPE = { '<BS>', '<Del>' }
for byte = 33, 126 do
  local char = string.char(byte)
  if not KEEP[char] then
    table.insert(TYPE, SPECIAL[char] or char)
  end
end

local function send(buf, text)
  local chan = vim.bo[buf].channel
  if chan and chan > 0 then
    pcall(vim.api.nvim_chan_send, chan, text)
  end
end

function M.attach(buf)
  for _, key in ipairs(TYPE) do
    vim.keymap.set('n', key, function()
      vim.cmd 'startinsert'
      send(buf, vim.keycode(key))
    end, { buffer = buf, desc = 'Type in the terminal' })
  end
  for _, key in ipairs { 'p', 'P' } do
    vim.keymap.set('n', key, function()
      local text = vim.fn.getreg '+'
      if text == '' then
        text = vim.fn.getreg '"'
      end
      vim.cmd 'startinsert'
      -- bracketed paste: the shell takes several lines as one paste, not as commands
      send(buf, '\27[200~' .. text:gsub('\n$', '') .. '\27[201~')
    end, { buffer = buf, desc = 'Paste into the terminal' })
  end
  -- the wheel down to the end of the output: typing again, new output scrolls the screen
  vim.keymap.set('n', '<ScrollWheelDown>', function()
    vim.cmd.normal { vim.keycode '<ScrollWheelDown>', bang = true }
    if vim.fn.line 'w$' >= vim.fn.line '$' then
      vim.cmd 'startinsert'
    end
  end, { buffer = buf, desc = 'Scroll; at the end back to typing' })
  -- a mouse selection copies itself on release, as in a terminal emulator (the log: drag, then y)
  vim.keymap.set('x', '<LeftRelease>', '<LeftRelease>y', { buffer = buf, desc = 'Copy the mouse selection' })
  vim.api.nvim_create_autocmd('TextYankPost', {
    buffer = buf,
    group = vim.api.nvim_create_augroup('pc-terminal-typing-' .. buf, { clear = true }),
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_get_current_buf() == buf and vim.fn.mode() == 'n' then
          vim.cmd 'startinsert'
        end
      end)
    end,
  })
end

return M
