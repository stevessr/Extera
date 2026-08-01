#!/usr/bin/env bash
# Emits the Android SDK location and a cache key to $GITHUB_OUTPUT.
#
# The key covers only what changes the installed components — the requested
# package list and the NDK revision — so unrelated edits to build.gradle.kts do
# not throw away a multi-gigabyte cache.
set -euo pipefail

root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$root" ]; then
  echo "Neither ANDROID_HOME nor ANDROID_SDK_ROOT was exported by setup-android." >&2
  exit 1
fi

ndk_version=$(sed -nE 's/^[[:space:]]*ndkVersion[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
  android/app/build.gradle.kts | head -1 || true)

key=$(printf '%s|%s' "${ANDROID_SDK_PACKAGES:-}" "$ndk_version" | sha256sum | cut -c1-16)

{
  echo "path=$root"
  echo "key=$key"
} >>"${GITHUB_OUTPUT:-/dev/stdout}"

echo "Android SDK at $root (cache key $key, ndk ${ndk_version:-none})"
