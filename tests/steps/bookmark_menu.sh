# The log (2026-11-24): Shift+F11, right click on a bookmark, Delete in the menu →
# "bookmarks_list.lua:195: attempt to index local 'picker' (a nil value)"; the menu's own picker
# had replaced the list. Delete from the menu removes that bookmark and shows the list again;
# Open goes to it.
R=$(q 'getcwd()'); printf 'l1\nl2\nl3\nl4\n' > $R/b.txt
ex 'e b.txt'; sleep 0.5
ex 'call cursor(2,1)'; k F11; sleep 0.5
ex 'call cursor(4,1)'; k F11; sleep 0.5
count() { ql "#vim.tbl_keys(require(\"bookmarks.config\").config.cache.data[vim.fn.fnamemodify(\"b.txt\", \":p\")] or {})"; }
expect "two bookmarks" "$(count)" "2"
k S-F11; sleep 1.5
expect "list open" "$(q '&filetype')" "TelescopePrompt"
ql 'vim.api.nvim_feedkeys(vim.keycode("<RightMouse>"), "m", false)'; sleep 1.5
expect "menu open" "$(ql 'vim.api.nvim_buf_get_lines(0,0,1,false)[1] ~= nil and vim.bo.filetype')" "TelescopePrompt"
lit 'Delete'; k Enter; sleep 1.5
expect "one bookmark left" "$(count)" "1"
expect "list shown again" "$(q '&filetype')" "TelescopePrompt"
check bookmark-menu-delete
k Escape; k Escape; sleep 0.5
k S-F11; sleep 1.5
ql 'vim.api.nvim_feedkeys(vim.keycode("<RightMouse>"), "m", false)'; sleep 1.5
lit 'Open'; k Enter; sleep 1.5
expect "open: in b.txt" "$(q 'expand("%:t")')" "b.txt"
expect "open: on the bookmark" "$(q 'line(".")')" "4"
check bookmark-menu-open
