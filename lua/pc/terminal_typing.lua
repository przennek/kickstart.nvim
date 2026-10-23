-- A terminal you scrolled or copied from (Normal mode) takes typing again, like IDEA's: keys
-- that would edit a buffer ("E21: modifiable is off") go to the shell instead, p / P paste
-- the clipboard into it, and copying (y) goes straight back to typing. Moving and selecting
-- (h j k l w b G / ? v V y …) work as in any buffer.

local M = {}

-- editing keys in Normal mode: none of them means anything in a terminal
local TYPE = { 'o', 'O', 's', 'S', 'x', 'X', 'c', 'C', 'r', 'R', 'u', 'U', 'd', 'D', 'J', 'K', 'Q', '<BS>', '<Del>' }

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
