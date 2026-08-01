#!/usr/bin/env bash
# Packs an existing Linux release bundle into bundle.tar.gz next to it.
# The bundle contents sit at the archive root, matching what the release
# workflow publishes.
#
# Build the bundle first:
#   flutter build linux --release
#   ./scripts/build-linux.sh [x64|arm64]
set -euo pipefail

cd "$(dirname "$0")/.."

arch="${1:-x64}"
release_dir="build/linux/$arch/release"

if [ ! -d "$release_dir/bundle" ]; then
  echo "Missing $release_dir/bundle. Run 'flutter build linux --release' first." >&2
  exit 1
fi

tar -czf "$release_dir/bundle.tar.gz" -C "$release_dir/bundle" .

echo "Built $release_dir/bundle.tar.gz"
