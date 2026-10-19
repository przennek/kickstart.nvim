-- Hide All Tool Windows (IDEA's Ctrl+Shift+F12; Alt+Shift+F12 in your keymap, which
-- Alacritty translates to Ctrl+Shift+F12). First press hides the project tree, structure,
-- Find / Problems, terminals, debugger and quickfix, leaving only the editor windows;
-- the second press brings back exactly the ones that were open.

local M = {}

local hidden = nil

local function open_fts()
  local fts = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    fts[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] = true
  end
  return fts
end

local function hide()
  local fts = open_fts()
  local state = {}

  if fts['neo-tree'] then
    state.tree = true
    vim.cmd 'Neotree close'
  end
  if fts['aerial'] then
    state.aerial = true
    require('aerial').close_all()
  end
  if package.loaded['trouble'] then
    local trouble = require 'trouble'
    state.trouble = {}
    for _, mode in ipairs { 'quickfix', 'diagnostics' } do
      if trouble.is_open(mode) then
        table.insert(state.trouble, mode)
        trouble.close(mode)
      end
    end
  end
  if fts['qf'] then
    state.qf = true
    vim.cmd 'cclose'
  end
  if require('pc.run').console_visible() then
    state.run = true
    require('pc.run').hide_console()
  end
  if package.loaded['toggleterm'] then
    state.terms = {}
    for _, term in ipairs(require('toggleterm.terminal').get_all()) do
      if term:is_open() then
        table.insert(state.terms, term)
        term:close()
      end
    end
  end
  if fts['dapui_scopes'] or fts['dapui_stacks'] or fts['dapui_breakpoints'] or fts['dapui_watches'] then
    state.dapui = 'all'
  elseif fts['dapui_console'] or fts['dap-repl'] then
    state.dapui = 'console'
  end
  if state.dapui then
    require('dapui').close()
  end
  return state
end

local function restore(state)
  local win = vim.api.nvim_get_current_win()
  if state.tree then
    require('neo-tree.command').execute { action = 'show', source = 'filesystem' }
  end
  if state.aerial then
    require('aerial').open { focus = false, direction = 'right' }
  end
  for _, mode in ipairs(state.trouble or {}) do
    require('trouble').open { mode = mode, focus = false }
  end
  if state.qf then
    vim.cmd 'copen'
  end
  if state.run then
    require('pc.run').show_console()
  end
  for _, term in ipairs(state.terms or {}) do
    term:open()
  end
  if state.dapui == 'all' then
    require('dapui').open()
  elseif state.dapui == 'console' then
    require('dapui').open { layout = 2 }
  end
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

--- Restore Default Layout (Shift+F12): close every tool window, forget what was hidden
function M.reset()
  hidden = nil
  if vim.bo.buftype ~= '' then
    vim.cmd 'wincmd p'
  end
  hide()
end

function M.toggle()
  if hidden then
    local state = hidden
    hidden = nil
    restore(state)
  else
    -- leave a tool window first, so the editor keeps the focus afterwards
    if vim.bo.buftype ~= '' then
      vim.cmd 'wincmd p'
    end
    local state = hide()
    if next(state.terms or {}) or next(state.trouble or {}) or state.tree or state.aerial or state.qf or state.run or state.dapui then
      hidden = state
    end
  end
end

-- Inside tmux Ctrl+Shift+F12 arrives as F48
vim.keymap.set({ 'n', 't' }, '<C-S-F12>', M.toggle, { desc = 'Hide / restore all tool windows' })
vim.keymap.set({ 'n', 't' }, '<F48>', M.toggle, { desc = 'Hide / restore all tool windows' })

return M
