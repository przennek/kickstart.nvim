cwd=$(q 'getcwd()')
for n in b c d; do seq 1 80 | sed "s/^/$n /" > $cwd/$n.txt; done
git -C $cwd add -A; git -C $cwd -c user.name=t -c user.email=t@t commit -qm x
for n in b c d; do sed -i 's/^\(. 30\)$/\1 changed/;s/^\(. 60\)$/\1 changed/' $cwd/$n.txt; done
echo more >> $cwd/a.txt
cur() { ql 'require("diffview.lib").get_current_view().cur_entry.path'; }
curline() { ql 'vim.api.nvim_win_get_cursor(require("diffview.lib").get_current_view().cur_layout:get_main_win().id)[1]'; }
inmain() { ql 'vim.api.nvim_get_current_win()==require("diffview.lib").get_current_view().cur_layout:get_main_win().id and 1 or 0'; }
openit() { editor; k ' vd'; sleep 3; }
openit
expect "first open starts at first file" "$(cur)" "a.txt"
# go to 3rd file via panel: next file
ql 'require("diffview.lib").get_current_view():set_file_by_path("c.txt", true)' >/dev/null; sleep 2
expect "c selected" "$(cur)" "c.txt"
lit '45G'; sleep 0.5
expect "line 45" "$(curline)" "45"
k q; sleep 2
expect "closed" "$(ql 'require("diffview.lib").get_current_view() and 1 or 0')" "0"
openit
expect "q: same file" "$(cur)" "c.txt"
expect "q: same line" "$(curline)" "45"
ql 'vim.api.nvim_set_current_win(require("diffview.lib").get_current_view().cur_layout:get_main_win().id)' >/dev/null
lit '20G'; sleep 0.5
lit ':q'; k Enter; sleep 2
openit
expect "q-cmd: same file" "$(cur)" "c.txt"
expect "q-cmd: line 20" "$(curline)" "20"
# switch file in panel without touching main, close
ql 'require("diffview.lib").get_current_view():set_file_by_path("d.txt", false)' >/dev/null; sleep 2
lit ':DiffviewClose'; k Enter; sleep 2
openit
expect "panel-picked file" "$(cur)" "d.txt"
# main cursor on 33, then remembered file no longer differs
ql 'vim.api.nvim_set_current_win(require("diffview.lib").get_current_view().cur_layout:get_main_win().id)' >/dev/null
lit '33G'; sleep 0.5
k q; sleep 2
git -C $cwd checkout d.txt
openit
expect "gone file: first file" "$(cur)" "a.txt"
k q; sleep 2
openit
expect "gone file: no stale" "$(cur)" "a.txt"
k q; sleep 1
check final
