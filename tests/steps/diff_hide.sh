# Hide the diff and bring it back with one key (the user, 2026-11-25): review a diff, put it
# away, work on a class, jump around, and Alt+Shift+F12 (Hide All Windows) / Space vd brings the
# diff back as it was; the files open outside and inside the diff are kept.
R=$(q 'getcwd()')
for n in b c d; do seq 1 80 | sed "s/^/$n /" > $R/$n.txt; done
seq 1 50 | sed 's/^/e /' > $R/e.txt; seq 1 50 | sed 's/^/f /' > $R/f.txt
git -C $R add -A; git -C $R -c user.name=t -c user.email=t@t commit -qm x
for n in b c d; do sed -i 's/^\(. 30\)$/\1 changed/;s/^\(. 60\)$/\1 changed/' $R/$n.txt; done
hide() { esc "$HIDE_ALL"; sleep 1.2; }
tabs() { q "tabpagenr('\$')"; }
dv() { ql 'require("diffview.lib").get_current_view() and 1 or 0'; }
cur() { ql 'require("diffview.lib").get_current_view().cur_entry.path'; }
mainwin() { ql 'require("diffview.lib").get_current_view().cur_layout:get_main_win().id'; }
here() { q 'expand("%:t").":".line(".")'; }
nwin() { ql '#vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative=="" end, vim.api.nvim_tabpage_list_wins(0))'; }
# the editor: e.txt | f.txt (line 10)
ex 'e e.txt'; ex 'vs f.txt'; ex '10'; sleep 0.3
# the diff: c.txt, line 45 of the right side
k ' vd'; sleep 3
expect "diff open" "$(dv)" 1
ql 'require("diffview.lib").get_current_view():set_file_by_path("c.txt", true)' >/dev/null; sleep 2
ql "vim.api.nvim_set_current_win($(mainwin))" >/dev/null; lit '45G'; sleep 0.5
DTAB=$(q 'tabpagenr()'); MAIN=$(mainwin)
# (1) hide: back in f.txt at line 10, e.txt beside it
hide
expect "1: hidden: editor tab" "$(dv)" 0
expect "1: in the window you came from" "$(here)" "f.txt:10"
expect "1: e.txt | f.txt kept" "$(nwin)" 2
expect "1: diff tab kept" "$(tabs)" 2
# (2) work in the editor: another file, an edit, a new split, jumps
ex 'e d.txt'; ex '5'; lit 'Aedit'; k Escape; ex 'w'
ex 'sp b.txt'; ex '33'; lit 'gg'; ex '33'
check 2-work
# (3) back to the diff: c.txt, line 45, in its right side
hide
expect "3: diff back" "$(dv)" 1
expect "3: same file" "$(cur)" "c.txt"
expect "3: in the right side" "$(q 'win_getid()')" "$MAIN"
expect "3: same line" "$(q 'line(".")')" "45"
# (4) and back to the editor: b.txt at 33, three windows
hide
expect "4: back in b.txt:33" "$(here)" "b.txt:33"
expect "4: three windows" "$(nwin)" 3
# (5) Space vd does the same, many times; nothing piles up
for i in 1 2 3 4 5; do
  k ' vd'; sleep 1.2
  expect "5.$i: diff c.txt:45" "$(cur):$(q 'line(".")')" "c.txt:45"
  k ' vd'; sleep 1.2
  expect "5.$i: editor b.txt:33" "$(here)" "b.txt:33"
done
expect "5: still two tabs" "$(tabs)" 2
expect "5: still three windows" "$(nwin)" 3
check 5-cycles
# (6) moving in the diff is kept: another file, another line
hide
ql 'require("diffview.lib").get_current_view():set_file_by_path("b.txt", true)' >/dev/null; sleep 2
ql "vim.api.nvim_set_current_win($(mainwin))" >/dev/null; lit '60G'; sleep 0.5
hide; hide
expect "6: diff on b.txt:60" "$(cur):$(q 'line(".")')" "b.txt:60"
# (7) F4 (Jump to Source) to the file, then the key: back to the diff
k F4; sleep 1.2
expect "7: F4: the file" "$(here)" "b.txt:60"
expect "7: F4: editor tab" "$(dv)" 0
hide
expect "7: key after F4: diff back" "$(cur):$(q 'line(".")')" "b.txt:60"
# (8) with the project tree open in the editor: visible tool windows hide first, as before
hide; k M-1; sleep 1.5
hide
expect "8: tree hidden first" "$(ql '#vim.tbl_filter(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype=="neo-tree" end, vim.api.nvim_tabpage_list_wins(0))')" 0
expect "8: still in the editor" "$(dv)" 0
k ' vd'; sleep 1.2
expect "8: Space vd: diff back" "$(dv)" 1
# (9) the diff closed (q): the key is Hide All again, nothing breaks
k q; sleep 2
expect "9: diff closed" "$(tabs)-$(dv)" "1-0"
hide; hide
check 9-after-close
# (10) split diff (Alt+D, this file against HEAD): hidden and back on its line
editor; ex 'e c.txt'; k M-d; sleep 1.5
expect "10: split diff" "$(q '&diff')" 1
# (Esc closes a split diff by design: the line without the Esc of `ex`)
lit ':60'; k Enter; hide
expect "10: hidden: no diff windows" "$(ql '#vim.tbl_filter(function(w) return vim.wo[w].diff end, vim.api.nvim_tabpage_list_wins(0))')" 0
expect "10: the file left" "$(q 'expand("%:t")')" "c.txt"
ex 'e e.txt'; ex '7'
hide
expect "10: split diff back" "$(q '&diff')" 1
expect "10: on c.txt:60" "$(here)" "c.txt:60"
hide
expect "10: hidden again: e.txt" "$(q 'expand("%:t")')" "e.txt"
check 10-split-diff
