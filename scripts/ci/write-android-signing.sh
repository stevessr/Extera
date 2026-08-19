#!/usr/bin/env bash
# Materialises android/key.properties using either:
# 1) release signing secrets, or
# 2) a CI debug keystore fallback when those secrets are entirely absent.
set -euo pipefail

umask 077

# java.util.Properties reads a backslash as an escape character, so backslashes
# in a password have to be doubled. printf also keeps the value away from shell
# expansion, which an unquoted heredoc would not.
write_property() {
  printf '%s=%s\n' "$1" "$(printf '%s' "$2" | sed 's/\\/\\\\/g')"
}

has_keystore_file=false
has_keystore_pass=false
has_key_pass=false

[ -n "${KEYSTORE_FILE:-}" ] && has_keystore_file=true
[ -n "${KEYSTORE_PASS:-}" ] && has_keystore_pass=true
[ -n "${KEY_PASS:-}" ] && has_key_pass=true

if $has_keystore_file || $has_keystore_pass || $has_key_pass; then
  for name in KEYSTORE_FILE KEYSTORE_PASS KEY_PASS; do
    if [ -z "${!name:-}" ]; then
      echo "Secret $name is not set; provide all release signing secrets or none." >&2
      exit 1
    fi
  done

  printf '%s' "$KEYSTORE_FILE" | base64 --decode >android/key.jks

  if [ ! -s android/key.jks ]; then
    echo "Decoded keystore is empty; is KEYSTORE_FILE valid base64?" >&2
    exit 1
  fi

  {
    write_property storePassword "$KEYSTORE_PASS"
    write_property keyPassword "$KEY_PASS"
    write_property keyAlias "${KEY_ALIAS:-key}"
    write_property storeFile ../key.jks
  } >android/key.properties

  echo "Release signing configuration written ($(wc -c <android/key.jks) byte keystore)."
  exit 0
fi

debug_keystore="android/debug-ci.keystore"
if [ ! -s "$debug_keystore" ]; then
  keytool -genkeypair \
    -keystore "$debug_keystore" \
    -storepass android \
    -alias androiddebugkey \
    -keypass android \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -storetype PKCS12 \
    -dname "CN=Android Debug,O=Android,C=US" \
    -noprompt
fi

{
  write_property storePassword android
  write_property keyPassword android
  write_property keyAlias androiddebugkey
  write_property storeFile ../debug-ci.keystore
} >android/key.properties

echo "Release secrets missing; using CI debug signing configuration ($(wc -c <"$debug_keystore") byte keystore)."
