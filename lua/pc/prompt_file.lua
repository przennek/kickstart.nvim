-- The prompt file (in.txt) of this Neovim: the agent's instructions are written here, not in a
-- file in the project (the log: in.txt in the repo, :w, Alt+I, type "read in.txt" every time).
--   Cmd/Alt+Shift+I              open it (this session's own, in Neovim's temp directory)
--   Cmd/Alt+Shift+I in it        hand it to the agent: the text goes to the prompt history
--                                (stdpath('state')/prompts/<time>.txt), the agent terminal
--                                opens and gets "Read <that file> and do what it says", in.txt is
--                                empty for the next one
--   Space sH                     the prompt history, newest first; Enter puts one back in in.txt
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

local HISTORY = vim.fn.stdpath 'state' .. '/prompts'

local function read_message(file)
  return 'Read ' .. file .. ' and do what it says.'
end

-- the text of in.txt into a file of its own (the agent reads that one, in.txt can be emptied at
-- once); nil when in.txt is empty
local function keep(lines)
  if not table.concat(lines, '\n'):match '%S' then
    return nil
  end
  vim.fn.mkdir(HISTORY, 'p')
  local base = HISTORY .. '/' .. os.date '%Y-%m-%d_%H-%M-%S'
  local file, n = base .. '.txt', 1
  while vim.uv.fs_stat(file) do
    n = n + 1
    file = base .. '-' .. n .. '.txt'
  end
  vim.fn.writefile(lines, file)
  return file
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
  local file = keep(vim.api.nvim_buf_get_lines(0, 0, -1, false))
  if not file then
    return vim.notify('in.txt is empty: nothing to hand to the agent', vim.log.levels.INFO)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
  vim.cmd 'silent! write'
  local term = require 'pc.fullscreen_terminal'
  if term.started 'Agent' then
    term.toggle_agent()
    vim.defer_fn(function()
      term.send('Agent', read_message(file) .. '\r')
    end, 200)
  else
    -- a new agent gets the file as its first prompt
    term.toggle_agent(M.agent_command(read_message(file)))
  end
end

--- The prompts handed to the agent, newest first; Enter puts one in in.txt again
function M.history()
  local files = vim.fn.reverse(vim.fn.sort(vim.fn.glob(HISTORY .. '/*.txt', true, true)))
  if #files == 0 then
    return vim.notify('No prompts handed to the agent yet', vim.log.levels.INFO)
  end
  local conf = require('telescope.config').values
  local actions, state = require 'telescope.actions', require 'telescope.actions.state'
  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Prompt History  ·  Enter: back into in.txt',
      finder = require('telescope.finders').new_table {
        results = files,
        entry_maker = function(file)
          local first = (vim.fn.readfile(file, '', 1)[1] or ''):gsub('^%s+', '')
          local when = vim.fn.fnamemodify(file, ':t:r'):gsub('_', ' '):gsub('(%d+)-(%d+)-(%d+)$', '%1:%2:%3')
          return { value = file, display = when .. '  ' .. first, ordinal = table.concat(vim.fn.readfile(file), ' '), path = file }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = conf.file_previewer {},
      attach_mappings = function(prompt)
        actions.select_default:replace(function()
          local file = state.get_selected_entry().value
          actions.close(prompt)
          vim.cmd.edit(vim.fn.fnameescape(M.path()))
          vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn.readfile(file))
        end)
        return true
      end,
    })
    :find()
end

vim.keymap.set('n', '<leader>sH', M.history, { desc = 'Prompt history (handed to the agent)' })

local modes = { 'n', 'i', 'x' }
vim.keymap.set(modes, '<M-I>', function()
  vim.cmd 'stopinsert'
  M.key()
end, { desc = 'Prompt file (in.txt); in it: hand it to the agent' })

return M
