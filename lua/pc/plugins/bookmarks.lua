-- Line bookmarks like IDEA's (and the Code Remark plugin's notes): a sign in the gutter,
-- optional description shown at the end of the line, searchable list.
-- Keys follow .ideavimrc (<leader>pa / pr = ToggleBookmark, <leader>sb = ShowBookmarks)
-- and the IDEA keymap (F11 / Ctrl+F11 = toggle, Alt+F11 = with description, Shift+F11 = list).
-- Stored globally in ~/.bookmarks, so they survive restarts.
local function bm(fn)
  return function()
    require('bookmarks')[fn]()
  end
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
    { '<leader>pi', bm 'bookmark_ann', desc = 'Bookmark: with description' },
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
    { '<M-F11>', bm 'bookmark_ann', desc = 'Bookmark: with description' },
    { '<F59>', bm 'bookmark_ann', desc = 'Bookmark: with description' },
    { '<M-2>', show_bookmarks, desc = 'Show Bookmarks' },
  },
  config = function()
    require('bookmarks').setup {
      virt_text = true, -- show descriptions at the end of the line
    }
    require('telescope').load_extension 'bookmarks'
  end,
}
