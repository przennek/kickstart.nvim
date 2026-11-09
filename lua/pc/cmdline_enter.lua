-- Enter on the command / search line does what you meant:
--   :Wq :W :Q :Qa :WQ… (Shift held a moment too long) are :wq :w :q :qa…
--   :q / :q! in a diff (Diffview, the split diff) closes the diff (it was an abbreviation, and :q!
--   became "lua …close()!", E5107)
--   / or ? text that finds nothing as a Vim pattern but is in the file as typed ($PATH, ~/.local,
--   items[0]) is searched as typed, as IDEA's Find does ($ . ~ [ * are special in a pattern)

local M = {}

local TYPO = { W = true, Wq = true, WQ = true, Q = true, Qa = true, QA = true, Wa = true, WA = true, Wqa = true, WQa = true, WQA = true, X = true, Xa = true }

function M.enter()
  local kind, line = vim.fn.getcmdtype(), vim.fn.getcmdline()
  if kind == ':' then
    local cmd, bang = line:match '^%s*(%a+)(!?)%s*$'
    if (cmd == 'q' or cmd == 'Q') and require('pc.diff_ui').active() then
      return '<C-u>lua require("pc.diff_ui").close()<CR>'
    end
    if cmd and TYPO[cmd] then
      return '<C-u>' .. cmd:lower() .. bang .. '<CR>'
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
