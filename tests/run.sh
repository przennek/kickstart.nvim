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
  (cd "$dir" && env XDG_CACHE_HOME="$WORK/cache" "$@" timeout 180 nvim --headless -n -i NONE --cmd "source $LIB/fakeclip.vim" $file -c "luafile $LIB/$script" 2>&1 | grep -E '^(OK|FAIL|STOPPED|TIMEOUT)' | tail -1)
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
  # tests from the context: one of the two fails
  ex 9; esc "$RUN_CTX"; sleep 20; check run-tests
  expect "tests window: 1 of 2 passed" "$(screen | grep -c 'OrderServiceTest  1/2 passed')" 1
  # debug the failing test with a breakpoint in the service
  editor; ex 'e src/main/java/example/shop/OrderService.java'; ex 15; esc "$AF8"
  editor; ex 'e src/test/java/example/shop/OrderServiceTest.java'; ex 19; esc "$DEBUG_CTX"; sleep 15; check debug
  expect "debugger stops in the service" "$(ql "(function() local s=require(\"dap\").session() return s and s.current_frame and (s.current_frame.source.name..\":\"..s.current_frame.line) or \"none\" end)()")" "OrderService.java:15"
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
  # tests again: the agent fixed the threshold, all pass
  editor; ex 'e src/test/java/example/shop/OrderServiceTest.java'; ex 9; esc "$RUN_CTX"; sleep 20; check rerun
  expect "tests window: 3 of 3 passed" "$(screen | grep -c 'OrderServiceTest  3/3 passed')" 1
  # the terminal types at once; restored by Hide All it leaves the editor in Normal mode
  editor; k M-t; sleep 1.5
  expect "Alt+T: the terminal takes typing" "$(q 'mode()')" t
  k M-t; sleep 0.5; editor; k M-t; sleep 1; k C-k; sleep 0.3; editor
  esc "$HIDE_ALL"; sleep 0.8; esc "$HIDE_ALL"; sleep 1
  expect "Hide All twice: the editor stays in Normal mode" "$(q 'mode()')" n
  hammer "$STEPS"
  stop
}

case $MODE in
  regression) regression ;;
  scenario) scenario ;;
  all) regression; scenario ;;
  *) echo "usage: tests/run.sh [regression|scenario [steps]|all]"; exit 2 ;;
esac
echo "== $FAILS failure(s)"
exit $FAILS
