#!/usr/bin/env bash
# Downloads the pinned CEF binary distribution into Engine/cef/dist/, verifies it
# against the pinned SHA-1 and the Spotify CDN index, builds libcef_dll_wrapper
# with CMake, and (once, or with --validate) builds and runs cefsimple to prove
# the local Xcode toolchain can build and launch a CEF app.
#
# Outputs (consumed by project.yml and Packages/EngineCEF):
#   Engine/cef/dist/current                 -> the extracted minimal distribution
#   Engine/cef/dist/build/libcef_dll_wrapper/libcef_dll_wrapper.a
#
# Usage: scripts/bootstrap-cef.sh [--validate] [--force]
set -euo pipefail

CEF_VERSION="154.0.32+g682c378+chromium-154.0.8037.58"
CEF_PLATFORM="macosarm64"
CEF_API_VERSION="15400"   # stable API of CEF 154 (include/cef_api_versions.h)
# SHA-1s from https://cef-builds.spotifycdn.com/index.json, recorded 2026-10-01.
SHA1_MINIMAL="2e9df1077c097e450d30f26804b7c4b1820da4e3"
# The minimal distribution ships no tests/; cefsimple comes from the standard one.
SHA1_STANDARD="8147f08ca0a65b21227962c7273fcb3ef7174cae"

CDN="https://cef-builds.spotifycdn.com"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/Engine/cef/dist"
DOWNLOADS="$DIST/downloads"
BUILD="$DIST/build"
NAME_MINIMAL="cef_binary_${CEF_VERSION}_${CEF_PLATFORM}_minimal"
NAME_STANDARD="cef_binary_${CEF_VERSION}_${CEF_PLATFORM}"
SRC="$DIST/$NAME_MINIMAL"

validate=0
force=0
for arg in "$@"; do
  case "$arg" in
    --validate) validate=1 ;;
    --force) force=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

log() { echo "== $(date '+%T') $*"; }
elapsed() { echo $(( $(date +%s) - $1 )); }

for tool in curl shasum jq cmake xcrun; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

urlencode_plus() { echo "${1//+/%2B}"; }

# fetch <tarball-name> <pinned-sha1>
fetch() {
  local file="$1.tar.bz2" want="$2" path="$DOWNLOADS/$1.tar.bz2"
  local indexed
  indexed=$(jq -r --arg v "$CEF_VERSION" --arg f "$file" \
    ".${CEF_PLATFORM}.versions[] | select(.cef_version == \$v) | .files[] | select(.name == \$f) | .sha1" \
    "$DOWNLOADS/index.json")
  if [[ "$indexed" != "$want" ]]; then
    echo "SHA-1 mismatch between pin ($want) and CDN index (${indexed:-missing}) for $file" >&2
    exit 1
  fi
  if [[ ! -f "$path" ]] || [[ "$(shasum -a 1 "$path" | cut -d' ' -f1)" != "$want" ]]; then
    local t0; t0=$(date +%s)
    log "downloading $file"
    curl -fsSL -o "$path.part" "$CDN/$(urlencode_plus "$file")"
    mv "$path.part" "$path"
    log "downloaded in $(elapsed "$t0")s"
  fi
  local got; got=$(shasum -a 1 "$path" | cut -d' ' -f1)
  [[ "$got" == "$want" ]] || { echo "SHA-1 mismatch for $file: $got" >&2; exit 1; }
}

mkdir -p "$DOWNLOADS"
log "fetching CDN index"
curl -fsSL -o "$DOWNLOADS/index.json" "$CDN/index.json"

fetch "$NAME_MINIMAL" "$SHA1_MINIMAL"
if [[ $force -eq 1 || ! -d "$SRC" ]]; then
  rm -rf "$SRC" "$BUILD"
  t0=$(date +%s)
  tar -xjf "$DOWNLOADS/$NAME_MINIMAL.tar.bz2" -C "$DIST"
  log "extracted minimal distribution in $(elapsed "$t0")s"
fi
ln -sfn "$NAME_MINIMAL" "$DIST/current"

if [[ $validate -eq 1 || ! -f "$BUILD/.cefsimple-validated" ]] && [[ ! -d "$SRC/tests" ]]; then
  fetch "$NAME_STANDARD" "$SHA1_STANDARD"
  t0=$(date +%s)
  tar -xjf "$DOWNLOADS/$NAME_STANDARD.tar.bz2" -C "$SRC" --strip-components 1 "$NAME_STANDARD/tests"
  log "extracted tests/ from the standard distribution in $(elapsed "$t0")s"
fi

t0=$(date +%s)
cmake -S "$SRC" -B "$BUILD" -G "Unix Makefiles" \
  -DPROJECT_ARCH=arm64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_CXX_FLAGS="-fobjc-arc" \
  -Dapi_version="$CEF_API_VERSION" >"$BUILD.configure.log" 2>&1 \
  || { cat "$BUILD.configure.log"; exit 1; }
log "configured in $(elapsed "$t0")s"

jobs=$(sysctl -n hw.ncpu)
t0=$(date +%s)
cmake --build "$BUILD" --target libcef_dll_wrapper -j "$jobs"
log "libcef_dll_wrapper built in $(elapsed "$t0")s"

if [[ $validate -eq 1 || ! -f "$BUILD/.cefsimple-validated" ]]; then
  t0=$(date +%s)
  cmake --build "$BUILD" --target cefsimple -j "$jobs"
  log "cefsimple built in $(elapsed "$t0")s"

  app="$BUILD/tests/cefsimple/Release/cefsimple.app"
  log "launching cefsimple for 8s"
  "$app/Contents/MacOS/cefsimple" --url="data:text/html,<h1>cefsimple</h1>" >"$BUILD/cefsimple.log" 2>&1 &
  pid=$!
  sleep 8
  if ! kill -0 "$pid" 2>/dev/null; then
    cat "$BUILD/cefsimple.log"
    echo "cefsimple exited early" >&2
    exit 1
  fi
  helpers=$(pgrep -f "cefsimple Helper" | wc -l | tr -d ' ')
  log "cefsimple running with $helpers helper processes; quitting"
  osascript -e 'tell application id "org.cef.cefsimple" to quit' >/dev/null 2>&1 || kill -TERM "$pid"
  t0=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    if (( $(date +%s) - t0 > 10 )); then echo "cefsimple did not quit within 10s" >&2; kill -9 "$pid"; exit 1; fi
    sleep 0.2
  done
  wait "$pid" && status=0 || status=$?
  log "cefsimple quit in $(elapsed "$t0")s with status $status"
  [[ $status -eq 0 ]] || { cat "$BUILD/cefsimple.log"; exit 1; }
  touch "$BUILD/.cefsimple-validated"
fi

log "CEF $CEF_VERSION ready at $DIST/current"
