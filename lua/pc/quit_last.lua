-- :q / :wq on the last file closes Neovim, as closing IDEA's last editor would not leave the tool
-- windows behind: the log had :q, then :qa, with the terminal (or the tree) still open. Files
-- are saved first (pc.autosave); a program running in a terminal (a build, Kiro) keeps Neovim
-- open and says so, the shell at its prompt does not.

local function editor(win)
  return vim.api.nvim_win_get_config(win).relative == '' and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ''
end

local function running_program()
  local nav = require 'pc.terminal_nav'
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == 'terminal' and vim.api.nvim_buf_is_loaded(buf) and nav.program_running(buf) then
      return vim.api.nvim_buf_get_name(buf)
    end
  end
end

vim.api.nvim_create_autocmd('QuitPre', {
  group = vim.api.nvim_create_augroup('pc-quit-last', { clear = true }),
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if #vim.api.nvim_list_tabpages() > 1 or not editor(win) then
      return
    end
    local wins = vim.api.nvim_tabpage_list_wins(0)
    for _, w in ipairs(wins) do
      if w ~= win and editor(w) then
        return
      end
    end
    if #vim.tbl_filter(function(w)
      return vim.api.nvim_win_get_config(w).relative == ''
    end, wins) < 2 then
      return
    end
    -- after this :q has closed the file (and :wq written it)
    vim.schedule(function()
      local program = running_program()
      if program then
        return vim.notify('A program still runs in ' .. vim.fn.fnamemodify(program, ':t') .. ': :qa! ends it with Neovim', vim.log.levels.WARN)
      end
      require('pc.autosave').save()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].buftype == '' and vim.bo[buf].modified then
          return
        end
      end
      vim.cmd 'qa!'
    end)
  end,
})
