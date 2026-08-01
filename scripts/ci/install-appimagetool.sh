#!/usr/bin/env bash
# Installs appimagetool to /usr/local/bin.
set -euo pipefail

target="${APPIMAGETOOL_INSTALL_DIR:-/usr/local/bin}/appimagetool"

if [ -x "$target" ]; then
  echo "appimagetool already installed."
  exit 0
fi

if [ "$(id -u)" -eq 0 ]; then
  sudo=""
else
  sudo="sudo"
fi

case "$(uname -m)" in
  x86_64) arch=x86_64 ;;
  aarch64 | arm64) arch=aarch64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

url="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${arch}.AppImage"
$sudo curl -fsSL -o "$target" "$url"
$sudo chmod +x "$target"
