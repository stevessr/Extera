#!/usr/bin/env bash
# Installs Flutter by cloning the SDK, for platforms where no prebuilt archive
# exists (Linux arm64). Adds it to $GITHUB_PATH so later steps can call
# `flutter` directly.
set -euo pipefail

cd "$(dirname "$0")/../.."

version=$(./scripts/ci/flutter-version.sh)
target="${FLUTTER_INSTALL_DIR:-$HOME/flutter}"

if [ ! -x "$target/bin/flutter" ]; then
  git clone --depth 1 --branch "$version" https://github.com/flutter/flutter.git "$target"
fi

export PATH="$target/bin:$PATH"
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$target/bin" >>"$GITHUB_PATH"
fi

git config --global --add safe.directory "$target"
flutter --version
