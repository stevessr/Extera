#!/usr/bin/env bash
# Asserts the installed Flutter matches the pin in .tool_versions.yaml.
#
# Worth checking explicitly: if the pinned version fails to reach
# subosito/flutter-action, it installs the latest stable instead of failing, and
# release artifacts would silently be built with an unpinned SDK.
set -euo pipefail

cd "$(dirname "$0")/../.."

expected=$(./scripts/ci/flutter-version.sh)
actual=$(flutter --version | head -1)

if ! grep -qE "(^| )Flutter $expected( |$)" <<<"$actual"; then
  echo "Expected Flutter $expected but found: $actual" >&2
  exit 1
fi

echo "$actual"
