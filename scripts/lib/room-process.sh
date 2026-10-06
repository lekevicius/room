# Sourced by the spike wrappers: talk to one Room process by its pid, never
# by bundle id (B-47). Room.app on RoomCore, the engine-free CI build and the RoomCore
# embryo host all share app.room.desktop; an AppleEvent addressed by bundle
# id goes to whichever LaunchServices picks and, when none is running,
# launches one, which then opens the real state directory. scripts/lib/room-ae.swift
# sends the event to the pid itself: when that process has gone the send
# fails (procNotFound) and nothing launches.

_room_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOM_AE="$_room_repo/build/tools/room-ae"
if [[ ! -x "$ROOM_AE" || "$_room_repo/scripts/lib/room-ae.swift" -nt "$ROOM_AE" ]]; then
  mkdir -p "$(dirname "$ROOM_AE")"
  swiftc -O -o "$ROOM_AE" "$_room_repo/scripts/lib/room-ae.swift" >&2
fi
unset _room_repo

# room_scope <app>: the pgrep patterns for that app's own processes (its main
# executable, ROOM_MAIN_PATTERN, and its helpers, ROOM_HELPER_PATTERN), so a
# Room run from elsewhere (the laptop's week build in /Applications, 2026-10-06)
# is neither waited for, counted, nor stopped by a wrapper. The path may be
# relative: it is matched as a substring of the command line.
room_scope() {
  ROOM_MAIN_PATTERN="${1#./}/Contents/MacOS/Room"
  ROOM_HELPER_PATTERN="${1#./}/Contents/.*Room Helper"
}
room_scope "${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"

# room_activate <pid>: bring that process frontmost (the AppleEvent `activate`,
# as `osascript … activate` did; macOS refuses a script-launched app's own
# activation while the user works elsewhere).
room_activate() {
  "$ROOM_AE" activate "$1" 2>/dev/null || true
}

# room_quit <pid>: the quit AppleEvent (the ⌘Q path) to that process only.
# Returns non-zero when the event could not be delivered.
room_quit() {
  "$ROOM_AE" quit "$1"
}

# room_helpers_left [timeout-seconds]: prints the Room Helper processes still
# running, waiting up to the timeout (default 5 s) for Chrome's
# code-sign-clone-cleanup helper only (B-45: it deletes the app's code-sign
# clone after the browser exits and lives 1–1.8 s past every quit on
# RoomCore). Other helpers are counted at once. Output: "<left> <clone>"
# where <left> excludes a cleanup helper that exited within the timeout and
# <clone> is the seconds the cleanup helper took (0 when there was none, or
# "timeout").
room_helpers_left() {
  local timeout="${1:-5}" t0 clone=0 others cleanup
  t0=$(perl -MTime::HiRes=time -e 'printf "%.2f", time')
  others=$( (pgrep -f "$ROOM_HELPER_PATTERN" | while read -r p; do
              ps -o command= -p "$p" 2>/dev/null | grep -q -- '--type=code-sign-clone-cleanup' || echo "$p"; done) | wc -l | tr -d ' ')
  cleanup=$( (pgrep -f -- "$ROOM_HELPER_PATTERN.*--type=code-sign-clone-cleanup" || true) | wc -l | tr -d ' ')
  if [[ $cleanup -gt 0 ]]; then
    while pgrep -f -- "$ROOM_HELPER_PATTERN.*--type=code-sign-clone-cleanup" >/dev/null; do
      if perl -e "exit !($(perl -MTime::HiRes=time -e 'printf "%.2f", time') - $t0 > $timeout)"; then
        clone=timeout; break
      fi
      sleep 0.1
    done
    [[ $clone == timeout ]] || clone=$(perl -MTime::HiRes=time -e "printf '%.1f', time - $t0")
  fi
  if [[ $clone == timeout ]]; then
    echo "$((others + cleanup)) timeout"
  else
    echo "$others $clone"
  fi
}
