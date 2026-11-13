#!/usr/bin/env bash
# Feature tests in a real nvim, one small scratch git repository each (tests/run.sh's scenario is
# one long session in the Java fixture; these start clean and run alone):
#   tests/steps.sh                 every file in tests/steps/
#   tests/steps.sh diffview_place  only tests/steps/diffview_place.sh
# A steps file is bash run inside a function, with the helpers of tests/lib/harness.sh (k, lit,
# ex, q, ql, expect, check, editor, screen); `q 'getcwd()'` is the scratch repository.
# nvim runs in a private tmux server (-L nvimsteps) with state and cache of its own.
# Exit status: the number of failures.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=$HERE/lib
TOTAL=0
names=("$@")
[ ${#names[@]} -eq 0 ] && for f in "$HERE"/steps/*.sh; do names+=("$(basename "$f" .sh)"); done

for name in "${names[@]}"; do
  echo "== $name"
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/nvim-steps.XXXXXX")
  export WORK LIB
  source "$LIB/harness.sh"
  : > "$LOG"
  FAILS=0
  t() { tmux -L nvimsteps "$@"; }
  LOCK=$(dirname "$HERE")/lazy-lock.json
  cp "$LOCK" "$WORK/lazy-lock.before"
  mkdir -p "$WORK/p" && (cd "$WORK/p" && echo hello > a.txt && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init)
  start "$WORK/p" a.txt
  sleep 4
  run() { source "$HERE/steps/$name.sh"; }
  run
  stop
  cmp -s "$LOCK" "$WORK/lazy-lock.before" || { fail "lazy-lock.json changed"; cp "$WORK/lazy-lock.before" "$LOCK"; }
  pkill -f "$WORK/" 2>/dev/null
  [ "${KEEP:-}" = 1 ] && echo "kept: $WORK" || rm -rf "$WORK"
  TOTAL=$((TOTAL + FAILS))
done
echo "== $TOTAL failure(s)"
exit $TOTAL
