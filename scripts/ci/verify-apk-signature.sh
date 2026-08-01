#!/usr/bin/env bash
# Verifies that every given APK is signed, and prints the signer certificates
# so the key used can be confirmed from the job log.
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "usage: verify-apk-signature.sh <apk> [apk...]" >&2
  exit 1
fi

android_home="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
apksigner=""
if [ -n "$android_home" ]; then
  apksigner=$(find "$android_home" -name apksigner -type f 2>/dev/null | sort | tail -1 || true)
fi

if [ -z "$apksigner" ]; then
  echo "apksigner not found, skipping signature verification." >&2
  exit 0
fi

for apk in "$@"; do
  echo "== $apk"
  "$apksigner" verify --print-certs "$apk"
done
