-- Ctrl+H/J/K/L from a terminal window (vim-tmux-navigator's own terminal mappings are Vim's:
-- `<C-w>:` in Neovim types the command into the shell)

local M = {}

-- Is a program (fzf, less, vim, htop, a database TUI…) in the terminal's foreground instead of the
-- shell? Then the key is that program's. (`ps`: /proc is Linux only, on macOS the key always moved
-- and hid lazysql)
function M.program_running(buf)
  local pid = vim.b[buf].terminal_job_pid
  if not pid then
    return false
  end
  local out = vim.system({ 'ps', '-o', 'tpgid=', '-p', tostring(pid) }, { text = true }):wait()
  local tpgid = out.code == 0 and tonumber(vim.trim(out.stdout or ''))
  return tpgid ~= nil and tpgid > 0 and tpgid ~= pid
end

--- Keys for an expr mapping of Ctrl+<key> in Terminal mode
function M.keys(key, dir)
  if M.program_running(vim.api.nvim_get_current_buf()) then
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
