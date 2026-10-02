#!/usr/bin/env bash
# Phase 2.1 exit criterion: a writer mutating the stores continuously is
# SIGKILLed at random points; after every kill the database must reopen
# without recovery, pass PRAGMA integrity_check, and hold exactly the
# content of a generation that was begun and not older than the last
# acknowledged commit. See Packages/Store/Sources/PersistenceHarness.
# Usage: scripts/persistence-kill-test.sh [kills=100] [debounce-ms=300] [seed]
set -euo pipefail

KILLS="${1:-100}"
DEBOUNCE="${2:-300}"
SEED="${3:-$RANDOM}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$(mktemp -d -t room-kill)"

swift build -c release --package-path "$ROOT/Packages/Store" --product room-persistence-harness >/dev/null
echo "load average: $(sysctl -n vm.loadavg)"
status=0
"$ROOT/Packages/Store/.build/release/room-persistence-harness" run \
  --kills "$KILLS" --debounce-ms "$DEBOUNCE" --seed "$SEED" --dir "$DIR" || status=$?
rm -rf "$DIR"
exit $status
