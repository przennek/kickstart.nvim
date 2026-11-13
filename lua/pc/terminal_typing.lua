-- Typing in a terminal that is in Normal mode (IDEA-like): what you type goes to the program
-- running in it (the shell, Kiro's chat), not to Neovim ("E21: modifiable is off", a motion).
--
-- ONE rule, in two situations. How Normal mode was entered decides which keys are Vim's:
--
--   key                                       after Esc Esc (keyboard)   after a click / the wheel
--   ----------------------------------------  -------------------------  -------------------------
--   VIM keys: j k g G v V y Y / ? n N : Space   Vim (scroll, search,       program
--             i a I A (i a I A: typing again)   copy, commands, leader)
--   p P                                         paste the clipboard        program (the letter)
--                                               (bracketed paste)
--   any other printable character, BS, Del      program, back to typing    program
--   Enter Tab Esc arrows Home End Ctrl+A B C    Vim (Enter opens a link)   program
--     D E F G N P R U W Y Z
--   Ctrl+H J K L (windows), mouse, wheel        Vim                        Vim
--
-- The program gets the keys in the order typed; typing starts again (Terminal mode) on the
-- first one. Wheel down: only the turn that reaches the end of the output returns to typing.
-- A mouse drag / triple click copies and returns to typing; a double click copies the word
-- and keeps it selected. Copies lose the program's frame / margin (M.clean).
--
-- Two implementations, because Vim itself must read the keyboard column but cannot in the
-- other: (1) buffer-local Normal mappings for "other printable, BS, Del": Vim's own mapping
-- and command parsing keeps g-sequences (gg, gd), leader mappings (Space f), counts and
-- operators (yw) working, they only act on the first key of a command. (2) after the mouse
-- EVERY key goes to the program, so no Vim parsing may happen (global gd / gr / Space-f
-- mappings would swallow "grep", "a f"): vim.on_key sees each key first and takes it away.

local M = {}

-- the Vim keys of the table above
local VIM = {}
for char in ('jkgGvVyY/?nN: iaIApP'):gmatch '.' do
  VIM[char] = true
end
local SPECIAL = { ['<'] = '<lt>', ['\\'] = '<Bslash>', ['|'] = '<Bar>' } -- as :map writes them

local function send(buf, text)
  local chan = vim.bo[buf].channel
  if chan and chan > 0 then
    pcall(vim.api.nvim_chan_send, chan, text)
  end
end

-- (1) after Esc Esc: the keys that go to the program, as mappings
local function map_typing(buf)
  local keys = { '<BS>', '<Del>' }
  for byte = 33, 126 do
    local char = string.char(byte)
    if not VIM[char] then
      table.insert(keys, SPECIAL[char] or char)
    end
  end
  for _, key in ipairs(keys) do
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
end

-- (2) after a click / the wheel (the log: after a click "git" lost its g i to Vim, Ctrl+C /
-- Enter did nothing, ":" ran a Neovim command): every key but Ctrl+H/J/K/L and the mouse
local KEYS = { -- besides the characters, which have no <>
  '<CR>',
  '<BS>',
  '<Del>',
  '<Tab>',
  '<Space>',
  '<lt>',
  '<Esc>',
  '<Up>',
  '<Down>',
  '<Left>',
  '<Right>',
  '<Home>',
  '<End>',
}
local TYPING = {}
for _, key in ipairs(KEYS) do
  TYPING[key] = true
end
for ctrl in ('ABCDEFGNPRUWYZ'):gmatch '.' do -- the shell's: Ctrl+C, Ctrl+R history, Ctrl+A / E...
  TYPING['<C-' .. ctrl .. '>'] = true
end
local mouse_key = false -- the last key was the mouse
local by_mouse = {} -- terminal buffer -> Normal mode was entered with the mouse
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
  if mouse_key or not by_mouse[buf] or vim.fn.mode() ~= 'n' or not typing(name) then
    return
  end
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
end)

-- by_mouse: set when Terminal mode is left by a mouse key, cleared when typing is back
local function track_mouse(buf)
  local group = vim.api.nvim_create_augroup('pc-terminal-mouse-' .. buf, { clear = true })
  vim.api.nvim_create_autocmd('ModeChanged', {
    group = group,
    buffer = buf,
    callback = function()
      if vim.v.event.new_mode == 't' then
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
  track_mouse(buf)
  map_typing(buf)
  -- the wheel down to the end of the output: typing again, new output scrolls the screen
  -- only when this turn of the wheel reached the end: already there (the wheel kept turning at
  -- the last line) it stays in Normal mode, or every turn left typing and the next one came back
  -- (the log: t / n hundreds of times, autosave and the diff refresh with each)
  vim.keymap.set('n', '<ScrollWheelDown>', function()
    local before = vim.fn.line 'w$'
    vim.cmd.normal { vim.keycode '<ScrollWheelDown>', bang = true }
    if vim.fn.line 'w$' < vim.fn.line '$' then
      return
    end
    if vim.fn.line 'w$' > before then
      vim.cmd 'startinsert'
    else
      -- on the last line new output keeps scrolling the window
      vim.cmd 'normal! G'
    end
  end, { buffer = buf, desc = 'Scroll; at the end back to typing' })
  -- a mouse selection copies itself on release, as in a terminal emulator (the log: drag, then y)
  vim.keymap.set('x', '<LeftRelease>', '<LeftRelease>y', { buffer = buf, desc = 'Copy the mouse selection' })
  -- a double click (word) copies too and stays selected, for the third click (line), which
  -- copies and goes back to typing (the log: double / triple click, then y)
  vim.keymap.set('x', '<2-LeftRelease>', '<2-LeftRelease>ygv', { buffer = buf, desc = 'Copy the word clicked twice' })
  vim.keymap.set('x', '<3-LeftRelease>', '<3-LeftRelease>y', { buffer = buf, desc = 'Copy the line clicked three times' })
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
