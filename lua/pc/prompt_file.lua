-- The prompt file (in.txt) of this Neovim: the agent's instructions are written here, not in a
-- file in the project (the log: in.txt in the repo, :w, Alt+I, type "read in.txt" every time).
--   Cmd/Alt+Shift+I              open it (this session's own, in Neovim's temp directory)
--   Cmd/Alt+Shift+I in it        save it and hand it to the agent: the agent terminal opens and
--                                gets "Read <file> and do what it says"
--   Alt+I                        the agent terminal, as before
-- The agent terminal starts the agent itself the first time (vim.g.pc_agent_cmd, else the first
-- installed of kiro-cli, claude, q), told where this file is; vim.g.pc_agent_cmd = false keeps a
-- plain shell. Terminals started from this Neovim also have it in $PC_PROMPT_FILE.

local M = {}

local AGENTS = { { 'kiro-cli', 'kiro-cli chat' }, { 'claude', 'claude' }, { 'q', 'q chat' } }

local path

function M.path()
  if not path then
    path = vim.fs.joinpath(vim.fn.fnamemodify(vim.fn.tempname(), ':h'), 'in.txt')
    if not vim.uv.fs_stat(path) then
      vim.fn.writefile({}, path)
    end
  end
  return path
end

vim.env.PC_PROMPT_FILE = M.path()

local function read_message()
  return 'Read ' .. M.path() .. ' and do what it says.'
end

--- The shell command that starts the agent with `message` as its first prompt, or nil (no agent)
function M.agent_command(message)
  local cmd = vim.g.pc_agent_cmd
  if cmd == false then
    return nil
  end
  if not cmd then
    for _, agent in ipairs(AGENTS) do
      if vim.fn.executable(agent[1]) == 1 then
        cmd = agent[2]
        break
      end
    end
  end
  if not cmd then
    return nil
  end
  message = message
    or ('My instructions for you in this session are in the file ' .. M.path() .. ". Nothing to do yet: when I send you that path, read the file and do what it says.")
  return cmd .. ' ' .. vim.fn.shellescape(message)
end

local function is_prompt(buf)
  return vim.fs.normalize(vim.api.nvim_buf_get_name(buf)) == vim.fs.normalize(M.path())
end

--- Opens the prompt file; in it, saves it and hands it to the agent
function M.key()
  if not is_prompt(0) then
    vim.cmd.edit(vim.fn.fnameescape(M.path()))
    return
  end
  vim.cmd 'silent! update'
  local term = require 'pc.fullscreen_terminal'
  if term.started 'Agent' then
    term.toggle_agent()
    vim.defer_fn(function()
      term.send('Agent', read_message() .. '\r')
    end, 200)
  else
    -- a new agent gets the file as its first prompt
    term.toggle_agent(M.agent_command(read_message()))
  end
end

local modes = { 'n', 'i', 'x' }
vim.keymap.set(modes, '<M-I>', function()
  vim.cmd 'stopinsert'
  M.key()
end, { desc = 'Prompt file (in.txt); in it: hand it to the agent' })

return M
