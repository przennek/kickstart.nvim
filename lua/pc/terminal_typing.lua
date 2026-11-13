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

-- Left typing with the mouse (a click, the wheel: Kiro's chat, the shell's output), every key you
-- type goes back to the program, in order, Enter and Ctrl+C too: after a click "git" lost its g i
-- to Vim, Ctrl+C / Enter did nothing, ":" ran a Neovim command. Leaving typing with Esc Esc keeps
-- the Normal mode below (j k / v y…).
local TYPING = { ['<CR>'] = true, ['<BS>'] = true, ['<Del>'] = true, ['<Tab>'] = true, ['<Space>'] = true, ['<lt>'] = true, ['<Esc>'] = true, ['<Up>'] = true, ['<Down>'] = true, ['<Left>'] = true, ['<Right>'] = true, ['<Home>'] = true, ['<End>'] = true }
-- the shell's Ctrl keys (Ctrl+C, Ctrl+R history, Ctrl+A / Ctrl+E…), not Ctrl+H/J/K/L (windows)
for _, key in ipairs { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'N', 'P', 'R', 'U', 'W', 'Y', 'Z' } do
  TYPING['<C-' .. key .. '>'] = true
end
local mouse_key = false
local by_mouse = {} -- terminal buffer -> left typing with the mouse
local queue = {} -- terminal buffer -> keys typed since, not sent yet
-- only characters and TYPING keys (one key, or several held back by a pending mapping: <Space>/)
local function typing(name)
  for key in name:gmatch '<[^>]+>' do
    if not TYPING[key] then
      return false
    end
  end
  return name ~= ''
end
vim.on_key(function(_, typed)
  if not typed or typed == '' then
    return
  end
  local name = vim.fn.keytrans(typed)
  mouse_key = name:find 'Mouse' or name:find 'Scroll' or name:find 'Drag' or name:find 'Release'
  local buf = vim.api.nvim_get_current_buf()
  if mouse_key or not by_mouse[buf] or vim.fn.mode() ~= 'n' then
    return
  end
  if typing(name) then
    -- kept until typing has started, then sent in order (keys typed fast / pasted come before
    -- Neovim is back in the terminal)
    local first = queue[buf] == nil
    queue[buf] = (queue[buf] or '') .. typed
    if first then
      vim.schedule(function()
        local keys = queue[buf]
        queue[buf] = nil
        if vim.fn.mode() ~= 't' then
          vim.cmd.startinsert()
        end
        vim.api.nvim_feedkeys(keys, 'ni', false)
      end)
    end
    return ''
  end
end)
local function typing_returns(buf)
  local group = vim.api.nvim_create_augroup('pc-terminal-mouse-' .. buf, { clear = true })
  vim.api.nvim_create_autocmd('ModeChanged', {
    group = group,
    buffer = buf,
    callback = function()
      local mode = vim.v.event.new_mode
      if mode == 't' then
        by_mouse[buf] = nil
      elseif vim.v.event.old_mode == 't' and mouse_key then
        by_mouse[buf] = true
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = buf,
    callback = function()
      by_mouse[buf] = nil
    end,
  })
end

function M.attach(buf)
  typing_returns(buf)
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
      local event = vim.v.event
      local lines = M.clean(event.regcontents)
      vim.schedule(function()
        -- the copy without the program's margin / frame (Kiro's "  │ ") and trailing spaces
        if event.operator == 'y' and table.concat(lines, '\n') ~= table.concat(event.regcontents, '\n') then
          local reg = event.regname ~= '' and event.regname or vim.v.register
          for _, r in ipairs { reg, '0' } do
            pcall(vim.fn.setreg, r, lines, event.regtype)
          end
        end
        if vim.api.nvim_get_current_buf() == buf and vim.fn.mode() == 'n' then
          vim.cmd 'startinsert'
        end
      end)
    end,
  })
end

--- Lines copied from a terminal without what the program draws around them: the margin / frame
--- every line starts with (spaces, │ ┃ ▏ |; the log: 3 x on every pasted line) and trailing spaces
function M.clean(lines)
  local CHAR = '[%z\1-\127\194-\244][\128-\191]*'
  local prefix -- list of characters
  for _, line in ipairs(lines) do
    if line:match '%S' then
      local p = {}
      for ch in line:match('^[%s│┃▏▕|]*'):gmatch(CHAR) do
        table.insert(p, ch)
      end
      if not prefix then
        prefix = p
      else
        local n = 0
        while n < #prefix and n < #p and prefix[n + 1] == p[n + 1] do
          n = n + 1
        end
        prefix = vim.list_slice(prefix, 1, n)
      end
    end
  end
  local cut = table.concat(prefix or {})
  local out = {}
  for _, line in ipairs(lines) do
    if cut ~= '' and line:sub(1, #cut) == cut then
      line = line:sub(#cut + 1)
    end
    table.insert(out, (line:gsub('%s+$', '')))
  end
  return out
end

return M
