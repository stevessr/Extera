#!/usr/bin/env bash
# Collects a built target into artifacts/ under its published release name.
#
#   package-artifacts.sh apk      <tag> [armv7|armv8|x86_64]
#   package-artifacts.sh linux    <tag> [arch]
#   package-artifacts.sh appimage <tag> [arch]
#   package-artifacts.sh web      <tag> [js|wasm]
#   package-artifacts.sh ios      <tag>
#   package-artifacts.sh macos    <tag>
set -euo pipefail

cd "$(dirname "$0")/../.."

target="${1:?usage: package-artifacts.sh <apk|linux|appimage|web|ios|macos> <tag> [arch]}"
tag="${2:?missing tag}"
arch="${3:-x64}"

# Artifact names carry enough provenance to identify the exact build without
# consulting CI metadata. BUILD_DATE / COMMIT_HASH can be overridden by local
# callers; CI defaults to the UTC production date and checked-out commit.
build_date="${BUILD_DATE:-$(date -u +%Y%m%d)}"
commit_hash="${COMMIT_HASH:-$(git rev-parse --short=8 HEAD 2>/dev/null || printf unknown)}"
provenance="${build_date}-${commit_hash}"

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

find_apple_app() {
  local directory="$1"
  local app
  app="$(find "$directory" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null || true)"
  if [ -n "$app" ]; then
    printf '%s\n' "$app"
    return 0
  fi
  echo "No .app bundle found under $directory." >&2
  find "$directory" -maxdepth 2 -name '*.app' -print >&2 2>/dev/null || true
  return 1
}

case "$target" in
  apk)
    case "$arch" in
      armv7|armv8|x86_64)
        artifact_name="ExteraNext-$tag-android-$arch-$provenance.apk"
        ;;
      x64|universal)
        artifact_name="ExteraNext-$tag-android-$provenance.apk"
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
      "artifacts/ExteraNext-$tag-linux-$arch-$provenance.tar.gz"
    ;;
  appimage)
    ./scripts/build-appimage.sh "$arch"
    case "$arch" in
      x64) appimage_arch=x86_64 ;;
      arm64) appimage_arch=aarch64 ;;
      *) appimage_arch="$arch" ;;
    esac
    cp "appimage/Extera_Next-$appimage_arch.AppImage" \
      "artifacts/ExteraNext-$tag-linux-$appimage_arch-$provenance.AppImage"
    ;;
  web)
    case "$arch" in
      ''|js|x64|universal) suffix='' ;;
      *) suffix="-$arch" ;;
    esac
    tar -czf "artifacts/ExteraNext-$tag-web$suffix-$provenance.tar.gz" -C build/web .
    ;;
  ios)
    app="$(find_apple_app build/ios/iphoneos)"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT
    mkdir -p "$tmpdir/Payload"
    cp -R "$app" "$tmpdir/Payload/"
    (
      cd "$tmpdir"
      zip -qry "$OLDPWD/artifacts/ExteraNext-$tag-ios-unsigned-$provenance.ipa" Payload
    )
    ;;
  macos)
    app="$(find_apple_app build/macos/Build/Products/Release)"
    ditto -c -k --sequesterRsrc --keepParent "$app" \
      "artifacts/ExteraNext-$tag-macos-$provenance.zip"
    ;;
  *)
    echo "Unknown target: $target" >&2
    exit 1
    ;;
esac

ls -lh artifacts
