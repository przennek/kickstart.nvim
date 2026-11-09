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
      -- the database TUIs get every key (the mouse: Neovim passes it on when they take it)
      if cmd and not vim.b[t.bufnr].pc_keys_passed then
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
