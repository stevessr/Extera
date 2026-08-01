#!/usr/bin/env bash
# Assembles appimage/Extera.AppDir from an existing Linux release bundle and
# runs appimagetool over it.
#
# Build the bundle first:
#   flutter build linux --release
#   ./scripts/build-appimage.sh [x64|arm64]
set -euo pipefail

cd "$(dirname "$0")/.."

arch="${1:-x64}"
bundle="build/linux/$arch/release/bundle"
appdir="appimage/Extera.AppDir"

case "$arch" in
  x64) appimage_arch=x86_64 ;;
  arm64) appimage_arch=aarch64 ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

if [ ! -d "$bundle" ]; then
  echo "Missing $bundle. Run 'flutter build linux --release' first." >&2
  exit 1
fi

rm -rf "$appdir"
mkdir -p "$appdir/usr/share/icons"
cp -r "$bundle"/. "$appdir/"
cp appimage/Extera.desktop "$appdir/"
cp assets/logo.svg "$appdir/extera.svg"
install -m 755 appimage/AppRun "$appdir/AppRun"

output="appimage/Extera_Next-$appimage_arch.AppImage"
rm -f "$output"
ARCH="$appimage_arch" appimagetool "$appdir" "$output"

echo "Built $output"
