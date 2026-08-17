#!/usr/bin/env bash
# Prints the pinned Flutter version from .tool_versions.yaml, the single source
# of truth that subosito/flutter-action reads via flutter-version-file.
set -euo pipefail

file="${TOOL_VERSIONS_FILE:-.tool_versions.yaml}"

version=$(sed -nE 's/^[[:space:]]*flutter:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' "$file" | head -1 || true)

if [ -z "$version" ]; then
  echo "No flutter version found in $file" >&2
  exit 1
fi

printf '%s\n' "$version"
