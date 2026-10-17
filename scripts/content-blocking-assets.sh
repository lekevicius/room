#!/usr/bin/env bash
# Refreshes what Room's built-in blocker ships (App/Resources/ContentBlocking,
# B-30; research/notes/adblock-approach.md §9.3): the permissively licensed
# default lists, a minimal resources file for $redirect rules, and Room's
# build of DuckDuckGo's autoconsent. A developer's command, run before a
# release (the lists then carry that day's versions); the app itself never
# downloads anything unless the user turns on list updates.
#
#   EasyList, EasyPrivacy        CC BY-SA 3.0 (dual GPLv3; taken as CC BY-SA)
#   EasyList Cookie List         CC BY 3.0
#   autoconsent (npm)            MPL-2.0
#
# Usage: scripts/content-blocking-assets.sh [autoconsent-version]
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/App/Resources/ContentBlocking"
AUTOCONSENT_VERSION="${1:-16.55.0}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$OUT"

fetch() {  # url file
  curl -fsSL --retry 3 -o "$work/$2" "$1"
  head -c 2000 "$work/$2" | grep -q '^\[Adblock Plus' || { echo "$1 is not a filter list" >&2; exit 1; }
  mv "$work/$2" "$OUT/$2"
  echo "$2: $(grep -m1 '^! Version:\|^! Last modified:' "$OUT/$2" | sed 's/^! //') $(wc -c < "$OUT/$2" | tr -d ' ') bytes"
}
fetch https://easylist.to/easylist/easylist.txt easylist.txt
fetch https://easylist.to/easylist/easyprivacy.txt easyprivacy.txt
fetch https://secure.fanboy.co.nz/fanboy-cookiemonster.txt easylist-cookie.txt

# $redirect bodies under uBO's and ABP's names (empty script, frame, text,
# image): Room's own minimal set, no third-party code.
python3 - "$OUT/redirect-resources.json" <<'EOF'
import base64, json, sys
def res(name, aliases, mime, body):
    return {"name": name, "aliases": aliases, "kind": {"mime": mime},
            "content": base64.b64encode(body).decode()}
gif = base64.b64decode("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")
png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAC0lEQVR4nGNgQAcAABIAAboYB0QAAAAASUVORK5CYII=")
resources = [
    res("noop.js", ["noopjs", "abp-resource:blank-js", "blank-js"], "application/javascript", b"(function(){})();"),
    res("noop.txt", ["nooptext", "noop", "abp-resource:blank-text"], "text/plain", b""),
    res("noop.css", ["noopcss", "abp-resource:blank-css"], "text/css", b""),
    res("noop.html", ["noopframe", "abp-resource:blank-html"], "text/html", b"<!DOCTYPE html><html><head></head><body></body></html>"),
    res("1x1.gif", ["1x1-transparent.gif", "abp-resource:1x1-transparent-gif"], "image/gif", gif),
    res("2x2.png", ["2x2-transparent.png", "abp-resource:2x2-transparent-png"], "image/png", png),
    res("noop.json", ["noopjson"], "application/json", b"{}"),
]
json.dump(resources, open(sys.argv[1], "w"), indent=1)
EOF

# autoconsent: the npm package (sources, rules) and Room's entry, bundled as
# one IIFE for the isolated world.
curl -fsSL --retry 3 -o "$work/autoconsent.tgz" \
  "https://registry.npmjs.org/@duckduckgo/autoconsent/-/autoconsent-$AUTOCONSENT_VERSION.tgz"
tar -xzf "$work/autoconsent.tgz" -C "$work"
mkdir -p "$work/package/room"
cp "$REPO/scripts/content-blocking/autoconsent-room.ts" "$work/package/room/entry.ts"
(cd "$work/package" && npm install --no-audit --no-fund --ignore-scripts >/dev/null 2>&1 \
  && npx --yes esbuild@0.25.10 room/entry.ts --bundle --format=iife --minify \
       --target=chrome120 --legal-comments=eof --outfile="$OUT/autoconsent-room.js" --log-level=warning)
cp "$work/package/LICENSE" "$OUT/LICENSE-autoconsent"
echo "autoconsent-room.js: autoconsent $AUTOCONSENT_VERSION, $(wc -c < "$OUT/autoconsent-room.js" | tr -d ' ') bytes"
printf '%s\n' "$AUTOCONSENT_VERSION" > "$OUT/autoconsent-version.txt"
