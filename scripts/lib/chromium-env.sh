# Sourced by the Chromium/RoomCore scripts: where the Chromium checkout and
# depot_tools live on this machine.
#
# Precedence: environment > the repo's local.env (gitignored, per machine;
# see local.env.example) > defaults.
#   CHROMIUM_ROOT   gclient root, holds src/        (default ~/chromium)
#   CHROMIUM_SRC    the checkout                    (default $CHROMIUM_ROOT/src)
#   DEPOT_TOOLS                                     (default ~/depot_tools)
#   CHROMIUM_IMAGE  optional disk image holding CHROMIUM_ROOT's volume; attached
#                   here when that volume is not mounted (an APFS sparse bundle
#                   on an external drive that is not APFS itself)

_room_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_room_env_root="${CHROMIUM_ROOT:-}" _room_env_src="${CHROMIUM_SRC:-}"
_room_env_tools="${DEPOT_TOOLS:-}" _room_env_image="${CHROMIUM_IMAGE:-}"
if [[ -f "$_room_repo/local.env" ]]; then
  # shellcheck source=/dev/null
  source "$_room_repo/local.env"
fi
CHROMIUM_ROOT="${_room_env_root:-${CHROMIUM_ROOT:-$HOME/chromium}}"
CHROMIUM_SRC="${_room_env_src:-${CHROMIUM_SRC:-$CHROMIUM_ROOT/src}}"
DEPOT_TOOLS="${_room_env_tools:-${DEPOT_TOOLS:-$HOME/depot_tools}}"
CHROMIUM_IMAGE="${_room_env_image:-${CHROMIUM_IMAGE:-}}"
export CHROMIUM_ROOT CHROMIUM_SRC DEPOT_TOOLS CHROMIUM_IMAGE
export PATH="$DEPOT_TOOLS:$PATH"
unset _room_env_root _room_env_src _room_env_tools _room_env_image

# Mount the volume CHROMIUM_ROOT lives on, if it is a /Volumes path that is
# missing and an image is configured.
if [[ "$CHROMIUM_ROOT" == /Volumes/* ]]; then
  _room_volume="/Volumes/$(echo "$CHROMIUM_ROOT" | cut -d/ -f3)"
  if [[ ! -d "$_room_volume" ]]; then
    if [[ -n "$CHROMIUM_IMAGE" && -e "$CHROMIUM_IMAGE" ]]; then
      echo "attaching $CHROMIUM_IMAGE" >&2
      hdiutil attach "$CHROMIUM_IMAGE" -nobrowse -owners on >/dev/null
    fi
    [[ -d "$_room_volume" ]] || { echo "$_room_volume is not mounted (CHROMIUM_ROOT=$CHROMIUM_ROOT)" >&2; exit 1; }
  fi
  unset _room_volume
fi
unset _room_repo
