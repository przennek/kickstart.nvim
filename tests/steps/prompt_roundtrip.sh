# Alt+Shift+I (in.txt), Alt+I (agent), Alt+Shift+I (back in in.txt), Alt+Shift+I: back to the file
# the round started from, every time and from either side
R=$(q 'getcwd()'); echo src > $R/src.txt
ql 'vim.g.pc_agent_cmd = false' >/dev/null
where() { q 'expand("%:t")."/".mode()."/".&buftype."/".winnr("$")'; }
ex 'edit src.txt'; sleep 0.5
for round in 1 2; do
  k M-I; sleep 0.6
  expect "$round: Alt+Shift+I opens in.txt" "$(where)" in.txt/n//1
  k M-i; sleep 1.5
  expect "$round: Alt+I the agent" "$(q '&buftype')" terminal
  k M-I; sleep 1
  expect "$round: Alt+Shift+I from the agent: in.txt" "$(where)" in.txt/n//1
  k M-I; sleep 0.6
  expect "$round: Alt+Shift+I again: the file" "$(where)" src.txt/n//1
  check "round $round"
done
# from the file straight to the agent and back to in.txt, then to the file
k M-i; sleep 1.5; k M-I; sleep 1
expect "file -> agent -> Alt+Shift+I: in.txt" "$(where)" in.txt/n//1
k M-I; sleep 0.6
expect "-> Alt+Shift+I: the file" "$(where)" src.txt/n//1
# typing in in.txt, to the agent and back: typing goes on there
k M-I; sleep 0.6; k i; lit 'note'; k M-i; sleep 1.5; k M-I; sleep 1
expect "typing, agent, back: in.txt" "$(q 'expand("%:t")')" in.txt
k M-I; sleep 0.6
expect "then the file" "$(where)" src.txt/n//1
check done
