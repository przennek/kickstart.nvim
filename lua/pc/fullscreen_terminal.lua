-- Terminals over the whole editor, one key each, apart from the Alt+T one:
--   Alt+I (Cmd+I on macOS)               the agent (Kiro, Claude…): a shell you run it in
--   Alt+Shift+D (Cmd+Shift+D on macOS)   the database TUI (vim.g.pc_db_tui, else the first
--                                        installed of DB_TUIS); quitting it closes the window
-- The key shows it, typing; again hides it and you are back where you were. What runs in it stays
-- alive while it is hidden. Going to another window (Alt+1, Ctrl+K…) hides it as well.

local M = {}

-- database TUIs, the widest coverage of what IDEA's Database window connects to first
M.DB_TUIS = {
  { 'dfox', 'PostgreSQL, MySQL, SQLite, MongoDB, Cassandra, Redis' },
  { 'tsql', 'PostgreSQL, MongoDB' },
  { 'sqlit', 'PostgreSQL, MySQL, SQLite, SQL Server, Oracle, ClickHouse, Snowflake…' },
  { 'harlequin', 'DuckDB, SQLite, PostgreSQL, MySQL…' },
  { 'lazysql', 'PostgreSQL, MySQL, SQLite, SQL Server' },
}

local function size()
  return { width = vim.o.columns, height = vim.o.lines - vim.o.cmdheight - 1 }
end

---@type table<string, Terminal>
local terms = {}

-- In the agent terminal the wheel scrolls back through Kiro's chat and a drag selects to copy, as
-- in any terminal; typing then goes back to the program: the key reaches it, at the bottom, not
-- Neovim (after scrolling the next keys were Neovim's). Leaving typing with Esc Esc keeps Normal
-- mode as usual (Vim motions, / search). (Blocking the wheel instead left no way to scroll.)
local TYPING = { ['<CR>'] = true, ['<BS>'] = true, ['<Tab>'] = true, ['<Space>'] = true, ['<lt>'] = true, ['<Up>'] = true, ['<Down>'] = true, ['<Left>'] = true, ['<Right>'] = true, ['<C-C>'] = true }
local mouse_key = false
local by_mouse = {} -- agent buffer -> left typing with the mouse (true), the keys typed since (string)
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
  if vim.fn.strchars(name) == 1 or TYPING[name] then
    -- the keys typed until typing has started go after it, in order
    if by_mouse[buf] == true then
      by_mouse[buf] = typed
      vim.schedule(function()
        local keys = by_mouse[buf]
        by_mouse[buf] = nil
        vim.cmd.startinsert()
        vim.api.nvim_feedkeys(keys, 'n', false)
      end)
    else
      by_mouse[buf] = by_mouse[buf] .. typed
    end
    return ''
  end
end)
local function typing_returns(buf)
  vim.b[buf].pc_agent = true
  local group = vim.api.nvim_create_augroup('pc-agent-typing-' .. buf, { clear = true })
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

-- The database TUI gets every key (Ctrl+H/J/K/L, Esc, Alt+1…: Neovim's in other terminals) but
-- Alt+Shift+D, back to Neovim, and Alt+I. lazysql: Cmd+<key> (Alt) does what its Ctrl+<key> does
-- (Cmd+E SQL editor, Cmd+R / Cmd+Enter run the query, Cmd+S save changes…), as Ctrl in IDEA is Cmd on
-- the Mac
local OWN = { ['<M-D>'] = true, ['<M-i>'] = true }
local LAZYSQL = { '<M-e>', '<M-r>', '<M-s>', '<M-p>', '<M-t>', '<M-d>', '<M-u>' }
local function pass_keys(buf, cmd)
  local keys = {}
  for _, m in ipairs(vim.api.nvim_get_keymap 't') do
    local first = m.lhs:match '^<[^>]+>' or m.lhs:sub(1, 1)
    keys[vim.fn.keytrans(vim.keycode(first))] = true
  end
  for key in pairs(keys) do
    if not OWN[key] then
      vim.keymap.set('t', key, key, { buffer = buf, nowait = true, desc = 'To the database TUI' })
    end
  end
  if vim.fs.basename(vim.split(cmd, ' ')[1]) == 'lazysql' then
    for _, key in ipairs(LAZYSQL) do
      vim.keymap.set('t', key, '<C-' .. key:sub(4), { buffer = buf, desc = 'lazysql: Ctrl' .. key:sub(3) })
    end
    vim.keymap.set('t', '<M-CR>', '<C-r>', { buffer = buf, desc = 'lazysql: run the query' })
  end
end

local function create(name, cmd)
  local Terminal = require('toggleterm.terminal').Terminal
  return Terminal:new {
    cmd = cmd,
    display_name = name,
    direction = 'float',
    -- not one of the Alt+T terminals (:ToggleTerm, the tool window)
    hidden = true,
    float_opts = {
      border = 'none',
      row = 0,
      col = 0,
      width = function()
        return size().width
      end,
      height = function()
        return size().height
      end,
    },
    on_open = function(t)
      -- the database TUIs take the mouse themselves (Neovim passes it on)
      if not cmd then
        if not vim.b[t.bufnr].pc_agent then
          typing_returns(t.bufnr)
        end
      elseif not vim.b[t.bufnr].pc_keys_passed then
        vim.b[t.bufnr].pc_keys_passed = true
        pass_keys(t.bufnr, cmd)
      end
      vim.schedule(function()
        if vim.api.nvim_get_current_win() == t.window then
          vim.cmd 'startinsert'
        end
      end)
      -- leaving it for another window hides it (a float would cover the window you went to)
      vim.api.nvim_create_autocmd('WinLeave', {
        buffer = t.bufnr,
        once = true,
        callback = function()
          vim.schedule(function()
            if t:is_open() then
              t:close()
            end
          end)
        end,
      })
    end,
    on_exit = function()
      terms[name] = nil
    end,
  }
end

--- Shows / hides the full-screen terminal `name`; `cmd` (nil: your shell) runs in it
function M.toggle(name, cmd)
  local t = terms[name]
  if t and t:is_open() then
    vim.cmd 'stopinsert'
    t:close()
    return
  end
  -- from a popup (Search Everywhere, an input box): it closes first
  if vim.api.nvim_win_get_config(0).relative ~= '' then
    pcall(vim.api.nvim_win_close, 0, false)
  end
  vim.cmd 'stopinsert'
  t = t or create(name, cmd)
  terms[name] = t
  t:open()
end

function M.is_open(name)
  return terms[name] ~= nil and terms[name]:is_open()
end

--- The database TUI to run: vim.g.pc_db_tui or the first one installed
function M.db_tui()
  if vim.g.pc_db_tui then
    return vim.g.pc_db_tui
  end
  for _, tool in ipairs(M.DB_TUIS) do
    if vim.fn.executable(tool[1]) == 1 then
      return tool[1]
    end
  end
end

-- also while typing and from inside (the key never reaches the program)
local modes = { 'n', 'i', 'x', 't' }
vim.keymap.set(modes, '<M-i>', function()
  M.toggle 'Agent'
end, { desc = 'Agent terminal (full screen)' })
vim.keymap.set(modes, '<M-D>', function()
  local cmd = M.db_tui()
  if not cmd and not terms.Database then
    local names = vim.tbl_map(function(t)
      return t[1] .. ' (' .. t[2] .. ')'
    end, M.DB_TUIS)
    return vim.notify('No database TUI installed: ' .. table.concat(names, ', ') .. ' (vim.g.pc_db_tui picks one)', vim.log.levels.WARN)
  end
  M.toggle('Database', cmd)
end, { desc = 'Database (full-screen TUI)' })

-- a resized terminal window: they still cover all of it
vim.api.nvim_create_autocmd('VimResized', {
  group = vim.api.nvim_create_augroup('pc-fullscreen-terminal', { clear = true }),
  callback = function()
    local s = size()
    for _, t in pairs(terms) do
      if t:is_open() and vim.api.nvim_win_is_valid(t.window) then
        vim.api.nvim_win_set_config(t.window, { relative = 'editor', row = 0, col = 0, width = s.width, height = s.height })
      end
    end
  end,
})

return M
