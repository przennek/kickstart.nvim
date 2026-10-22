-- Line bookmarks like IDEA's (and the Code Remark plugin's notes): a sign in the gutter,
-- optional description shown at the end of the line, searchable list.
-- Keys follow .ideavimrc (<leader>pa / pr = ToggleBookmark, <leader>sb = ShowBookmarks)
-- and the IDEA keymap (F11 / Ctrl+F11 = toggle, Alt+F11 = with description, Shift+F11 = list).
-- Stored in the project like IDEA's (.idea/nvim/bookmarks.json, see pc.project_store), outside a
-- project in ~/.bookmarks; bookmarks made before move there with the next change.
local function bm(fn)
  return function()
    require('bookmarks')[fn]()
  end
end

-- Bookmark with description (Alt+F11 / <leader>pi): on a line that already has a bookmark the
-- key removes it, like pressing the bookmark key again in IDEA, instead of editing its text
local function bookmark_with_description()
  local ns = vim.api.nvim_get_namespaces()['bookmarks_extmark_signs_']
  local line = vim.fn.line '.' - 1
  local marked = ns and #vim.api.nvim_buf_get_extmarks(0, ns, { line, 0 }, { line, -1 }, {}) > 0
  require('bookmarks')[marked and 'bookmark_toggle' or 'bookmark_ann']()
end

local function show_bookmarks()
  require('telescope').extensions.bookmarks.list()
end

return {
  'tomasky/bookmarks.nvim',
  event = 'BufReadPost',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  keys = {
    { '<leader>pa', bm 'bookmark_toggle', desc = 'Bookmark: toggle' },
    { '<leader>pr', bm 'bookmark_toggle', desc = 'Bookmark: toggle' },
    { '<leader>pi', bookmark_with_description, desc = 'Bookmark: with description' },
    -- Edit Bookmark / Rename (the description of the bookmark on this line; adds one if there is none)
    { '<leader>pe', bm 'bookmark_ann', desc = 'Bookmark: [e]dit description' },
    { '<leader>pn', bm 'bookmark_next', desc = 'Bookmark: next in file' },
    { '<leader>pp', bm 'bookmark_prev', desc = 'Bookmark: previous in file' },
    { '<leader>pc', bm 'bookmark_clean', desc = 'Bookmark: clear file' },
    { '<leader>sb', show_bookmarks, desc = 'Show Bookmarks' },
    -- F11 / Ctrl+F11 / Shift+F11 (F35 / F23 inside tmux)
    { '<F11>', bm 'bookmark_toggle', desc = 'Bookmark: toggle' },
    -- Ctrl+F11 toggles too, as in your keymap
    { '<C-F11>', bm 'bookmark_toggle', desc = 'Bookmark: toggle' },
    { '<F35>', bm 'bookmark_toggle', desc = 'Bookmark: toggle' },
    { '<S-F11>', show_bookmarks, desc = 'Show Bookmarks' },
    { '<F23>', show_bookmarks, desc = 'Show Bookmarks' },
    -- macOS keymap on Alt: Cmd+F11 = bookmark with description (also what Code Remark did),
    -- Cmd+2 = Bookmarks tool window (F59 is Alt+F11 inside tmux)
    { '<M-F11>', bookmark_with_description, desc = 'Bookmark: with description' },
    { '<F59>', bookmark_with_description, desc = 'Bookmark: with description' },
    { '<M-2>', show_bookmarks, desc = 'Show Bookmarks' },
  },
  config = function()
    -- the plugin keeps a project's bookmarks in its scope file once that file exists
    local root = vim.fs.root(vim.fn.getcwd(), { '.git', 'pom.xml', 'build.gradle', 'pyproject.toml', 'package.json', 'Makefile' })
    local dir = root and require('pc.project_store').dir(root, true)
    if dir and not vim.uv.fs_stat(dir .. '/bookmarks.json') then
      vim.fn.writefile({}, dir .. '/bookmarks.json')
    end
    require('bookmarks').setup {
      virt_text = true, -- show descriptions at the end of the line
      scope_file = '.idea/nvim/bookmarks.json',
    }
    require('telescope').load_extension 'bookmarks'
  end,
}
