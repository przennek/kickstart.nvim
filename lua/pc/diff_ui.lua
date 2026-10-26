-- One way out of every diff and a label on each side, whatever opened it (Show Diff, a branch,
-- Compare with Revision / Diffview, Compare With…, Local History, Compare with Clipboard):
--   q, Back (Ctrl+Shift+P / Alt+H) and :q   close the whole diff and return to where you were
--                                            (Back used to step back in one side only)
--   winbar of each side                       ◀ Previous · <revision>   |   Current · working copy ▶
--                                            (Next · <revision> when both sides are revisions)
--   back from the terminal / another app       the diff is shown again for the new state

local M = {}

local function normal_wins(tab)
  return vim.tbl_filter(function(w)
    return vim.api.nvim_win_get_config(w).relative == ''
  end, vim.api.nvim_tabpage_list_wins(tab or 0))
end

local function diffview_open()
  if not package.loaded['diffview'] then
    return false
  end
  local ok, lib = pcall(require, 'diffview.lib')
  return ok and lib.get_current_view() ~= nil
end

--- Is the current window part of a diff?
function M.active()
  if vim.wo.diff or diffview_open() then
    return true
  end
  local sd = package.loaded['pc.split_diff']
  return sd ~= nil and sd.current() ~= nil
end

--- Closes the diff the current window belongs to; false when it is not in one
function M.close()
  local sd = package.loaded['pc.split_diff']
  if sd and sd.close() then
    return true
  end
  if diffview_open() then
    vim.cmd 'DiffviewClose'
    return true
  end
  if not vim.wo.diff then
    return false
  end
  local wins = normal_wins()
  local own_tab = #vim.api.nvim_list_tabpages() > 1 and vim.iter(wins):all(function(w)
    return vim.wo[w].diff
  end)
  vim.cmd 'diffoff!'
  if own_tab then
    vim.cmd 'tabclose'
    return true
  end
  -- a diff among other windows: the revision / scratch side goes, the file stays
  for _, w in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(w)
    if vim.bo[buf].buftype ~= '' or vim.api.nvim_buf_get_name(buf):match '^%a+://' then
      pcall(vim.api.nvim_win_close, w, false)
    end
  end
  return true
end

---------------------------------------------------------------------------
-- Labels
---------------------------------------------------------------------------

-- "  2 days ago · Fix the discount" of a commit (asked once per commit)
local infos = {}
local function commit_info(rev, name)
  if infos[rev] == nil then
    local root = name:match '^%a+://(.-)/%.git/' or vim.fn.getcwd()
    local out = vim.system({ 'git', '-C', root, 'log', '-1', '--format=%ar · %s', rev }, { text = true }):wait()
    local text = out.code == 0 and vim.trim(out.stdout) or ''
    infos[rev] = text ~= '' and ('  ' .. vim.fn.strcharpart(text, 0, 60)) or ''
  end
  return infos[rev]
end

-- What a diff side shows: { kind = 'file' | 'revision' | 'other', text }
local function describe(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local rev = name:match '^fugitive://.-//(%x+)/' or name:match '^diffview://.-/%.git/([^/]+)/'
  if rev then
    if rev == '0' or rev == ':0:' then
      return { kind = 'revision', text = 'staged (index)' }
    elseif rev == 'null' then
      return { kind = 'revision', text = 'none' }
    end
    return { kind = 'revision', text = rev:sub(1, 8) .. commit_info(rev, name) }
  end
  local stamp = name:match ' @ (%d+%-%d+%-%d+ [%d:]+)$'
  if stamp then
    return { kind = 'revision', text = 'Local History ' .. stamp }
  end
  if vim.bo[buf].buftype == '' and name ~= '' then
    return { kind = 'file', text = vim.fn.fnamemodify(name, ':~:.') }
  end
  return { kind = 'other', text = name ~= '' and vim.fs.basename(name) or 'scratch' }
end

local function esc(s)
  return (s:gsub('%%', '%%%%'))
end

local function set_label(win, text)
  vim.w[win].pc_diff_label = true
  vim.wo[win].winbar = text
end

local function update()
  local diffs = vim.tbl_filter(function(w)
    return vim.wo[w].diff
  end, normal_wins())
  -- labels only for a two-way diff (a merge has its own)
  if #diffs == 2 then
    table.sort(diffs, function(a, b)
      return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
    end)
    local left, right = describe(vim.api.nvim_win_get_buf(diffs[1])), describe(vim.api.nvim_win_get_buf(diffs[2]))
    local both_files = left.kind == 'file' and right.kind == 'file'
    local lname = both_files and 'Left' or (left.kind == 'other' and left.text or 'Previous')
    local rname = both_files and 'Right' or (right.kind == 'file' and 'Current') or (right.kind == 'revision' and 'Next') or right.text
    local ltext = (left.kind == 'other' and not both_files) and '' or (' · ' .. left.text)
    local rtext = right.kind == 'file' and (both_files and (' · ' .. right.text) or ' · working copy') or (right.kind == 'revision' and (' · ' .. right.text) or '')
    set_label(diffs[1], ('%%#DiffDelete# ◀ %s %%*%%#Comment#%s%%*'):format(esc(lname), esc(ltext)))
    set_label(diffs[2], ('%%#DiffAdd# %s ▶ %%*%%#Comment#%s%%*'):format(esc(rname), esc(rtext)))
  end
  -- a window that left its diff loses the label
  for _, w in ipairs(normal_wins()) do
    if vim.w[w].pc_diff_label and not (vim.wo[w].diff and #diffs == 2) then
      vim.w[w].pc_diff_label = nil
      vim.wo[w].winbar = ''
    end
  end
end

local group = vim.api.nvim_create_augroup('pc-diff-ui', { clear = true })
vim.api.nvim_create_autocmd({ 'OptionSet' }, { group = group, pattern = 'diff', callback = vim.schedule_wrap(update) })
vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter', 'TabEnter', 'DiffUpdated', 'WinClosed' }, {
  group = group,
  callback = vim.schedule_wrap(update),
})

-- Back from the terminal or another app (git pull, rebase, commit): the diff shows the new state
vim.api.nvim_create_autocmd({ 'TermLeave', 'FocusGained' }, {
  group = group,
  callback = vim.schedule_wrap(function()
    local sd = package.loaded['pc.split_diff']
    if sd and sd.current() then
      sd.refresh()
    elseif diffview_open() then
      pcall(vim.cmd, 'DiffviewRefresh')
    end
  end),
})

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------

-- q: closes the diff (a recording macro still ends with q; buffer-local q maps come first)
vim.keymap.set('n', 'q', function()
  if vim.fn.reg_recording() == '' and M.active() then
    vim.schedule(M.close)
    return ''
  end
  return 'q'
end, { expr = true, desc = 'Close the diff' })

-- :q in a diff closes all of it
vim.cmd [[cnoreabbrev <expr> q (getcmdtype() ==# ':' && getcmdline() ==# 'q' && luaeval('require("pc.diff_ui").active()')) ? 'lua require("pc.diff_ui").close()' : 'q']]

return M
