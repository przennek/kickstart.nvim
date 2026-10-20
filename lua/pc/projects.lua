-- Project windows, like the FrameSwitcher plugin: every project is a tmux session
-- (same naming as ~/.local/bin/tmux-sessionizer).
--   Alt+F2, <leader>P   pick a project: open sessions first, then directories
--                       from ~/Projects, ~/IdeaProjects and ~/.config

local M = {}

local ROOTS = { '~/Projects', '~/IdeaProjects', '~/.config' }

local function in_tmux()
  return vim.env.TMUX ~= nil
end

local function tmux(args)
  return vim.system(vim.list_extend({ 'tmux' }, args), { text = true }):wait()
end

local function session_name(dir)
  return (vim.fs.basename(dir):gsub('%.', '_'))
end

-- Open sessions, most recently used first
local function sessions()
  local out = tmux({ 'list-sessions', '-F', '#{session_last_attached} #{session_name} #{session_path}' }).stdout or ''
  local list = {}
  for line in out:gmatch '[^\n]+' do
    local time, name, path = line:match '^(%d*) (%S+) (.*)$'
    table.insert(list, { time = tonumber(time) or 0, name = name, path = path })
  end
  table.sort(list, function(a, b)
    return a.time > b.time
  end)
  return list
end

local function open(dir)
  if not in_tmux() then
    vim.cmd.tcd(vim.fn.fnameescape(dir))
    return require('telescope.builtin').find_files()
  end
  local name = session_name(dir)
  if tmux({ 'has-session', '-t=' .. name }).code ~= 0 then
    tmux { 'new-session', '-ds', name, '-c', dir }
  end
  tmux { 'switch-client', '-t', name }
end

function M.pick()
  local items, seen = {}, {}
  local current = in_tmux() and vim.trim(tmux({ 'display-message', '-p', '#S' }).stdout or '') or nil
  if in_tmux() then
    for _, s in ipairs(sessions()) do
      if s.name ~= current then
        table.insert(items, { label = '● ' .. s.name, dir = s.path })
        seen[s.name] = true
      end
    end
  end
  for _, root in ipairs(ROOTS) do
    for name, type in vim.fs.dir(vim.fn.expand(root)) do
      local dir = vim.fn.expand(root) .. '/' .. name
      if type == 'directory' and not seen[session_name(dir)] and session_name(dir) ~= current then
        table.insert(items, { label = '  ' .. vim.fn.fnamemodify(dir, ':~'), dir = dir })
      end
    end
  end
  vim.ui.select(items, {
    prompt = 'Switch project (● = open)',
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    if item then
      open(item.dir)
    end
  end)
end

-- Alt+F2 arrives as F50 inside tmux
vim.keymap.set('n', '<M-F2>', M.pick, { desc = 'Switch Project' })
vim.keymap.set('n', '<F50>', M.pick, { desc = 'Switch Project' })
vim.keymap.set('n', '<leader>P', M.pick, { desc = 'Switch Project' })

return M
