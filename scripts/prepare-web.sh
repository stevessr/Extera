#!/bin/sh -e

# Compile the Wasm-enabled vodozemac bridge from the same stable releases
# resolved by Pub. Keeping both versions sourced from pubspec.lock prevents
# generated Dart/Rust bindings from drifting away from the runtime packages.
vodozemac_version=$(yq -r '.packages.flutter_vodozemac.version' pubspec.lock)
frb_codegen_version=$(yq -r '.packages.flutter_rust_bridge.version' pubspec.lock)
if [ -z "$vodozemac_version" ] || [ "$vodozemac_version" = "null" ]; then
  echo "Unable to resolve flutter_vodozemac version from pubspec.lock" >&2
  exit 1
fi
if [ -z "$frb_codegen_version" ] || [ "$frb_codegen_version" = "null" ]; then
  echo "Unable to resolve flutter_rust_bridge version from pubspec.lock" >&2
  exit 1
fi

rm -rf .vodozemac
git clone --depth 1 https://github.com/famedly/dart-vodozemac.git \
  --branch "$vodozemac_version" .vodozemac
cd .vodozemac

# Cached in CI via ~/.cargo/bin. Reinstall only when the cached binary does
# not match the FRB runtime selected by Pub.
if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1 \
  || [ "$(flutter_rust_bridge_codegen --version)" != "flutter_rust_bridge_codegen $frb_codegen_version" ]; then
  cargo install flutter_rust_bridge_codegen \
    --version "=$frb_codegen_version" --locked --force
fi

flutter_rust_bridge_codegen build-web --dart-root dart --rust-root \
  "$(readlink -f rust)" --release
cd ..
mkdir -p ./assets/vodozemac
rm -f ./assets/vodozemac/vodozemac_bindings_dart*
mv .vodozemac/dart/web/pkg/vodozemac_bindings_dart* ./assets/vodozemac/
rm -rf .vodozemac
# Keep the generated package graph valid with the Pub version bundled by the
# CI Flutter SDK; web preparation does not need dependency examples.
flutter pub get --no-example

# Download native_imaging for web:
version=$(yq ".dependencies.native_imaging" < pubspec.yaml)
version=$(printf "%s" "$version" | tr -d '"^')
curl -L "https://github.com/famedly/dart_native_imaging/releases/download/v${version}/native_imaging.zip" > native_imaging.zip
unzip -o native_imaging.zip
mv js/* web/
rmdir js
rm native_imaging.zip

# Compile the matrix SDK native-implementations web worker (image resizing
# and metadata calculation off the main thread). Pure Dart entry point, so
# it is compiled to JS and serves both the js and wasm bundles. Output is
# gitignored; the CI build-web-app action compiles it into build/web itself.
dart compile js --minify -O4 \
  -o web/native_impl_worker.dart.js web/native_impl_worker.dart
