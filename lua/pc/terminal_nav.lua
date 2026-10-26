-- Ctrl+H/J/K/L from a terminal window (vim-tmux-navigator's own terminal mappings are Vim's:
-- `<C-w>:` in Neovim types the command into the shell)

local M = {}

-- Is a program (fzf, less, vim, htop…) in the terminal's foreground instead of the shell? Then
-- the key is that program's. (/proc: the foreground process group of the shell's tty; without
-- /proc, e.g. on macOS, the key always moves)
local function program_running(buf)
  local pid = vim.b[buf].terminal_job_pid
  local f = pid and io.open('/proc/' .. pid .. '/stat')
  if not f then
    return false
  end
  local stat = f:read '*a'
  f:close()
  local fields = vim.split(vim.trim(stat:match '%)(.*)$' or ''), ' ')
  return fields[6] ~= nil and tonumber(fields[6]) ~= pid
end

--- Keys for an expr mapping of Ctrl+<key> in Terminal mode
function M.keys(key, dir)
  if program_running(vim.api.nvim_get_current_buf()) then
    return '<C-' .. key .. '>'
  end
  return ('<C-\\><C-n><cmd>lua require("pc.terminal_nav").navigate %q<cr>'):format(dir)
end

-- Is this Neovim's tmux pane (still) the active one? true outside tmux
local function own_pane_active()
  local pane = vim.env.TMUX_PANE
  if not (vim.env.TMUX and pane) then
    return true
  end
  local out = vim.system({ 'tmux', 'display-message', '-p', '-t', pane, '#{pane_active}' }, { text = true }):wait()
  return out.code ~= 0 or vim.trim(out.stdout) == '1'
end

-- Leaves typing and moves; staying in the same window (no split / pane that way) types in the
-- shell again. Ctrl+L with nothing to the right clears the screen as in any terminal (the tmux
-- prefix + Ctrl+L sends the same key)
function M.navigate(dir)
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd('TmuxNavigate' .. dir)
  if vim.api.nvim_get_current_win() == win and vim.bo.buftype == 'terminal' then
    vim.cmd 'startinsert'
    if dir == 'Right' and own_pane_active() then
      pcall(vim.api.nvim_chan_send, vim.bo[buf].channel, vim.keycode '<C-l>')
    end
  end
end

return M
