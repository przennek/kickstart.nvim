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
    -- every Diffview, not the one in this tab only: opened twice, :q had to be typed twice
    local lib = require 'diffview.lib'
    for _ = 1, #lib.views + 1 do
      local view = lib.get_current_view() or lib.views[1]
      if not view then
        break
      end
      pcall(vim.api.nvim_set_current_tabpage, view.tabpage)
      vim.cmd 'DiffviewClose'
    end
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

-- Back from the terminal or another app (git pull, rebase, commit): the diff shows the new state.
-- Once, 0.5 s after the last of them: each wheel turn over a terminal leaves Terminal mode, and
-- 40 turns ran git 80 times in a row (Neovim hung for seconds)
local refresh_timer = vim.uv.new_timer()
vim.api.nvim_create_autocmd({ 'TermLeave', 'FocusGained' }, {
  group = group,
  callback = function()
    refresh_timer:stop()
    refresh_timer:start(
      500,
      0,
      vim.schedule_wrap(function()
        local sd = package.loaded['pc.split_diff']
        if sd and sd.current() then
          sd.refresh()
        elseif diffview_open() then
          pcall(vim.cmd, 'DiffviewRefresh')
        end
      end)
    )
  end,
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

-- :q / :q! in a diff closes all of it: pc.cmdline_enter

-- The file a diff window shows, on disk: diffview://<repo>/.git/<rev>/<path>, fugitive://… or the
-- file itself
local function source_file(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local repo, rel = name:match '^diffview://(.-)/%.git/[^/]+/(.+)$'
  if not repo then
    repo, rel = name:match '^fugitive://(.-)/%.git//%x+/(.+)$'
  end
  local file = repo and (repo .. '/' .. rel) or name
  return file ~= '' and not file:match '^%a+://' and vim.uv.fs_stat(file) and file or nil
end

-- Jump to Source (F4 in a diff, as in IDEA's diff viewer): the file you are reading, at this line,
-- in the editor; a Diffview stays open in its tab (Space vd / the Switcher go back to it), the
-- diff of one file (Show Diff) closes and leaves you in the file. The log: :q out of the diff,
-- then Search Everywhere for the same file, every time.
function M.jump_to_source()
  local file = source_file(0)
  if not file then
    return vim.notify('Jump to Source: no file on disk for this side', vim.log.levels.INFO)
  end
  local line = vim.fn.line '.'
  if not diffview_open() then
    M.close()
  else
    M.diff_tab = vim.api.nvim_get_current_tabpage()
    local target
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if tab ~= M.diff_tab and not target then
        target = tab
      end
    end
    if target then
      vim.api.nvim_set_current_tabpage(target)
    else
      vim.cmd 'tabnew'
    end
    -- an editor window of that tab (not the tree, a terminal…)
    for _, w in ipairs(normal_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == '' and not vim.wo[w].diff then
        vim.api.nvim_set_current_win(w)
        break
      end
    end
  end
  if vim.fs.normalize(vim.api.nvim_buf_get_name(0)) ~= vim.fs.normalize(file) then
    vim.cmd.edit(vim.fn.fnameescape(file))
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { math.min(line, vim.api.nvim_buf_line_count(0)), 0 })
  vim.cmd 'normal! zz'
end

--- Back to the open Diffview (the one F4 left), if any; true when there was one
function M.back_to_diff()
  if not package.loaded['diffview'] then
    return false
  end
  local lib = require 'diffview.lib'
  local view = (M.diff_tab and vim.api.nvim_tabpage_is_valid(M.diff_tab) and M.diff_tab) or (lib.views[1] and lib.views[1].tabpage)
  if view and vim.api.nvim_tabpage_is_valid(view) then
    vim.api.nvim_set_current_tabpage(view)
    return true
  end
  return false
end

-- A file opened in a Diffview's tab from outside the diff (the tree, Go to File, Search
-- Everywhere, the Switcher) goes to the editor; the Diffview keeps its file list and sides. It
-- took the list's (or a side's) place and the diff fell apart.
local function diffview_tab(tab)
  if not package.loaded['diffview'] then
    return false
  end
  for _, view in ipairs(require('diffview.lib').views) do
    if view.tabpage == tab then
      return true
    end
  end
  return false
end

-- a file that is not this window's side of the diff (Diffview puts its own files in its sides)
local function stray(win, buf, tab)
  for _, view in ipairs(require('diffview.lib').views) do
    if view.tabpage == tab then
      for _, w in ipairs(view.cur_layout and view.cur_layout.windows or {}) do
        if w.id == win then
          return not (w.file and w.file.bufnr == buf)
        end
      end
    end
  end
  return true
end

vim.api.nvim_create_autocmd('BufWinEnter', {
  group = vim.api.nvim_create_augroup('pc-diffview-files', { clear = true }),
  callback = function(event)
    local win, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    local name = vim.api.nvim_buf_get_name(event.buf)
    if vim.bo[event.buf].buftype ~= '' or name == '' or name:match '^%a+://' then
      return
    end
    if vim.api.nvim_win_get_config(win).relative ~= '' or not diffview_tab(tab) or not stray(win, event.buf, tab) then
      return
    end
    local cursor = vim.api.nvim_win_get_cursor(win)
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      -- the window gets back what it showed (the file list / a side)
      vim.api.nvim_win_call(win, function()
        if vim.fn.bufnr '#' > 0 then
          pcall(vim.cmd, 'buffer #')
        end
      end)
      M.diff_tab = tab
      local target
      for _, t in ipairs(vim.api.nvim_list_tabpages()) do
        if not target and not diffview_tab(t) then
          target = t
        end
      end
      if target then
        vim.api.nvim_set_current_tabpage(target)
      else
        vim.cmd 'tabnew'
      end
      for _, w in ipairs(normal_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == '' and not vim.wo[w].diff then
          vim.api.nvim_set_current_win(w)
          break
        end
      end
      vim.cmd.edit(vim.fn.fnameescape(name))
      pcall(vim.api.nvim_win_set_cursor, 0, cursor)
    end)
  end,
})

vim.api.nvim_create_autocmd('OptionSet', {
  group = vim.api.nvim_create_augroup('pc-diff-collapse', { clear = true }),
  pattern = 'diff',
  callback = function()
    if vim.v.option_new and vim.g.pc_diff_collapse ~= nil then
      vim.wo.foldenable = vim.g.pc_diff_collapse
    end
  end,
})

--- Diffs fold the unchanged lines (on) or show whole files (off); Settings → Editor too
function M.toggle_collapse()
  local on = vim.g.pc_diff_collapse == false
  require('pc.settings').set('diff_collapse', on)
  vim.notify('Diffs: unchanged lines ' .. (on and 'collapsed' or 'shown'))
end
vim.keymap.set('n', '<leader>vz', M.toggle_collapse, { desc = 'Diff: collapse unchanged lines (on / off)' })

return M
