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

-- Leaves typing and moves; staying in the same window (no split / pane that way) types in the
-- shell again
function M.navigate(dir)
  local win = vim.api.nvim_get_current_win()
  vim.cmd('TmuxNavigate' .. dir)
  if vim.api.nvim_get_current_win() == win and vim.bo.buftype == 'terminal' then
    vim.cmd 'startinsert'
  end
end

return M
