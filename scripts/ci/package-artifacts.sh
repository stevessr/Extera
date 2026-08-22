#!/usr/bin/env bash
# Collects a built target into artifacts/ under its published release name.
#
#   package-artifacts.sh apk      <tag> [armv7|armv8|x86_64]
#   package-artifacts.sh linux    <tag> [arch]
#   package-artifacts.sh appimage <tag> [arch]
#   package-artifacts.sh web      <tag> [js|wasm]
set -euo pipefail

cd "$(dirname "$0")/../.."

target="${1:?usage: package-artifacts.sh <apk|linux|appimage|web> <tag> [arch]}"
tag="${2:?missing tag}"
arch="${3:-x64}"

mkdir -p artifacts

find_apk() {
  # Flutter reports the APK under flutter-apk/, but a flavoured Gradle build
  # also leaves one under apk/. Take whichever exists.
  local candidate
  for candidate in \
    build/app/outputs/flutter-apk/app-frelease-release.apk \
    build/app/outputs/apk/fRelease/release/app-frelease-release.apk \
    build/app/outputs/apk/release/app-frelease-release.apk; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "No release APK found under build/app/outputs." >&2
  find build/app/outputs -name '*.apk' >&2 || true
  return 1
}

case "$target" in
  apk)
    case "$arch" in
      armv7|armv8|x86_64)
        artifact_name="ExteraNext-$tag-android-$arch.apk"
        ;;
      x64|universal)
        # Keep the old name usable for local callers that do not request an
        # architecture-specific artifact.
        artifact_name="ExteraNext-$tag-android.apk"
        ;;
      *)
        echo "Unknown Android ABI label: $arch" >&2
        exit 1
        ;;
    esac
    cp "$(find_apk)" "artifacts/$artifact_name"
    ;;
  linux)
    ./scripts/build-linux.sh "$arch"
    cp "build/linux/$arch/release/bundle.tar.gz" \
      "artifacts/ExteraNext-$tag-linux-$arch.tar.gz"
    ;;
  appimage)
    ./scripts/build-appimage.sh "$arch"
    case "$arch" in
      x64) appimage_arch=x86_64 ;;
      arm64) appimage_arch=aarch64 ;;
      *) appimage_arch="$arch" ;;
    esac
    cp "appimage/Extera_Next-$appimage_arch.AppImage" \
      "artifacts/ExteraNext-$tag-$appimage_arch.AppImage"
    ;;
  web)
    case "$arch" in
      ''|js|x64|universal) suffix='' ;;
      *) suffix="-$arch" ;;
    esac
    tar -czf "artifacts/ExteraNext-$tag-web$suffix.tar.gz" -C build/web .
    ;;
  *)
    echo "Unknown target: $target" >&2
    exit 1
    ;;
esac

ls -lh artifacts
