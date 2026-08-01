#!/usr/bin/env bash
# Installs the Android SDK components Gradle needs and accepts their licences.
#
# The package list comes from ANDROID_SDK_PACKAGES (.github/workflows/versions.env);
# the NDK revision is read from android/app/build.gradle.kts so the two can
# never disagree. Safe to run on a warm cache: sdkmanager skips what is already
# installed.
set -euo pipefail

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

read -r -a packages <<<"${ANDROID_SDK_PACKAGES:-}"

ndk_version=$(sed -nE 's/^[[:space:]]*ndkVersion[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
  android/app/build.gradle.kts | head -1 || true)
if [ -n "$ndk_version" ]; then
  packages+=("ndk;$ndk_version")
fi

if [ ${#packages[@]} -eq 0 ]; then
  echo "No SDK packages requested."
  exit 0
fi

# sdkmanager closes stdin as soon as it stops reading answers, which kills `yes`
# with SIGPIPE; swallow that so pipefail does not abort the script.
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
