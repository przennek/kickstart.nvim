-- The prompt file (in.txt) of this Neovim: the agent's instructions are written here, not in a
-- file in the project (the log: in.txt in the repo, :w, Alt+I, type "read in.txt" every time).
--   Cmd/Alt+Shift+I              open it (this session's own, in Neovim's temp directory)
--   Cmd/Alt+Shift+I, selection   the selected code goes to the end of in.txt with where it is
--                                (src/Order.java:12-18 and the lines; a few words: on one line),
--                                you stay in the code (the log: v … y, Ctrl+H, a, paste, Esc,
--                                Ctrl+L for every piece of a review)
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
local function keep(lines, draft)
  if not table.concat(lines, '\n'):match '%S' then
    return nil
  end
  vim.fn.mkdir(HISTORY, 'p')
  local base = HISTORY .. '/' .. os.date '%Y-%m-%d_%H-%M-%S' .. (draft and '_draft' or '')
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

-- the file a buffer shows, as the agent can open it: relative to the project; a side of a diff
-- (diffview://<repo>/.git/<rev>/<path>, fugitive://<repo>/.git//<rev>/<path>) is its file
local function reference(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local repo, rel = name:match '^diffview://(.-)/%.git/[^/]+/(.+)$'
  if not repo then
    repo, rel = name:match '^fugitive://(.-)/%.git//%x+/(.+)$'
  end
  if repo then
    name = repo .. '/' .. rel
  end
  return name ~= '' and vim.fn.fnamemodify(name, ':~:.') or nil
end

--- Appends `lines` to in.txt (open or not) and saves it
function M.append(lines)
  local buf = vim.fn.bufadd(M.path())
  vim.fn.bufload(buf)
  local last = vim.api.nvim_buf_line_count(buf)
  local empty = last == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
  vim.api.nvim_buf_set_lines(buf, empty and 0 or last, -1, false, lines)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd 'silent! update'
  end)
end

--- The selection goes to the end of in.txt with its file and lines; you stay where you are
function M.add_selection()
  local mode = vim.fn.mode()
  local from, to = vim.fn.getpos 'v', vim.fn.getpos '.'
  local text = vim.fn.getregion(from, to, { type = mode })
  local first, last = math.min(from[2], to[2]), math.max(from[2], to[2])
  vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'nx', false)
  if not table.concat(text, ''):match '%S' then
    return
  end
  local where = reference(0)
  local at = where and (where .. ':' .. first .. (last > first and ('-' .. last) or '')) or nil
  local lines
  if #text == 1 and mode == 'v' then
    -- a name, a call, a few words: one line you go on writing after
    lines = { (at and (at .. '  ') or '') .. '`' .. vim.trim(text[1]) .. '`' }
  else
    lines = { at or 'code:', '```' .. vim.bo.filetype }
    vim.list_extend(lines, text)
    vim.list_extend(lines, { '```', '' })
  end
  M.append(lines)
  vim.notify(('Added to in.txt: %s'):format(at or (#text .. ' line(s)')), vim.log.levels.INFO)
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
          local name, draft = vim.fn.fnamemodify(file, ':t:r'):gsub('_draft', '')
          -- 2026-11-13_14-09-33 -> 2026-11-13 14:09:33
          local day, time = name:match '^(.-)_(.+)$'
          local when = day and (day .. ' ' .. time:gsub('-', ':')) or name
          return { value = file, display = when .. (draft > 0 and '  (not sent)' or '') .. '  ' .. first, ordinal = table.concat(vim.fn.readfile(file), ' '), path = file }
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

-- in.txt lives in Neovim's temp directory and goes with it: text not handed to the agent yet is
-- kept in the prompt history as "(not sent)" (Space sH brings it back)
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = vim.api.nvim_create_augroup('pc-prompt-draft', { clear = true }),
  callback = function()
    local buf = vim.fn.bufnr(M.path())
    local ok, lines = pcall(function()
      return buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or vim.fn.readfile(M.path())
    end)
    if ok then
      keep(lines, true)
    end
  end,
})

vim.keymap.set('n', '<leader>sH', M.history, { desc = 'Prompt history (handed to the agent)' })

vim.keymap.set({ 'n', 'i' }, '<M-I>', function()
  vim.cmd 'stopinsert'
  M.key()
end, { desc = 'Prompt file (in.txt); in it: hand it to the agent' })
vim.keymap.set('x', '<M-I>', function()
  if is_prompt(0) then
    vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'nx', false)
    return M.key()
  end
  M.add_selection()
end, { desc = 'Add the selection to the prompt file (in.txt)' })

return M
