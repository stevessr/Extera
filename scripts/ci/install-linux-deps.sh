#!/usr/bin/env bash
# Installs the apt packages required to build the Flutter Linux desktop bundle.
# Set INSTALL_APPIMAGE_DEPS=true to also pull in the FUSE runtime appimagetool
# needs.
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  sudo=""
else
  sudo="sudo"
fi

packages=(
  git wget curl clang cmake ninja-build pkg-config
  libgtk-3-dev libblkid-dev liblzma-dev libjsoncpp-dev
  cmake-data libsecret-1-dev libsecret-1-0 librhash0
  libssl-dev libwebkit2gtk-4.1-dev
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
  libgstreamer-plugins-good1.0-dev
  libkeybinder-3.0-dev
  libpulse-dev libasound2-dev
  libx11-dev libxcb1-dev libxcb-randr0-dev
  libxrandr-dev libxcomposite-dev libxdamage-dev
  libxrender-dev libxtst-dev libxi-dev
  libegl1-mesa-dev libgl1-mesa-dev
)

if [ "${INSTALL_APPIMAGE_DEPS:-false}" = "true" ]; then
  packages+=(libfuse2 file desktop-file-utils)
fi

export DEBIAN_FRONTEND=noninteractive
$sudo apt-get update
$sudo apt-get install -y --no-install-recommends "${packages[@]}"
