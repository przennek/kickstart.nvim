-- Hide All Tool Windows (IDEA's Ctrl+Shift+F12; Alt+Shift+F12 in your keymap, which
-- Alacritty translates to Ctrl+Shift+F12; Cmd+Shift+F12 on the Mac). First press hides every
-- tool window (project tree, structure, Find / Problems, Run, terminals, debugger, commit,
-- Maven, hierarchy, notifications, query results…), leaving only the editor windows;
-- the second press brings back exactly the ones that were open, where they were.

local M = {}

local hidden = nil

local function open_fts()
  local fts = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    fts[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] = true
  end
  return fts
end

-- Tool windows of this config's features: closed and reopened by their own module
local MODULES = {
  NeogitStatus = {
    hide = function()
      require('neogit.buffers.status').instance():close()
    end,
    show = function()
      vim.cmd 'Neogit'
    end,
  },
  pcnotifications = {
    hide = function()
      require('pc.notifications').toggle()
    end,
    show = function()
      require('pc.notifications').toggle()
    end,
  },
  pcmaven = {
    hide = function()
      require('pc.maven').toggle()
    end,
    show = function()
      require('pc.maven').toggle()
    end,
  },
  pcawsexplorer = {
    hide = function()
      require('pc.aws_explorer').toggle()
    end,
    show = function()
      require('pc.aws_explorer').toggle()
    end,
  },
  pchierarchy = {
    hide = function()
      require('pc.hierarchy').close_window()
    end,
    show = function()
      require('pc.hierarchy').show()
    end,
  },
}

-- Window options a reopened tool window gets back
local WIN_OPTS = { 'number', 'relativenumber', 'signcolumn', 'foldcolumn', 'winfixwidth', 'winfixheight', 'wrap', 'linebreak', 'list', 'cursorline', 'winbar', 'winhighlight', 'statuscolumn' }

-- A window that is not an editor window: special buffer, not floating, not part of a diff
local function tool_window(win)
  if vim.api.nvim_win_get_config(win).relative ~= '' or vim.wo[win].diff then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  if ft:match '^Diffview' or ft == 'pcdifffiles' then
    return false
  end
  return vim.bo[buf].buftype ~= ''
end

local function side(win)
  local row, col = unpack(vim.api.nvim_win_get_position(win))
  local width = vim.api.nvim_win_get_width(win)
  if width < vim.o.columns and col == 0 then
    return 'left'
  elseif width < vim.o.columns and col + width >= vim.o.columns then
    return 'right'
  end
  return row == 0 and 'top' or 'bottom'
end

-- Every other tool window: remembered (buffer, side, size, options) and closed
local function hide_others(state)
  state.modules, state.others = {}, {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and tool_window(win) and #vim.api.nvim_tabpage_list_wins(0) > 1 then
      local buf = vim.api.nvim_win_get_buf(win)
      local module = MODULES[vim.bo[buf].filetype]
      if module then
        if pcall(module.hide) then
          table.insert(state.modules, module)
        end
      else
        local opts = {}
        for _, opt in ipairs(WIN_OPTS) do
          opts[opt] = vim.wo[win][opt]
        end
        table.insert(state.others, {
          buf = buf,
          bufhidden = vim.bo[buf].bufhidden,
          side = side(win),
          width = vim.api.nvim_win_get_width(win),
          height = vim.api.nvim_win_get_height(win),
          opts = opts,
        })
        -- keep the buffer while its window is hidden
        vim.bo[buf].bufhidden = 'hide'
        pcall(vim.api.nvim_win_close, win, false)
      end
    end
  end
end

local function restore_others(state)
  for _, module in ipairs(state.modules or {}) do
    pcall(module.show)
  end
  local open = {
    left = 'topleft vertical sbuffer ',
    right = 'botright vertical sbuffer ',
    top = 'topleft sbuffer ',
    bottom = 'botright sbuffer ',
  }
  for _, w in ipairs(state.others or {}) do
    if vim.api.nvim_buf_is_valid(w.buf) then
      vim.cmd(open[w.side] .. w.buf)
      local win = vim.api.nvim_get_current_win()
      if w.side == 'left' or w.side == 'right' then
        vim.api.nvim_win_set_width(win, w.width)
      else
        vim.api.nvim_win_set_height(win, w.height)
      end
      for opt, value in pairs(w.opts) do
        pcall(function()
          vim.wo[win][opt] = value
        end)
      end
      vim.bo[w.buf].bufhidden = w.bufhidden
    end
  end
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
  hide_others(state)
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
  restore_others(state)
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

local function any_tool_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if tool_window(win) or ft == 'neo-tree' or ft == 'aerial' or ft:match '^dapui_' then
      return true
    end
  end
  return false
end

-- Diffview tabs (Git log, branch diff) are views of their own: Hide All leaves them alone
local function in_diffview()
  return package.loaded['diffview'] and require('diffview.lib').get_current_view() ~= nil
end

function M.toggle()
  if in_diffview() then
    return vim.notify('Hide All Windows: not in a diff / log tab (q closes it)', vim.log.levels.INFO)
  end
  -- like IDEA: visible tool windows are hidden first; with none visible the hidden ones return
  if not any_tool_window() and hidden then
    local state = hidden
    hidden = nil
    restore(state)
  else
    -- leave a tool window first, so the editor keeps the focus afterwards
    if vim.bo.buftype ~= '' then
      vim.cmd 'wincmd p'
    end
    local state = hide()
    if next(state.terms or {}) or next(state.trouble or {}) or next(state.modules) or next(state.others) or state.tree or state.aerial or state.qf or state.run or state.dapui then
      hidden = state
    end
  end
end

-- Inside tmux Ctrl+Shift+F12 arrives as F48
vim.keymap.set({ 'n', 't' }, '<C-S-F12>', M.toggle, { desc = 'Hide / restore all tool windows' })
vim.keymap.set({ 'n', 't' }, '<F48>', M.toggle, { desc = 'Hide / restore all tool windows' })

return M
