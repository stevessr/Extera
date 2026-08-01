#!/usr/bin/env bash
# Prepares the Android SDK for a Gradle build.
#
# No API level is installed here on purpose. compileSdk follows
# flutter.compileSdkVersion, so the Android Gradle Plugin downloads the
# matching platform and build-tools itself once the licences are accepted;
# pinning them in CI would only drift from whatever Flutter asks for.
#
# The NDK is preinstalled because its revision is pinned in
# android/app/build.gradle.kts and it is large enough to be worth caching.
# Safe to run on a warm cache: sdkmanager skips what is already installed.
set -euo pipefail

cd "$(dirname "$0")/../.."

android_home="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$android_home" ]; then
  echo "ANDROID_HOME is not set. Run android-actions/setup-android first." >&2
  exit 1
fi

sdkmanager=""
for candidate in "$android_home/cmdline-tools/latest/bin/sdkmanager" \
                 "$android_home"/cmdline-tools/*/bin/sdkmanager; do
  if [ -x "$candidate" ]; then
    sdkmanager="$candidate"
    break
  fi
done

if [ -z "$sdkmanager" ]; then
  echo "sdkmanager not found under $android_home" >&2
  exit 1
fi

packages=(platform-tools)

ndk_version=$(./scripts/ci/android-ndk-version.sh)
if [ -n "$ndk_version" ]; then
  packages+=("ndk;$ndk_version")
fi

# sdkmanager closes stdin as soon as it stops reading answers, which kills `yes`
# with SIGPIPE; swallow that so pipefail does not abort the script.
# Accepting the licences is also what lets Gradle fetch the compile SDK.
( yes || true ) | "$sdkmanager" --licenses >/dev/null
( yes || true ) | "$sdkmanager" "${packages[@]}"

# Check source.properties rather than the directory: an interrupted sdkmanager
# leaves the directory behind half-extracted, and that would otherwise be
# cached and fail later inside Gradle with an unrelated-looking error.
for package in "${packages[@]}"; do
  path="$android_home/${package//;//}"
  if [ ! -f "$path/source.properties" ]; then
    echo "$package looks incomplete: $path/source.properties is missing." >&2
    ls -la "$path" >&2 || true
    exit 1
  fi
done

echo "Installed: ${packages[*]}"
