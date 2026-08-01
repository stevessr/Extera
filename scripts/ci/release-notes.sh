#!/usr/bin/env bash
# Extracts the CHANGELOG.md section for a version into a file usable as a
# release body. Falls back to a single line when there is no matching section.
#
#   release-notes.sh <version> [output-file]
set -euo pipefail

version="${1:?usage: release-notes.sh <version> [output-file]}"
output="${2:-release-notes.md}"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

if [ -f CHANGELOG.md ]; then
  awk -v version="$version" '
    BEGIN {
      escaped = version
      gsub(/\./, "\\.", escaped)
      # Bound the match so 26.4.3 never matches the 26.4.31 heading.
      pattern = "(^|[^0-9.])" escaped "([^0-9.]|$)"
    }
    /^## / {
      if (collecting) exit
      if ($0 ~ pattern) collecting = 1
      next
    }
    collecting { print }
  ' CHANGELOG.md >"$tmp"
fi

# Trim leading and trailing blank lines.
sed -e '/./,$!d' "$tmp" | tac | sed -e '/./,$!d' | tac >"$output"

if [ ! -s "$output" ]; then
  printf 'ExteraNext %s\n' "$version" >"$output"
fi

cat "$output"
