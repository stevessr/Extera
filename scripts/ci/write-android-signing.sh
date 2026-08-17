#!/usr/bin/env bash
# Materialises android/key.jks and android/key.properties from the release
# signing secrets. KEY_ALIAS is optional and defaults to "key".
set -euo pipefail

for name in KEYSTORE_FILE KEYSTORE_PASS KEY_PASS; do
  if [ -z "${!name:-}" ]; then
    echo "Secret $name is not set; the release APK cannot be signed." >&2
    exit 1
  fi
done

umask 077

printf '%s' "$KEYSTORE_FILE" | base64 --decode >android/key.jks

if [ ! -s android/key.jks ]; then
  echo "Decoded keystore is empty; is KEYSTORE_FILE valid base64?" >&2
  exit 1
fi

# java.util.Properties reads a backslash as an escape character, so backslashes
# in a password have to be doubled. printf also keeps the value away from shell
# expansion, which an unquoted heredoc would not.
write_property() {
  printf '%s=%s\n' "$1" "$(printf '%s' "$2" | sed 's/\\/\\\\/g')"
}

{
  write_property storePassword "$KEYSTORE_PASS"
  write_property keyPassword "$KEY_PASS"
  write_property keyAlias "${KEY_ALIAS:-key}"
  write_property storeFile key.jks
} >android/key.properties

echo "Signing configuration written ($(wc -c <android/key.jks) byte keystore)."
