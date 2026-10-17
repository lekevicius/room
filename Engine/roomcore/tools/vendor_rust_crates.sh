#!/bin/bash
# Vendors Room's Rust crates (room/third_party/rust/Cargo.lock) into
# room/third_party/rust/vendor/ (gitignored; checksums from the lock file) and
# regenerates each crate's BUILD.gn. Runs offline when the crates are already
# in ~/.cargo/registry; otherwise it downloads them from crates.io (a build
# machine's request, never the browser's).
#
# Usage: Engine/roomcore/tools/vendor_rust_crates.sh [--check]
#   --check  exit 1 if vendor/ is missing or does not match Cargo.lock
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rust_dir="$here/../room/third_party/rust"
stamp="$rust_dir/vendor/.cargo-lock-stamp"

if [[ "${1:-}" == "--check" ]]; then
  [[ -f "$stamp" ]] && cmp -s "$stamp" "$rust_dir/Cargo.lock" && exit 0
  echo "room/third_party/rust/vendor is missing or stale: run $0" >&2
  exit 1
fi

cd "$rust_dir"
cargo vendor --locked --versioned-dirs vendor >/dev/null
python3 "$here/gen_rust_crates.py" "$rust_dir"
cp Cargo.lock "$stamp"
