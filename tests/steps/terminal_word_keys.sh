# The log (2026-11-24 09:38): fixing a word in a long prompt in the agent's terminal took
# Left ×81, Right ×86, Backspace ×62; Alt+Left / Right (word) worked in the editor only.
# In the terminal: Alt / Ctrl+Left / Right jump a word, Alt+Backspace deletes one; after a
# click in the terminal too.
ql 'vim.g.pc_agent_cmd = false' >/dev/null
k M-i; sleep 1.5
expect "terminal open" "$(q '&buftype')" terminal
lit 'exec zsh -f'; k Enter; sleep 1; lit "PS1='$ '; bindkey -e"; k Enter; sleep 0.5
out() { sleep 0.8; ql 'vim.fn.join(vim.api.nvim_buf_get_lines(0,0,-1,false),"\n")' | grep -v '^\$' | grep -v '^\s*$' | tail -1; }
lit 'echo aaa bbb ccc'; k M-Left; k M-Left; lit 'X'; k Enter
expect "Alt+Left x2: two words back" "$(out)" "aaa Xbbb ccc"
lit 'echo aaa bbb ccc'; k C-Left; lit 'Y'; k C-a; k M-Right; k M-Right; lit 'Z'; k Enter
expect "Ctrl+Left, Alt+Right (zsh: to the next word)" "$(out)" "aaa Zbbb Yccc"
lit 'echo one two'; k M-BSpace; lit 'three'; k Enter
expect "Alt+Backspace: word deleted" "$(out)" "one three"
# after a click into the output (Normal mode by the mouse): the keys still edit the prompt
lit 'echo aaa bbb'
ql 'vim.api.nvim_input("<LeftMouse><3,1>")' >/dev/null; sleep 0.5
expect "click: Normal mode" "$(q 'mode()')" "n"
k M-Left; lit 'Q'; k Enter
expect "after a click: Alt+Left still a word" "$(out)" "aaa Qbbb"
check terminal-word-keys
