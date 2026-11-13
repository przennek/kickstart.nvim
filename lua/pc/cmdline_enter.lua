-- Enter on the command / search line does what you meant:
--   :Wq :W :Q :Qa :WQ :Vs :Sp… (Shift held a moment too long) are :wq :w :q :qa :vs :sp…
--   :q typed while text is selected (:'<,'>q, E16) is :q
--   :q / :qa with unsaved text in a buffer without a name asks save / discard / cancel (not E37)
--   :q / :q! in a diff (Diffview, the split diff) closes the diff (it was an abbreviation, and :q!
--   became "lua …close()!", E5107)
--   / or ? text that finds nothing as a Vim pattern but is in the file as typed ($PATH, ~/.local,
--   items[0]) is searched as typed, as IDEA's Find does ($ . ~ [ * are special in a pattern)

local M = {}

--- true while a command typed with ! (:q!, :qa!, :wq!) runs: pc.autosave does not save before
--- such a quit. (It looked at the last line of the command history, which is some older command
--- when the quit comes from ZZ, Ctrl+W q or a mapping.)
M.bang = false

--- the buffer a typed :q! throws away (see M.enter), nil otherwise; pc.autosave must not write it
M.discard = nil

local QUIT = { q = true, qa = true, wq = true, wqa = true, x = true, xa = true, Q = true, Wq = true, WQ = true }
local TYPO = { W = true, Wq = true, WQ = true, Q = true, Qa = true, QA = true, Wa = true, WA = true, Wqa = true, WQa = true, WQA = true, X = true, Xa = true }

function M.enter()
  local kind, line = vim.fn.getcmdtype(), vim.fn.getcmdline()
  if kind == ':' then
    -- :q typed with a selection becomes :'<,'>q (E16): the range goes
    local ranged = line:match "^'<,'>%s*(%a+!?)%s*$"
    if ranged and QUIT[ranged:gsub('!$', '')] then
      line = ranged
    end
    local cmd, bang = line:match '^%s*(%a+)(!?)%s*$'
    if bang == '!' then
      M.bang = true
      -- after the command has run
      vim.schedule(function()
        M.bang = false
      end)
    end
    if (cmd == 'q' or cmd == 'Q') and require('pc.diff_ui').active() then
      return '<C-u>lua require("pc.diff_ui").close()<CR>'
    end
    -- :q! on a window whose buffer is shown nowhere else: the changes go away with the window. Vim
    -- would keep the buffer hidden and modified, and autosave (WinLeave) would then save exactly
    -- what you threw away. A buffer still shown in another window stays as it is (saved as usual).
    -- Limits: what the 1 s timer already wrote is on disk (and in Local History, which keeps every
    -- saved version): only what is not written yet can be discarded.
    local buf = vim.api.nvim_get_current_buf()
    if bang == '!' and cmd and cmd:lower() == 'q' and vim.bo[buf].modified and vim.bo[buf].buftype == '' and #vim.fn.win_findbuf(buf) == 1 then
      M.discard = buf
      vim.schedule(function()
        -- after the window is gone; a new file that was never written leaves no file either
        if M.discard == buf and vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
        M.discard = nil
      end)
    end
    -- :Vs, :Sp, :Wq… : a command that does not exist, written small it does
    local typo = cmd and (TYPO[cmd] or (cmd:match '^%u' and vim.fn.exists(':' .. cmd) == 0 and vim.fn.exists(':' .. cmd:lower()) > 0))
    if typo then
      cmd = cmd:lower()
      line = cmd .. bang
    end
    -- :q / :qa with unsaved text in a buffer without a name (autosave cannot keep it): one
    -- question, save / discard / cancel, instead of E37 (the log: :qa, :q, :qa, then :q!)
    local quit = cmd and bang == '' and QUIT[cmd:lower()] and cmd:lower()
    if quit then
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].modified and vim.bo[buf].buftype == '' and vim.api.nvim_buf_get_name(buf) == '' then
          return '<C-u>confirm ' .. quit .. '<CR>'
        end
      end
    end
    if ranged or typo then
      return '<C-u>' .. line .. '<CR>'
    end
  elseif (kind == '/' or kind == '?') and line ~= '' and not line:find '^\\V' then
    local ok, found = pcall(vim.fn.search, line, 'nw')
    if not ok or found == 0 then
      local literal = '\\V' .. line:gsub('\\', '\\\\')
      if vim.fn.search(literal, 'nw') > 0 then
        return '<C-u>' .. literal:gsub('<', '<lt>') .. '<CR>'
      end
    end
  end
  return '<CR>'
end

vim.keymap.set('c', '<CR>', M.enter, { expr = true, desc = 'Run / search what you meant' })

return M
