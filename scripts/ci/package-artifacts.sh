#!/usr/bin/env bash
# Collects a built target into artifacts/ under its published release name.
#
#   package-artifacts.sh apk      <tag>
#   package-artifacts.sh linux    <tag> [arch]
#   package-artifacts.sh appimage <tag> [arch]
#   package-artifacts.sh web      <tag>
set -euo pipefail

cd "$(dirname "$0")/../.."

target="${1:?usage: package-artifacts.sh <apk|linux|appimage|web> <tag> [arch]}"
tag="${2:?missing tag}"
arch="${3:-x64}"

mkdir -p artifacts

case "$target" in
  apk)
    cp build/app/outputs/flutter-apk/app-frelease-release.apk \
      "artifacts/ExteraNext-$tag-android.apk"
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
    tar -czf "artifacts/ExteraNext-$tag-web.tar.gz" -C build/web .
    ;;
  *)
    echo "Unknown target: $target" >&2
    exit 1
    ;;
esac

ls -lh artifacts
