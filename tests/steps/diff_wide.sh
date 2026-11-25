# The log (2026-11-13 15:22): in a Diffview Ctrl+Shift+M maximized one side and was undone at
# once, then the separators were dragged by hand. In a Diffview it now gives the diff the whole
# width: the file list goes, the sides are equal; again: the list is back. The cursor stays.
R=$(q 'getcwd()')
for n in b c; do seq 1 80 | sed "s/^/$n /" > $R/$n.txt; done
git -C $R add -A; git -C $R -c user.name=t -c user.email=t@t commit -qm x
for n in b c; do sed -i 's/^\(. 30\)$/\1 changed/' $R/$n.txt; done
panel() { ql '#vim.tbl_filter(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype=="DiffviewFiles" end, vim.api.nvim_tabpage_list_wins(0))'; }
sides() { ql 'table.concat(vim.tbl_map(function(w) return vim.api.nvim_win_get_width(w) end, vim.tbl_filter(function(w) return vim.wo[w].diff end, vim.api.nvim_tabpage_list_wins(0))), " ")'; }
k ' vd'; sleep 3
ql 'vim.api.nvim_set_current_win(require("diffview.lib").get_current_view().cur_layout:get_main_win().id)' >/dev/null
lit '30G'; sleep 0.3
W=$(q 'win_getid()')
expect "list shown" "$(panel)" 1
for round in 1 2; do
  k M-M; sleep 0.8
  expect "$round: list gone" "$(panel)" 0
  set -- $(sides)
  expect "$round: two equal sides over the width" "$(( $1 + $2 + 1 >= 199 && ( $1 - $2 <= 1 && $2 - $1 <= 1 ) ))" 1
  expect "$round: still in the right side, line 30" "$(q 'win_getid()'):$(q 'line(".")')" "$W:30"
  k M-M; sleep 0.8
  expect "$round: list back" "$(panel)" 1
  expect "$round: cursor kept" "$(q 'win_getid()'):$(q 'line(".")')" "$W:30"
done
# outside a diff Ctrl+Shift+M still maximizes a split
k q; sleep 1.5; ex 'vs'; k M-M; sleep 0.5
expect "plain split maximized" "$(( $(q 'winwidth(0)') > 150 ))" 1
k M-M; sleep 0.5
check diff-wide
