#!/usr/bin/env bash
# Xcode build phase (Room target): copies the CEF framework from
# Engine/cef/dist/current/Release into Contents/Frameworks with the versioned
# Versions/A layout Xcode 26+ expects, then signs its dylibs and the framework
# with the target's signing identity (ad-hoc when signing is "Sign to Run Locally").
set -euo pipefail

NAME="Chromium Embedded Framework"
SRC="$SRCROOT/Engine/cef/dist/current/Release/$NAME.framework"
DEST="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/$NAME.framework"

if [[ ! -d "$SRC" ]]; then
  echo "error: $SRC not found; run scripts/bootstrap-cef.sh" >&2
  exit 1
fi

identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[[ -n "$identity" ]] || identity="-"
# Skip the copy and re-sign when nothing changed since the last build.
stamp="$DERIVED_FILE_DIR/cef-framework.stamp"
want="$(readlink "$SRCROOT/Engine/cef/dist/current") $identity ${CODE_SIGNING_ALLOWED:-YES} ${ENABLE_HARDENED_RUNTIME:-NO}"
if [[ -f "$stamp" && "$(cat "$stamp")" == "$want" && -f "$DEST/Versions/A/$NAME" ]]; then
  exit 0
fi

mkdir -p "$DEST/Versions/A"
# rsync keeps incremental builds cheap (the framework is ~320 MB).
rsync -a --delete "$SRC/" "$DEST/Versions/A/"
ln -sfn A "$DEST/Versions/Current"
for link in "$NAME" Libraries Resources; do
  ln -sfn "Versions/Current/$link" "$DEST/$link"
done

if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
  flags=(--force --sign "$identity")
  if [[ "${ENABLE_HARDENED_RUNTIME:-NO}" == "YES" ]]; then
    flags+=(--options runtime --timestamp)
  fi
  # Inside-out: dylibs first, then the framework bundle.
  find "$DEST/Versions/A/Libraries" -name '*.dylib' -print0 \
    | xargs -0 -n1 codesign "${flags[@]}"
  codesign "${flags[@]}" "$DEST/Versions/A"
fi

mkdir -p "$DERIVED_FILE_DIR"
echo "$want" > "$stamp"
