-- Context menu like IDEA's: right click shows the actions of the place clicked, with their
-- shortcuts (Neovim's own mouse menu, filled anew for every click):
--   project tree   New…, Copy (F5), Rename, Move, Delete, Copy Path, Compare With, Run / Debug
--                  (tests of a directory), Local History, Git history; on a directory Open in
--                  Terminal
--   editor         Show Context Actions, Go To, Find Usages, Refactor (Rename, Extract…),
--                  Generate, Reformat, Run / Debug, Copy Reference, Git, Local History, Paste…;
--                  with a selection: Cut / Copy / Paste, Extract, Surround With, Compare with
--                  Clipboard, Git history of the selection
-- Every entry runs the action's own mapping, so the menu and the shortcut always agree; entries
-- whose mapping the buffer has not got (no LSP, no git…) are left out.

local M = {}

local actions = {}

--- Runs the menu entry `i` (called by the menu items)
function M.run(i)
  local fn = actions[i]
  if fn then
    fn()
  end
end

-- runs a mapping as if typed (<leader> = space); `visual`: right away, while the selection
-- is still there (the menu ends Visual mode afterwards)
local function keys(lhs, visual)
  return function()
    vim.api.nvim_feedkeys(vim.keycode((lhs:gsub('<leader>', ' '))), visual and 'mx' or 'm', false)
  end
end

local function mapped(lhs, mode)
  local key = vim.keycode((lhs:gsub('<leader>', ' ')))
  return vim.fn.maparg(key, mode) ~= '' or vim.fn.maparg(lhs, mode) ~= ''
end

-- menu names: special characters escaped (the terminal's menu shows no <Tab> part, so the
-- shortcut is padded into the label, right-aligned)
local function esc(s)
  return (s:gsub('&', '&&'):gsub('[%s.\\|]', '\\%0'))
end

-- items: { label, run, shortcut } or '-' (separator); double separators dropped. `visual`: the
-- entries keep the selection (vnoremenu) instead of ending it
local function fill(items, visual)
  pcall(vim.cmd, 'aunmenu PopUp')
  actions = {}
  local width = 0
  for _, item in ipairs(items) do
    if item ~= '-' then
      width = math.max(width, vim.fn.strdisplaywidth(item[1]))
    end
  end
  local cmd = visual and 'vnoremenu' or 'nnoremenu'
  local last_sep = true
  for i, item in ipairs(items) do
    if item == '-' then
      if not last_sep then
        vim.cmd(('%s PopUp.-%d- <Nop>'):format(cmd, i))
        last_sep = true
      end
    else
      actions[i] = item[2]
      local label = item[1]
      if item[3] then
        label = label .. string.rep(' ', width - vim.fn.strdisplaywidth(label) + 4) .. item[3]
      end
      vim.cmd(('%s <silent> PopUp.%s <Cmd>lua require("pc.context_menu").run(%d)<CR>'):format(cmd, esc(label), i))
      last_sep = false
    end
  end
end

---------------------------------------------------------------------------
-- Project tree
---------------------------------------------------------------------------

local function tree_items()
  local state = require('neo-tree.sources.manager').get_state 'filesystem'
  local node = state and state.tree and state.tree:get_node()
  if not node then
    return {}
  end
  local commands = require 'neo-tree.sources.filesystem.commands'
  local path, dir = node.path, node.type == 'directory'
  local folder = dir and path or vim.fs.dirname(path)
  local function cmd(name)
    return function()
      commands[name](state)
    end
  end
  local function in_editor(fn)
    return function()
      vim.cmd 'wincmd p'
      fn()
    end
  end
  local function copy(text)
    return function()
      vim.fn.setreg('+', text)
      vim.fn.setreg('"', text)
      vim.notify('Copied ' .. text)
    end
  end
  local items = {}
  local function add(item, when)
    if when ~= false then
      table.insert(items, item)
    end
  end
  add { 'New…', function()
    require('pc.new_element').menu(folder)
  end, 'Alt+Insert' }
  add '-'
  add({ 'Copy…', in_editor(function()
    require('pc.copy_class').copy(path)
  end), 'F5' }, not dir)
  add { 'Rename…', cmd 'rename', 'r' }
  add { 'Move…', cmd 'move', 'm' }
  add { 'Delete…', cmd 'delete', 'd' }
  add '-'
  add { 'Copy Absolute Path', copy(path) }
  add { 'Copy Path from Project Root', copy(vim.fn.fnamemodify(path, ':.')) }
  add { 'Copy File Name', copy(vim.fs.basename(path)) }
  add({ 'Compare With…', function()
    require('pc.compare_files').mark(path)
  end, '=' }, not dir)
  add '-'
  add { dir and 'Run All Tests' or 'Run', keys '<C-S-F10>', 'Ctrl+Shift+F10' }
  add { dir and 'Debug All Tests' or 'Debug', keys '<C-S-F9>', 'Ctrl+Shift+F9' }
  add '-'
  add({ 'Open in Terminal', function()
    vim.cmd 'wincmd p'
    -- focus goes to the terminal, like IDEA's Open In → Terminal
    require('toggleterm').exec('cd ' .. vim.fn.shellescape(path), nil, nil, nil, nil, nil, false)
    vim.cmd 'startinsert'
  end }, dir)
  add({ 'Local History', in_editor(function()
    vim.cmd.edit(vim.fn.fnameescape(path))
    require('pc.local_history').show()
  end), '␣vH' }, not dir)
  add { 'Git: Show History', in_editor(function()
    vim.cmd('DiffviewFileHistory ' .. vim.fn.fnameescape(path))
  end) }
  add '-'
  add { 'Refresh', cmd 'refresh', 'R' }
  return items
end

---------------------------------------------------------------------------
-- Editor
---------------------------------------------------------------------------

-- { label, lhs, shortcut shown } — in the menu only where the buffer has the mapping
local NORMAL = {
  { 'Show Context Actions', '<M-CR>', 'Alt+Enter' },
  '-',
  { 'Go to Declaration', 'gd', 'Alt+B' },
  { 'Go to Implementation(s)', 'gI', 'Ctrl+Alt+B' },
  { 'Go to Super Method', '<M-u>', 'Alt+U' },
  { 'Go to Test', '<M-T>', 'Alt+Shift+T' },
  { 'Find Usages', '<leader>f', 'Alt+F7' },
  { 'Call Hierarchy', '<leader>h', '␣h' },
  { 'Type Hierarchy', '<M-8>', 'Alt+8' },
  '-',
  { 'Rename…', '<leader>rn', 'Shift+F6' },
  { 'Extract Variable', '<leader>ev', '␣ev' },
  { 'Move…', '<F6>', 'F6' },
  { 'Copy Class…', '<F5>', 'F5' },
  { 'Generate…', '<leader>g', 'Alt+Insert' },
  { 'Reformat Code', '<M-L>', 'Alt+Shift+L' },
  { 'Optimize Imports', '<M-O>', 'Alt+Shift+O' },
  '-',
  { 'Run', '<C-S-F10>', 'Ctrl+Shift+F10' },
  { 'Debug', '<C-S-F9>', 'Ctrl+Shift+F9' },
  { 'Toggle Breakpoint', '<M-F8>', 'Alt+F8' },
  '-',
  { 'Copy Reference', '<leader>yr', 'Alt+Shift+C' },
  { 'Copy Path / Reference…', '<leader>yp', '␣yp' },
  { 'Paste', '"+gP', 'Ctrl+V' },
  { 'Compare with Clipboard', '<leader>vy', '␣vy' },
  '-',
  { 'Git: Annotate', '<leader>va', '␣va' },
  { 'Git: Show History', '<leader>vh', '␣vh' },
  { 'Git: Show Diff', '<M-d>', 'Alt+D' },
  { 'Git: Rollback Change', '<leader>vr', '␣vr' },
  { 'Local History', '<leader>vH', '␣vH' },
}

local VISUAL = {
  { 'Cut', '"+d', 'Ctrl+X' },
  { 'Copy', '"+y', 'Ctrl+C' },
  { 'Paste', '"+P', 'Ctrl+V' },
  '-',
  { 'Show Context Actions', '<M-CR>', 'Alt+Enter' },
  { 'Extract Variable', '<leader>ev', '␣ev' },
  { 'Extract Method', '<leader>em', 'Ctrl+Alt+M' },
  { 'Surround With…', '<leader>es', '␣es' },
  { 'Reformat Code', '<M-L>', 'Alt+Shift+L' },
  '-',
  { 'Compare with Clipboard', '<leader>vy', '␣vy' },
  { 'Git: Show History for Selection', '<leader>vh', '␣vh' },
}

local function editor_items(visual)
  local mode = visual and 'x' or 'n'
  local items = {}
  for _, item in ipairs(visual and VISUAL or NORMAL) do
    if item == '-' then
      table.insert(items, '-')
    elseif item[2]:match '^"%+' or mapped(item[2], mode) then
      local lhs = item[2]
      table.insert(items, { item[1], lhs:match '^"%+' and function()
        vim.cmd('normal! ' .. lhs)
      end or keys(lhs, visual), item[3] })
    end
  end
  return items
end

---------------------------------------------------------------------------

local function on_popup()
  local ft = vim.bo.filetype
  local mode = vim.fn.mode()
  local visual = mode:match '^[vV\22]' ~= nil
  if ft == 'neo-tree' then
    fill(tree_items())
  elseif vim.bo.buftype == '' and vim.api.nvim_buf_get_name(0) ~= '' then
    fill(editor_items(visual), visual)
  else
    -- tool windows, terminals, dialogs: just the clipboard
    fill(visual and { { 'Copy', function()
      vim.cmd 'normal! "+y'
    end, 'Ctrl+C' } } or { { 'Paste', function()
      if vim.bo.buftype == 'terminal' then
        -- typed into the shell, and back to typing
        vim.api.nvim_chan_send(vim.bo.channel, vim.fn.getreg '+')
        vim.cmd 'startinsert'
      elseif vim.bo.modifiable then
        vim.cmd 'normal! "+gP'
      end
    end, 'Ctrl+V' } }, visual)
  end
end

-- Neovim's default mouse menu (Go to definition, diagnostics…) is replaced
pcall(vim.api.nvim_del_augroup_by_name, 'nvim.popupmenu')
vim.api.nvim_create_autocmd('MenuPopup', {
  group = vim.api.nvim_create_augroup('pc-context-menu', { clear = true }),
  desc = 'IDEA-like context menu',
  callback = function()
    local ok, err = pcall(on_popup)
    if not ok then
      vim.notify('Context menu: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end,
})

return M
