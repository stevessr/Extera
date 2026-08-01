#!/usr/bin/env bash
# Installs the pinned yq release to /usr/local/bin. No-op if the right version
# is already present.
set -euo pipefail

version="${YQ_VERSION:-v4.53.3}"
target="${YQ_INSTALL_DIR:-/usr/local/bin}/yq"

if [ -x "$target" ] && "$target" --version 2>/dev/null | grep -q "${version#v}"; then
  echo "yq ${version} already installed."
  exit 0
fi

if [ "$(id -u)" -eq 0 ]; then
  sudo=""
else
  sudo="sudo"
fi

case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

url="https://github.com/mikefarah/yq/releases/download/${version}/yq_linux_${arch}"
$sudo curl -fsSL -o "$target" "$url"
$sudo chmod +x "$target"
"$target" --version
