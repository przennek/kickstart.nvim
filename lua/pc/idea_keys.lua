-- The rest of your IntelliJ keymap (macOS keymap, Cmd -> Alt) that isn't part of a feature
-- module. Keys a terminal can't send (Ctrl+Tab, Ctrl+Shift+<letter>, Ctrl+Enter) are
-- translated by Alacritty into Ctrl+Shift+F1…F7, which arrive here as F37…F43.
-- The full IDEA ↔ Neovim comparison is in ~/Projects/test/KEYMAP.md.

local map = vim.keymap.set
local function tb(picker, opts)
  return function()
    require('telescope.builtin')[picker](opts)
  end
end

-- Switcher (Ctrl+Tab / Ctrl+Shift+Tab): recent files; keep pressing Ctrl+Tab to move down
map('n', '<F37>', tb('buffers', { sort_mru = true, ignore_current_buffer = true }), { desc = 'Switcher' })
map('n', '<F38>', tb('buffers', { sort_mru = true, ignore_current_buffer = true }), { desc = 'Switcher' })

-- Find (Cmd+F), Find Next / Previous (F3 / Shift+F3), Find Word at Caret (Cmd+F3)
map('n', '<M-f>', '/', { desc = 'Find' })
map('n', '<F3>', 'n', { desc = 'Find Next' })
map('n', '<S-F3>', 'N', { desc = 'Find Previous' })
map('n', '<F15>', 'N', { desc = 'Find Previous' })
map('n', '<M-F3>', '*', { desc = 'Find word at caret' })
map('n', '<F51>', '*', { desc = 'Find word at caret' })

-- Find in Path (Ctrl+Shift+F)
map('n', '<F39>', tb 'live_grep', { desc = 'Find in Path' })

-- Replace in Path (Ctrl+Shift+R): matches go to the Find window, then confirm to replace all
local function replace_in_path()
  local search = vim.fn.input('Replace in Path: ', vim.fn.expand '<cword>')
  if search == '' then
    return
  end
  local replacement = vim.fn.input('Replace "' .. search .. '" with: ')
  local out = vim.system({ 'rg', '--vimgrep', '--fixed-strings', '--', search }, { text = true, cwd = vim.fn.getcwd() }):wait()
  local lines = vim.split(out.stdout or '', '\n', { trimempty = true })
  if #lines == 0 then
    return vim.notify('No occurrences of ' .. search)
  end
  vim.fn.setqflist({}, ' ', { title = ('Replace %s → %s'):format(search, replacement), lines = lines, efm = '%f:%l:%c:%m' })
  require('trouble').open 'quickfix'
  -- ask once the Find window has opened (it takes the focus asynchronously)
  vim.defer_fn(function()
    vim.ui.select({ ('Replace all %d occurrences'):format(#lines), 'Cancel' }, { prompt = 'Replace in Path' }, function(choice)
      if choice and choice:match '^Replace' then
        -- gdefault is on, so no g flag: every match in a line is replaced
        vim.cmd(('silent cfdo %%s/\\V%s/%s/e | update'):format(vim.fn.escape(search, '/\\'), vim.fn.escape(replacement, '/\\&~')))
        local files = {}
        for _, line in ipairs(lines) do
          files[line:match '^[^:]+'] = true
        end
        vim.notify(('Replaced %d occurrences in %d files'):format(#lines, vim.tbl_count(files)))
      end
    end)
  end, 200)
end
map('n', '<F41>', replace_in_path, { desc = 'Replace in Path' })
map('n', '<leader>sR', replace_in_path, { desc = 'Replace in Path' })

-- Go to Type Declaration (Ctrl+Shift+B)
map('n', '<F42>', tb 'lsp_type_definitions', { desc = 'Go to Type Declaration' })

-- Generate (Ctrl+Enter); in the project tree it is New… (see neo-tree.lua)
map({ 'n', 'x' }, '<F40>', vim.lsp.buf.code_action, { desc = 'Generate' })

-- Jump to Source (F4) / Jump to Last Window (F12) / Restore Default Layout (Shift+F12)
map('n', '<F4>', tb 'lsp_definitions', { desc = 'Jump to Source' })
map({ 'n', 't' }, '<F12>', '<cmd>wincmd p<CR>', { desc = 'Jump to last window' })
local function restore_layout()
  require('pc.hide_windows').reset()
  vim.cmd 'wincmd ='
end
map('n', '<S-F12>', restore_layout, { desc = 'Restore default layout' })
map('n', '<F24>', restore_layout, { desc = 'Restore default layout' })

-- Next project window (Cmd+`), Git Branches (Cmd+Shift+`)
map('n', '<M-`>', function()
  if vim.env.TMUX then
    vim.system { 'tmux', 'switch-client', '-n' }
  end
end, { desc = 'Next project window' })
map('n', '<M-~>', function()
  -- the <leader>d Git branches popup (a lazy-loaded key, so it is typed rather than called)
  vim.api.nvim_feedkeys(vim.keycode '<leader>d', 'm', false)
end, { desc = 'Git Branches' })

-- Jump to Last Change (Cmd+Shift+Backspace)
map('n', '<M-BS>', 'g;', { desc = 'Jump to last change' })

-- Collapse / Expand (Cmd+- / Cmd+=): treesitter folds, all open by default
map('n', '<M-->', 'zc', { desc = 'Collapse' })
map('n', '<M-=>', 'zo', { desc = 'Expand' })
map('x', '<M-.>', 'zf', { desc = 'Collapse selection' })

-- IDE shortcuts work in the terminal too, as in IDEA's Terminal tool window: the key leaves
-- the terminal for the last editor window and runs there (a picked file opens in the editor,
-- not over the terminal). Shell word keys (Alt+B/F/D/.) stay with the shell.
local function last_editor_window()
  local prev = vim.fn.win_getid(vim.fn.winnr '#')
  local function editor(win)
    return win ~= 0 and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == '' and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ''
  end
  if editor(prev) then
    return prev
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if editor(win) then
      return win
    end
  end
end
local IDE_KEYS = {
  '<A-1>', '<M-2>', '<M-3>', '<M-4>', '<M-5>', '<M-6>', '<M-7>', '<M-8>', '<M-9>', '<M-0>',
  '<M-n>', '<M-N>', '<M-e>', '<M-E>', '<M-F12>', '<F60>', '<M-F2>', '<F50>', '<F37>', '<F39>', '<F41>',
}
for _, lhs in ipairs(IDE_KEYS) do
  map('t', lhs, function()
    vim.cmd 'stopinsert'
    vim.schedule(function()
      local win = last_editor_window()
      if win then
        vim.api.nvim_set_current_win(win)
      end
      vim.api.nvim_feedkeys(vim.keycode(lhs), 'm', false)
    end)
  end, { desc = 'IDE shortcut from the terminal' })
end

-- Cmd+Option shortcuts (macOS Alacritty sends them as Ctrl+Alt+F1…F7; on Linux Ctrl+Alt
-- belongs to the window manager). Each runs the existing <leader> mapping.
local cmd_option = {
  { '<C-M-F1>', '<leader>ev', 'Introduce Variable (Cmd+Option+V)', { 'n', 'x' } },
  { '<C-M-F2>', '<leader>ec', 'Introduce Constant (Cmd+Option+C)', { 'n', 'x' } },
  { '<C-M-F3>', '<leader>vr', 'Rollback (Cmd+Option+Z)', { 'n', 'x' } },
  { '<C-M-F4>', '<leader>vC', 'Commit and Push (Cmd+Option+K)' },
  { '<C-M-F5>', '<leader>i', 'Auto-Indent Lines (Cmd+Option+I)', { 'n', 'x' } },
  { '<C-M-F6>', '<leader>Qh', 'Database: query history (Cmd+Option+E)' },
  { '<C-M-F7>', '<leader>yr', 'Copy Reference (Cmd+Option+Shift+C)' },
}
for _, k in ipairs(cmd_option) do
  map(k[4] or 'n', k[1], k[2], { remap = true, desc = k[3] })
end

-- Tab after an auto-inserted closing bracket / quote jumps over it (BraceOrQuoteOut);
-- completion and snippets come first (autocomplete.lua)
return {
  brace_out = function()
    local col = vim.fn.col '.'
    local next_char = vim.api.nvim_get_current_line():sub(col, col)
    if next_char:match '[%)%]%}"\'`>]' then
      vim.api.nvim_win_set_cursor(0, { vim.fn.line '.', col })
      return true
    end
    return false
  end,
}
