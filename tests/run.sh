#!/usr/bin/env bash
# Tests of this config on small Java / Python / C projects (tests/fixtures), in a fresh scratch
# directory. Run before committing:
#   tests/run.sh               regression: startup of each language (servers, keys, no errors),
#                              the plugin internals the config builds on, and the debugger
#                              stopping at a breakpoint in each
#   tests/run.sh scenario [N]  a work session in a real nvim inside a private tmux server
#                              (-L nvimtest): tests from the context, a debug session, an "LLM
#                              agent" editing files behind the editor, Recent Changes, Rename,
#                              tests again, then N (default 60) random tool-window / IDE actions
#   tests/run.sh all           both
# Exit status: the number of failures. KEEP=1 keeps the scratch directory for a look.
# Your nvim state (undo, Neogit, logs) and cache stay untouched: both point into the scratch
# directory; Local History entries of the scratch files are removed at the end.
# Needs: nvim with this config's plugins installed, tmux, git, java + mvn (jdtls), python3,
# cc + make; Python's debugger test needs pytest (a .venv is made with pip, skipped offline).
set -u
MODE=${1:-regression}
STEPS=${2:-60}
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=$HERE/lib
WORK=$(mktemp -d "${TMPDIR:-/tmp}/nvim-tests.XXXXXX")
export WORK LIB
source "$LIB/harness.sh"
: > "$LOG"
# nvim runs this config: lazy.nvim rewrites lazy-lock.json when it sees other plugins (e.g. a
# test with its own data directory); the tests must leave it as it was
LOCK=$(dirname "$HERE")/lazy-lock.json
cp "$LOCK" "$WORK/lazy-lock.before"

cleanup() {
  t kill-server 2>/dev/null
  # language servers (jdtls) can outlive nvim and write into the scratch directory: stop the
  # processes started for it (their command line has its unique path), then remove it
  pkill -f "$WORK/" 2>/dev/null
  sleep 2
  pkill -9 -f "$WORK/" 2>/dev/null
  # Local History kept versions of the scratch files: those entries go, nothing else
  local history=${XDG_DATA_HOME:-$HOME/.local/share}/nvim/local_history
  local prefix=$(printf '%s' "$WORK" | tr '/' '%')
  if [ -d "$history" ]; then
    find "$history" -maxdepth 1 -name "${prefix}*" -exec rm -r {} +
  fi
  if [ "${KEEP:-0}" = 1 ]; then echo "kept $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

# the projects, each a git repository
cp -r "$HERE/fixtures/." "$WORK/"
for p in java python c; do
  git -C "$WORK/$p" init -q && git -C "$WORK/$p" add -A && git -C "$WORK/$p" -c user.name=test -c user.email=test@example.com commit -qm init
done
printf '[{"directory":"%s","command":"cc -g -O0 -c src/%s","file":"src/%s"}' "$WORK/c" main.c main.c > "$WORK/c/compile_commands.json"
printf ',{"directory":"%s","command":"cc -g -O0 -c src/%s","file":"src/%s"}]\n' "$WORK/c" discount.c discount.c >> "$WORK/c/compile_commands.json"
make -s -C "$WORK/c" build/shop >/dev/null
PY_DEBUG=0
if python3 -m venv "$WORK/python/.venv" >/dev/null 2>&1 && "$WORK/python/.venv/bin/pip" install -q pytest >/dev/null 2>&1; then PY_DEBUG=1; fi

headless() {  # headless <dir> <file> <script> [env…]
  local dir=$1 file=$2 script=$3; shift 3
  (cd "$dir" && env XDG_CACHE_HOME="$WORK/cache" XDG_STATE_HOME="$WORK/state" "$@" timeout 180 nvim --headless -n -i NONE --cmd "source $LIB/fakeclip.vim" $file -c "luafile $LIB/$script" 2>&1 | grep -E '^(OK|FAIL|STOPPED|TIMEOUT)' | tail -1)
}

regression() {
  echo "== startup"
  for case in "java src/main/java/example/shop/OrderService.java jdtls 40000" "python shop/calculator.py basedpyright 12000" "c src/discount.c clangd 8000"; do
    set -- $case
    local out; out=$(headless "$WORK/$1" "$2" startup.lua SERVERS="$3" WAIT="$4")
    echo "$out"; [[ $out == OK* ]] || FAILS=$((FAILS + 1))
  done
  out=$(headless "$WORK/java" "" hooks.lua)
  echo "$out"; [[ $out == OK* ]] || FAILS=$((FAILS + 1))
  out=$(headless "$WORK/java" src/main/java/example/shop/OrderService.java editing.lua)
  echo "$out"; [[ $out == OK* ]] || FAILS=$((FAILS + 1))
  out=$(headless "$WORK" query.sql sql_statements.lua)
  echo "$out"; [[ $out == OK* ]] || FAILS=$((FAILS + 1))
  out=$(headless "$WORK/java" "" console_links.lua)
  echo "$out"; [[ $out == OK* ]] || FAILS=$((FAILS + 1))
  out=$(headless "$WORK/java" "" search.lua)
  echo "$out"; [[ $out == OK* ]] || FAILS=$((FAILS + 1))
  # on a copy: it renames and moves files of the repository
  cp -r "$WORK/java" "$WORK/java-git"
  out=$(headless "$WORK/java-git" "" git_track.lua)
  echo "$out"; [[ $out == OK* ]] || FAILS=$((FAILS + 1))
  cp -r "$WORK/java" "$WORK/java-store"
  out=$(headless "$WORK/java-store" "" project_store.lua)
  echo "$out"; [[ $out == OK* ]] || FAILS=$((FAILS + 1))
  python3 "$LIB/fake_pg.py" silent 55991 & local silent=$!
  python3 "$LIB/fake_pg.py" password 55992 & local password=$!
  sleep 0.5
  out=$(headless "$WORK" "" db_connect.lua SILENT_PORT=55991 PASSWORD_PORT=55992 FREE_PORT=55993 PGPASSFILE=/dev/null)
  kill $silent $password 2>/dev/null; wait $silent $password 2>/dev/null
  echo "$out"; [[ $out == OK* ]] || FAILS=$((FAILS + 1))
  # console switch needs a PostgreSQL server (PG_URL=postgresql://user@host:port/db) and a data
  # directory of its own: consoles are written there; the plugins are linked in
  if [ -n "${PG_URL:-}" ]; then
    mkdir -p "$WORK/data/nvim"
    for f in "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/*; do [ "$(basename "$f")" = dadbod ] || ln -sfn "$f" "$WORK/data/nvim/"; done
    out=$(headless "$WORK" "" db_switch.lua XDG_DATA_HOME="$WORK/data" PG_URL="$PG_URL")
    echo "$out"; [[ $out == OK* ]] || FAILS=$((FAILS + 1))
  else
    echo "skip console switch (no PG_URL)"
  fi
  echo "== debugger"
  local out
  out=$(headless "$WORK/java" src/test/java/example/shop/OrderServiceTest.java debug.lua WAIT=40000 BP_FILE=src/main/java/example/shop/OrderService.java BP_LINE=15 START="require('jdtls').test_class()")
  expect "java: breakpoint in a test run" "${out%% (*}" "STOPPED OrderService.java:15"
  if [ $PY_DEBUG = 1 ]; then
    out=$(headless "$WORK/python" "+9 tests/test_calculator.py" debug.lua WAIT=12000 BP_FILE=shop/calculator.py BP_LINE=20 START="require('dap-python').test_method()")
    expect "python: breakpoint in a pytest test" "${out%% (*}" "STOPPED calculator.py:20"
  else
    echo "skip python debugger (no pytest: pip offline?)"
  fi
  out=$(headless "$WORK/c" src/main.c debug.lua WAIT=8000 BP_FILE=src/discount.c BP_LINE=4 START="local d=require('dap') d.run(vim.tbl_extend('force', d.configurations.c[1], { program = '$WORK/c/build/shop', cwd = '$WORK/c' }))")
  expect "c: breakpoint in the program" "${out%% (*}" "STOPPED discount.c:4"
}

scenario() {
  echo "== scenario (log: $LOG)"
  local dir=$WORK/java
  start "$dir" src/test/java/example/shop/OrderServiceTest.java
  sleep 45
  check start
  # Terminal (Alt+T): Ctrl+K to the editor and Ctrl+J back, a few times; the shell gets none
  # of it (the plugin's own mappings typed "TmuxNavigateUp" into it), what you typed stays
  k M-t; sleep 2; lit 'echo nav'
  k C-k; sleep 0.5; expect "terminal: Ctrl+K goes to the editor" "$(q '&buftype')/$(q 'mode()')" "/n"
  k C-j; sleep 0.5; expect "editor: Ctrl+J back to the terminal, typing" "$(q '&buftype')/$(q 'mode()')" "terminal/t"
  k C-k; k C-j; k C-k; k C-j; lit ' ok'; k Enter; sleep 1; check terminal-navigation
  local term_text; term_text=$(ql 'table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")')
  expect "terminal: the command ran" "$(printf '%s' "$term_text" | grep -c '^nav ok$')" 1
  expect "terminal: nothing typed into the shell" "$(printf '%s' "$term_text" | grep -cE 'TmuxNavigate|command not found')" 0
  # a program in the foreground (fzf, less…) keeps Ctrl+K: here cat shows it as ^K
  lit 'cat'; k Enter; sleep 0.5; k C-k; sleep 0.5
  expect "terminal: Ctrl+K belongs to a running program" "$(q '&buftype')/$(q 'mode()')" "terminal/t"
  k C-d; k C-c; sleep 0.5; k C-k; sleep 0.5; esc "$HIDE_ALL"; check terminal-program
  # while typing, Alt+1 / Alt+T open their tool windows (they were Esc + 1 / Esc + t)
  editor; k G; k o; lit 'int typed = 1'; k M-1; sleep 1
  expect "typing: Alt+1 opens the project tree" "$(q '&ft')/$(q 'mode()')" "neo-tree/n"
  k M-1; editor; k A; k M-t; sleep 1.5
  expect "typing: Alt+T opens the terminal" "$(q '&ft')/$(q 'mode()')" "toggleterm/t"
  k M-t; editor; expect "typing: the text stays as typed" "$(q 'getline("$")')" "int typed = 1"
  k u; check typing-tool-windows
  # Alt+T from a popup: Search Everywhere and an input box close, the terminal opens
  editor; k ' ' ' '; sleep 1; lit Ord; sleep 0.5; k M-t; sleep 1.5
  expect "Search Everywhere: Alt+T opens the terminal" "$(q '&ft')/$(q 'mode()')" "toggleterm/t"
  k M-t; editor; ql 'require("pc.input").open({ prompt = "Name" }, function() end)' >/dev/null; sleep 0.5; lit abc; k M-t; sleep 1.5
  expect "input box: Alt+T opens the terminal" "$(q '&ft')/$(q 'mode()')" "toggleterm/t"
  k M-t; check popup-terminal
  # with a selection too (Visual: it was Esc + t, waiting for a character)
  editor; k V; k j; k M-1; sleep 1
  expect "selection: Alt+1 opens the project tree" "$(q '&ft')/$(q 'mode()')" "neo-tree/n"
  k M-1; check visual-tool-window
  # Search Everywhere finds a method (jdtls lists only classes unless told otherwise)
  k ' ' ' '; sleep 1; lit loyaltyDisc; sleep 3; k Enter; sleep 1.5; check search-everywhere
  expect "Search Everywhere: a method" "$(q "expand('%:t').':'.line('.')")" OrderService.java:10
  # tests from the context: one of the two fails
  editor; ex 'e src/test/java/example/shop/OrderServiceTest.java'
  ex 9; esc "$RUN_CTX"; sleep 20; check run-tests
  expect "tests window: 1 of 2 passed" "$(screen | grep -c 'OrderServiceTest  1/2 passed')" 1
  # debug the failing test with a breakpoint in the service
  editor; ex 'e src/main/java/example/shop/OrderService.java'; ex 15; esc "$AF8"
  editor; ex 'e src/test/java/example/shop/OrderServiceTest.java'; ex 19; esc "$DEBUG_CTX"; sleep 15; check debug
  expect "debugger stops in the service" "$(ql "(function() local s=require(\"dap\").session() return s and s.current_frame and (s.current_frame.source.name..\":\"..s.current_frame.line) or \"none\" end)()")" "OrderService.java:15"
  # Variables (Alt+5): Copy Value of an object is its text, Set Value takes an object expression
  k M-5; sleep 1
  ql "(function() for _,w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do local b=vim.api.nvim_win_get_buf(w) if vim.bo[b].filetype==\"dapui_scopes\" then vim.api.nvim_set_current_win(w) for i,l in ipairs(vim.api.nvim_buf_get_lines(b,0,-1,false)) do if l:find(\"newTotal\") then vim.api.nvim_win_set_cursor(w,{i,0}) return i end end end end end)()" >/dev/null
  k M-c; sleep 1; check copy-value
  expect "Copy Value: the object's text" "$(q 'g:test_clip[0][0]')" 50
  k F2; sleep 1.5; lit 'new java.math.BigDecimal("100")'; k Enter; sleep 2; check set-value
  expect "Set Value: an object" "$(ql "(function() local s=require(\"dap\").session() local out s:request(\"evaluate\",{expression=\"String.valueOf(newTotal)\",frameId=s.current_frame.id,context=\"repl\"},function(e,r) out=r and r.result end) vim.wait(3000,function() return out ~= nil end) return out end)()")" '"100"'
  # Step Into twice from there (BigDecimal calls on the line): the JDK is skipped, as in IDEA
  k F7; sleep 2; k F7; sleep 2; check step-into
  expect "Step Into stays in project code" "$(ql "(function() local s=require(\"dap\").session() local f=s and s.current_frame return f and ((f.source and f.source.path or \"\"):match(\"^jdt:\") and \"jdk\" or \"project\") or \"none\" end)()")" project
  editor; k ' xe'; sleep 0.8; k Enter; sleep 1.5; check evaluate; k Escape
  esc "$CF2"; sleep 2
  # an agent edits the open file, adds a class and a test behind the editor's back
  editor; ex 'e src/main/java/example/shop/OrderService.java'; sleep 1
  python3 "$LIB/agent_edit.py" "$dir"; sleep 3; check agent
  expect "open file reloaded with the agent's change" "$( [ "$(q "search('>= 0','nw')")" -gt 0 ] && echo yes || echo no)" yes
  editor; k ' vE'; sleep 1.5
  expect "Recent Changes lists the agent's change" "$( screen | grep -q 'OrderService.java' && echo yes || echo no)" yes
  k Escape; k Escape
  # rename the agent's method in the box at the cursor: the (unopened) test is changed and saved
  editor; q "execute('call search(\"long unpaid\") | normal! w')" >/dev/null; sleep 8
  esc "$SF6"; sleep 1.5; lit countUnpaid; k Enter; sleep 5; check rename
  expect "rename saved in the service" "$(grep -c 'countUnpaid' "$dir/src/main/java/example/shop/OrderService.java")" 1
  expect "rename saved in the test" "$(grep -c 'countUnpaid' "$dir/src/test/java/example/shop/OrderServiceTest.java")" 1
  # rename the record: its file is renamed, every use changes, the new file is in git (a commit
  # would otherwise take the deletion of Order.java only)
  editor; ex 'e src/main/java/example/shop/Order.java'; q "execute('call search(\"record Order\") | normal! w')" >/dev/null; sleep 2
  esc "$SF6"; sleep 1.5; k C-u; lit PurchaseOrder; k Enter; sleep 6; check rename-class
  expect "rename class: file renamed" "$(ls "$dir/src/main/java/example/shop" | grep -c '^Order.java$\|^PurchaseOrder.java$')-$(q "expand('%:t')")" "1-PurchaseOrder.java"
  expect "rename class: uses changed and saved" "$(grep -rl 'PurchaseOrder' "$dir/src" | wc -l)" 4
  expect "rename class: new file added to git" "$(git -C "$dir" status --short -- src/main/java/example/shop/PurchaseOrder.java | cut -c1-2)" " A"
  # move it to a new package in the tree (m): jdtls' Move - package line, imports of its users
  editor; ex 'e src/main/java/example/shop/PurchaseOrder.java'; sleep 1; k M-1; sleep 1.5
  k m; sleep 1; k C-u; lit model/PurchaseOrder.java; k Enter; sleep 12; check tree-move
  expect "tree move: package line" "$(head -1 "$dir/src/main/java/example/shop/model/PurchaseOrder.java" 2>/dev/null)" "package example.shop.model;"
  expect "tree move: imports in its users" "$(grep -rl 'import example.shop.model.PurchaseOrder;' "$dir/src" | wc -l)" 3
  k Escape; editor
  # Replace in Path: exactly the (case-sensitive) matches it lists, in every file
  editor; ex 'e src/main/java/example/shop/OrderService.java'; q "execute('call search(\"\\\"PAID\") | normal! l')" >/dev/null
  k ' sR'; sleep 1; k Enter; sleep 0.8; lit SETTLED; k Enter; sleep 2; k Enter; sleep 2; check replace
  expect "Replace in Path: 3 files" "$(grep -rl '"SETTLED"' "$dir/src" | wc -l)" 3
  expect "Replace in Path: lower-case 'paid' in a comment left alone" "$(grep -c 'in paid orders' "$dir/src/main/java/example/shop/OrderService.java")" 1
  # review: Find in Path only in the sources (mask without tests), the file against its last
  # commit, the .gitignore through Go to File
  editor; k ' sg'; sleep 1; lit SETTLED; sleep 1.5; k M-m; sleep 0.8; lit '*.java, !*Test.java'; k Enter; sleep 2; check find-mask
  expect "Find in Path with a mask: no test file listed" "$(screen | grep -c 'Test.java:')" 0
  expect "Find in Path with a mask: the sources listed" "$( screen | grep -q 'OrderService.java:' && echo yes || echo no)" yes
  k M-m; sleep 0.8; k C-u; k Enter; sleep 1; k Escape; k Escape
  editor; ex 'e src/main/java/example/shop/OrderService.java'; k ' vo'; sleep 2; k Enter; sleep 3; check compare-revision
  expect "Compare with Revision: last commit against the working tree" "$(ql "(function() local v=require(\"diffview.lib\").get_current_view() return v and (tostring(v.left):sub(1,7)..\" \"..tostring(v.right)) or \"none\" end)()")" "$(git -C "$dir" rev-parse --short=7 HEAD) LOCAL"
  k q; sleep 1.5
  editor; k ' sf'; sleep 1; lit gitign; sleep 1.5; k Enter; sleep 1; check goto-dotfile
  expect "Go to File: .gitignore" "$(q "expand('%:t')")" .gitignore
  # Find in Path → the Find window (Ctrl+T): Enter on the file line opens its first match
  editor; k ' sg'; sleep 1; lit SETTLED; sleep 2; k C-t; sleep 2; k Enter; sleep 1; check find-window
  expect "Find window: Enter opens the match" "$(q "getline('.')" | grep -c SETTLED)" 1
  k M-3; sleep 0.5; editor
  # tests again: the agent fixed the threshold, all pass
  editor; ex 'e src/test/java/example/shop/OrderServiceTest.java'; ex 9; esc "$RUN_CTX"; sleep 20; check rerun
  expect "tests window: 3 of 3 passed" "$(screen | grep -c 'OrderServiceTest  3/3 passed')" 1
  # Extract Constant from the literal under the cursor, named in the rename box
  editor; ex 'e src/main/java/example/shop/OrderService.java'
  q "execute('call search(\"\\\"100\\\"\") | normal! l')" >/dev/null
  k ' ec'; sleep 3; lit THRESHOLD; k Enter; sleep 4; check extract-constant
  expect "Extract Constant: named and used" "$(grep -c 'THRESHOLD' "$dir/src/main/java/example/shop/OrderService.java")" 2
  # the terminal types at once; restored by Hide All it leaves the editor in Normal mode
  editor; k M-t; sleep 1.5
  expect "Alt+T: the terminal takes typing" "$(q 'mode()')" t
  k M-t; sleep 0.5; editor; k M-t; sleep 1; k C-k; sleep 0.3; editor
  esc "$HIDE_ALL"; sleep 0.8; esc "$HIDE_ALL"; sleep 1
  expect "Hide All twice: the editor stays in Normal mode" "$(q 'mode()')" n
  # commit from the Commit window with nothing staged: every tracked change goes (IDEA: all
  # changes checked), the agent's new files stay unversioned
  editor; k M-0; sleep 3; k c; sleep 1; k c; sleep 3
  lit 'Review fixes'; k Escape; sleep 0.3; ex wq; sleep 4; check commit
  expect "commit: last message" "$(git -C "$dir" log -1 --format=%s)" "Review fixes"
  expect "commit: no tracked change left" "$(git -C "$dir" status --porcelain --untracked-files=no | wc -l)" 0
  expect "commit: the agent's new files stay unversioned" "$( [ -n "$(git -C "$dir" status --porcelain | grep '^??')" ] && echo yes || echo no)" yes
  k M-0; sleep 1; editor
  hammer "$STEPS"
  stop
  # Python: renaming a module in the tree changes its imports (the server's willRenameFiles)
  start "$WORK/python" shop/calculator.py
  sleep 10; check python-start
  editor; k M-1; sleep 1.5; k r; sleep 1; k C-u; lit pricing.py; k Enter; sleep 4; check python-tree-rename
  expect "Python: module renamed in the tree, its import follows" "$(head -1 "$WORK/python/tests/test_calculator.py")" "from shop.pricing import Line, PriceCalculator"
  stop
}

case $MODE in
  regression) regression ;;
  scenario) scenario ;;
  all) regression; scenario ;;
  *) echo "usage: tests/run.sh [regression|scenario [steps]|all]"; exit 2 ;;
esac
if ! cmp -s "$LOCK" "$WORK/lazy-lock.before"; then
  cp "$WORK/lazy-lock.before" "$LOCK"
  fail "the tests changed lazy-lock.json (restored)"
fi
echo "== $FAILS failure(s)"
exit $FAILS
