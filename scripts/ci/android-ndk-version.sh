#!/usr/bin/env bash
# Prints the NDK revision pinned in android/app/build.gradle.kts, the only
# place it is declared. Prints nothing if the build does not pin one.
set -euo pipefail

cd "$(dirname "$0")/../.."

sed -nE 's/^[[:space:]]*ndkVersion[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
  android/app/build.gradle.kts | head -1 || true
