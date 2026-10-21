#!/usr/bin/env bash
# 5.2a: token drift. Lists literal point sizes, colours and radii in the
# chrome's sources outside the Design package: Packages/*/Sources (Design
# excluded) and App/Sources (the DEBUG spikes in App/Sources/Debug excluded:
# they draw contact sheets and test pages, not the product).
#
# A finding is a line where a number literal (not 0) gives
#   size    a font or symbol size: `ofSize: 13`, `pointSize: 12`, `.system(size: 11`, `size: 13, weight:`
#   colour  a colour: `NSColor(white:|red:|srgbRed:|calibratedRed:|calibratedWhite:|deviceRed:|displayP3Red:|hue:`,
#           `CGColor(red:|gray:|srgbRed:`, SwiftUI `Color(red:|white:`, `.withAlphaComponent(0.4)`, `.opacity(0.4)`,
#           a `#RRGGBB` hex string
#   radius  a corner: `cornerRadius = 6`, `cornerRadius: 6`, `xRadius: 6`, `.cornerRadius(6)`
# A literal that stays on purpose carries `// design-audit: <reason>` on its
# line; it is listed as declared (docs/design-tokens.md "Deliberate literals"
# has the list). The count that matters is the undeclared one.
#
# Usage: scripts/design-audit.sh [--list] [--strict]
#   --list    every finding (file:line: category: text), declared ones marked
#   --strict  exit 1 when an undeclared finding remains
set -euo pipefail
cd "$(dirname "$0")/.."
LIST=0; STRICT=0
for arg in "$@"; do
  case "$arg" in
    --list) LIST=1 ;;
    --strict) STRICT=1 ;;
    *) echo "usage: $0 [--list] [--strict]" >&2; exit 2 ;;
  esac
done

num='([1-9][0-9]*(\.[0-9]+)?|0\.[0-9]*[1-9][0-9]*)'
size_re="(ofSize: *$num|pointSize: *$num|\.system\(size: *$num|[^a-zA-Z]size: *$num, *weight:)"
colour_re="(NSColor\((white|red|srgbRed|calibratedRed|calibratedWhite|deviceRed|deviceWhite|displayP3Red|hue|genericGamma22White): *$num|CGColor\((red|gray|srgbRed): *$num|[^a-zA-Z]Color\((red|white): *$num|withAlphaComponent\( *$num|\.opacity\( *$num|\"#[0-9A-Fa-f]{6}\")"
radius_re="(cornerRadius *= *$num|cornerRadius: *$num|[xy]Radius: *$num|\.cornerRadius\( *$num)"

files=$(find Packages/*/Sources App/Sources -name '*.swift' -not -path 'Packages/Design/*' -not -path 'App/Sources/Debug/*' | sort)

total=0; declared=0
report=""
for category in size colour radius; do
  case $category in
    size) re="$size_re" ;;
    colour) re="$colour_re" ;;
    radius) re="$radius_re" ;;
  esac
  # shellcheck disable=SC2086
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    text="${line#*:*:}"
    # Comment lines are prose, not code.
    [[ "$(echo "$text" | sed 's/^[[:space:]]*//')" == //* ]] && continue
    total=$((total + 1))
    mark=""
    if [[ "$text" == *"design-audit:"* ]]; then declared=$((declared + 1)); mark=" [declared]"; fi
    report+="${line%%:*}:$(echo "$line" | cut -d: -f2): $category$mark: $(echo "$text" | sed 's/^[[:space:]]*//' | cut -c1-140)"$'\n'
  done < <(grep -nE "$re" $files /dev/null 2>/dev/null || true)
done

undeclared=$((total - declared))
if [[ $LIST -eq 1 ]]; then printf '%s' "$report"; fi
by_category=$(printf '%s' "$report" | { grep -v '\[declared\]' || true; } | awk -F': ' '{print $2}' | sort | uniq -c | awk '{printf "%s %s, ", $2, $1}' | sed 's/, $//')
echo "design-audit: $total literal(s), $declared declared deliberate, $undeclared undeclared${by_category:+ ($by_category)}"
if [[ $STRICT -eq 1 && $undeclared -gt 0 ]]; then exit 1; fi
exit 0
