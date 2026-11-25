# The user (2026-11-25): "przewijanie jest zepsute jak agent pisze": scrolled up in the agent's
# terminal to read, every new line of output threw the view back (toggleterm's auto_scroll
# ran G on each chunk). Scrolled up, the view stays while the program writes; the wheel down
# to the end follows the output again.
ql 'vim.g.pc_agent_cmd = false' >/dev/null
k M-i; sleep 1.5
expect "agent terminal open" "$(q '&buftype')" terminal
lit 'for i in $(seq 1 400); do echo line$i; sleep 0.02; done'; k Enter; sleep 3
for _ in 1 2 3 4 5 6; do ql 'vim.api.nvim_input("<ScrollWheelUp><5,5>")' >/dev/null; sleep 0.1; done
sleep 0.3
top1=$(q 'line("w0")'); sleep 2; top2=$(q 'line("w0")')
expect "scrolled up: view stays while output comes" "$top2" "$top1"
expect "scrolled up: not at the end" "$( [ "$(q 'line("w$")')" -lt "$(q 'line("$")')" ] && echo yes || echo no)" yes
for _ in $(seq 1 60); do [ "$(ql 'vim.fn.search("^line400$", "nw")')" -gt 0 ] && break; sleep 0.5; done
expect "first output finished" "$( [ "$(ql 'vim.fn.search("^line400$", "nw")')" -gt 0 ] && echo yes || echo no)" yes
n=0; while [ "$(q 'mode()')" != t ] && [ $n -lt 120 ]; do ql 'vim.api.nvim_input("<ScrollWheelDown><5,5>")' >/dev/null; sleep 0.05; n=$((n+1)); done
expect "wheel down to the end: typing again" "$(q 'mode()')" t
lit 'for i in $(seq 1 50); do echo more$i; sleep 0.02; done'; k Enter
for _ in $(seq 1 30); do [ "$(ql 'vim.fn.search("^more50$", "nw")')" -gt 0 ] && break; sleep 0.5; done; sleep 0.5
last=$(ql 'vim.fn.search("^more50$", "nw")')
expect "at the end again: follows the output" "$( [ "$last" -gt 0 ] && [ "$last" -le "$(q 'line("w$")')" ] && [ "$last" -ge "$(q 'line("w0")')" ] && echo yes || echo "no: more50 at $last, view $(q 'line("w0")')-$(q 'line("w$")')")" yes
check terminal-scroll-output
