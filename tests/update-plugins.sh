#!/usr/bin/env bash
# Plugin update that cannot leave a broken config behind:
#   tests/update-plugins.sh            update all plugins, run tests/run.sh all; on a failure the
#                                      versions from before are restored (:Lazy restore)
#   tests/update-plugins.sh <plugin>…  only these (names as in lazy-lock.json)
# On success lazy-lock.json holds the new versions: look at the summary and commit it. Close your
# other nvim windows first: the plugin files change under them.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
CONFIG=$(dirname "$HERE")
LOCK=$CONFIG/lazy-lock.json
BACKUP=$(mktemp "${TMPDIR:-/tmp}/lazy-lock.XXXXXX.json")
cp "$LOCK" "$BACKUP"

restore() {
  echo "== restoring the plugin versions from before"
  cp "$BACKUP" "$LOCK"
  nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1
  echo "restored ($(git -C "$CONFIG" diff --quiet -- lazy-lock.json && echo 'lazy-lock.json unchanged' || echo 'check lazy-lock.json'))"
}

echo "== updating ${*:-all plugins}"
# UPDATE_CMD replaces the update itself (for testing this script)
if [ -n "${UPDATE_CMD:-}" ]; then
  eval "$UPDATE_CMD"
else
  nvim --headless "+Lazy! update $*" +qa >/dev/null 2>&1
fi

changed=$(python3 - "$BACKUP" "$LOCK" <<'EOF'
import json, sys
old, new = (json.load(open(p)) for p in sys.argv[1:3])
for name in sorted(set(old) | set(new)):
    a, b = old.get(name, {}).get('commit'), new.get(name, {}).get('commit')
    if a != b:
        print(f"  {name}: {(a or 'new')[:8]} -> {(b or 'removed')[:8]}")
EOF
)
if [ -z "$changed" ]; then
  echo "nothing to update"
  rm -f "$BACKUP"
  exit 0
fi
echo "$changed"

echo "== testing the new versions"
# TEST_CMD replaces the tests (for testing this script)
if eval "${TEST_CMD:-\"$HERE/run.sh\" all ${STEPS:-40}}"; then
  echo "== all tests pass: commit the new versions with"
  echo "   git -C $CONFIG commit -m 'Update plugins' lazy-lock.json"
  rm -f "$BACKUP"
  exit 0
fi
restore
rm -f "$BACKUP"
exit 1
