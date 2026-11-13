cwd=$(q 'getcwd()')
mkdir -p $cwd/src $cwd/docs
for f in docs/notes_beta.md src/alpha_one.txt src/beta_two.txt docs/notes_alpha.md docs/zeta.txt src/gamma.txt; do echo "x $f" > $cwd/$f; done
cp -r ~/.config/nvim/tests/fixtures/python/. "$cwd/"
SEL='(function() local e = require("telescope.actions.state").get_selected_entry() return e and (e.filename or e.value or e[1]) or "none" end)()'
PROMPT='require("telescope.actions.state").get_current_line()'
LIST='(function() local p=require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf()) local t={} for i=1,p.manager:num_results() do t[#t+1]=p.manager:get_entry(i).value end return table.concat(t,",") end)()'
CUR='vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")'
# (1) pick X then Y
editor; k M-N; sleep 1.5; lit 'beta'; sleep 0.8; k Enter; sleep 0.6
expect "X opened" "$(ql "$CUR")" "src/beta_two.txt"
editor; k M-N; sleep 1.5; lit 'zeta'; sleep 0.8; k Enter; sleep 0.6
expect "Y opened" "$(ql "$CUR")" "docs/zeta.txt"
editor; k M-N; sleep 1.5
expect "prompt empty" "$(ql "$PROMPT")" ""
expect "first = Y" "$(ql "$SEL")" "docs/zeta.txt"
l=$(ql "$LIST")
expect "list order" "$(echo $l | cut -d, -f1-2)" "docs/zeta.txt,src/beta_two.txt"
expect "no duplicates" "$(echo $l | tr ',' '\n' | sort | uniq -d | wc -l)" "0"
expect "all files listed" "$(echo $l | tr ',' '\n' | wc -l)" "$(cd $cwd && rg --files --hidden --glob '!.git' | wc -l)"
k Up; expect "next = X" "$(ql "$SEL")" "src/beta_two.txt"
k Down; k Enter; sleep 0.6
expect "Enter opens Y" "$(ql "$CUR")" "docs/zeta.txt"
# (2) typed query matching recent and non-recent: 'alpha' -> docs/notes_alpha.md, src/alpha_one.txt (neither recent); use 'txt' ... recent X=beta_two.txt
editor; k M-N; sleep 1.5; lit 'txt'; sleep 1
expect "typed: recent first" "$(ql "$SEL")" "docs/zeta.txt"
k Escape; sleep 0.5
editor; k M-N; sleep 1.5; lit 'beta'; sleep 1
expect "typed beta: recent before non-recent" "$(ql "$SEL")" "src/beta_two.txt"
k Escape; sleep 0.5
# leader keys too
editor; lit ' n'; sleep 1.5
screen > $WORK/leader.scr; expect "leader n first = Y" "$(ql "$SEL")" "docs/zeta.txt"
k Escape; sleep 0.5
# (4) config search
editor; lit ' sN'; sleep 2
expect "config search lists config files" "$(ql "$LIST" | grep -c 'init.lua')" "1"
k Escape; sleep 0.5
editor; k M-N; sleep 1.5
expect "config search did not pollute" "$(ql "$LIST" | cut -d, -f1-2)" "docs/zeta.txt,src/beta_two.txt"
k Escape; sleep 0.5
check files
# (5) classes
ex "e shop/calculator.py"; sleep 12
k M-n; sleep 2; lit 'Line'; sleep 2
expect "class typed Line selected" "$(ql "$SEL" | grep -c 'calculator.py')" "1"
k Enter; sleep 1
expect "jumped to Line" "$(ql "$CUR"):$(ql 'vim.fn.line(".")')" "shop/calculator.py:5"
ex "e src/gamma.txt"; sleep 1
k M-n; sleep 2.5
expect "class prompt empty" "$(ql "$PROMPT")" ""
expect "class pre-selected = Line" "$(ql 'require("telescope.actions.state").get_selected_entry().symbol_name')" "Line"
k M-n; sleep 2
expect "toggle title all places" "$(ql 'vim.api.nvim_buf_get_name(0)' >/dev/null; screen | grep -c 'all places)')" "1"
k M-n; sleep 2
k Escape; sleep 0.5
editor; ex "e src/gamma.txt"; sleep 1
k M-n; sleep 2.5; lit 'Pri'; sleep 1.5
k M-n; sleep 2.5
expect "toggle keeps text" "$(ql "$PROMPT")" "Pri"
k Escape; sleep 0.5
editor
k M-n; sleep 2.5; k Enter; sleep 1
expect "Enter right away -> Line" "$(ql "$CUR"):$(ql 'vim.fn.line(".")')" "shop/calculator.py:5"
# second class picked: PriceCalculator, then order
k M-n; sleep 2; lit 'PriceCalc'; sleep 2; k Enter; sleep 1
expect "jumped PriceCalculator" "$(ql 'vim.fn.line(".")')" "14"
ex "e src/gamma.txt"; sleep 1
k M-n; sleep 2.5
expect "last class first" "$(ql 'require("telescope.actions.state").get_selected_entry().symbol_name')" "PriceCalculator"
k Up; expect "then Line" "$(ql 'require("telescope.actions.state").get_selected_entry().symbol_name')" "Line"
k Escape; sleep 0.5
check classes
echo "JSONPATH $WORK/state/nvim/pc-recent-picks.json"
