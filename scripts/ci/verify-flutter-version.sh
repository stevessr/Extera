#!/usr/bin/env bash
# Asserts the installed Flutter matches FLUTTER_VERSION.
#
# Worth checking explicitly: if the pinned version fails to reach
# subosito/flutter-action, it installs the latest stable instead of failing, and
# release artifacts would silently be built with an unpinned SDK.
set -euo pipefail

expected="${FLUTTER_VERSION:-}"
if [ -z "$expected" ]; then
  echo "FLUTTER_VERSION is empty; versions.env was not loaded." >&2
  exit 1
fi

actual=$(flutter --version | head -1)

if ! grep -qE "(^| )Flutter $expected( |$)" <<<"$actual"; then
  echo "Expected Flutter $expected but found: $actual" >&2
  exit 1
fi

echo "$actual"
