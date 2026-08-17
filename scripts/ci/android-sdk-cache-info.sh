#!/usr/bin/env bash
# Emits the Android SDK location and a cache key to $GITHUB_OUTPUT.
#
# The key is built from the Flutter version and the NDK revision. The Flutter
# version is in there because compileSdk follows flutter.compileSdkVersion:
# when Flutter moves, Gradle pulls a different platform and build-tools, and
# the cache has to be rebuilt to pick them up. Nothing else about
# build.gradle.kts changes what is installed, so nothing else belongs in the
# key.
set -euo pipefail

cd "$(dirname "$0")/../.."

root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$root" ]; then
  echo "Neither ANDROID_HOME nor ANDROID_SDK_ROOT was exported by setup-android." >&2
  exit 1
fi

flutter_version=$(./scripts/ci/flutter-version.sh)
ndk_version=$(./scripts/ci/android-ndk-version.sh)

key=$(printf 'flutter=%s|ndk=%s' "$flutter_version" "$ndk_version" | sha256sum | cut -c1-16)

{
  echo "path=$root"
  echo "key=$key"
} >>"${GITHUB_OUTPUT:-/dev/stdout}"

echo "Android SDK at $root (cache key $key, flutter $flutter_version, ndk ${ndk_version:-none})"
