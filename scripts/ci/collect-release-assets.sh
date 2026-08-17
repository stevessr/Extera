#!/usr/bin/env bash
# Flattens the per-job artifact downloads into one directory and adds
# SHA256SUMS.txt covering everything in it.
#
#   collect-release-assets.sh <download-dir> <output-dir>
set -euo pipefail

source_dir="${1:?usage: collect-release-assets.sh <download-dir> <output-dir>}"
target_dir="${2:?missing output directory}"

rm -rf "$target_dir"
mkdir -p "$target_dir"

find "$source_dir" -type f -exec cp -t "$target_dir" {} +

if [ -z "$(ls -A "$target_dir")" ]; then
  echo "No artifacts found under $source_dir." >&2
  exit 1
fi

# Hash into a temp file outside the directory: writing SHA256SUMS.txt in place
# races with the find that enumerates it, and it would checksum itself.
sums=$(mktemp)
trap 'rm -f "$sums"' EXIT
( cd "$target_dir" && find . -maxdepth 1 -type f -printf '%f\0' | sort -z |
  xargs -0 sha256sum ) >"$sums"
cp "$sums" "$target_dir/SHA256SUMS.txt"

ls -lh "$target_dir"
cat "$target_dir/SHA256SUMS.txt"
