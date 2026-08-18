#!/usr/bin/env bash
# Decides which platform builds a pull request actually needs and writes the
# result to $GITHUB_OUTPUT as android/web/linux/ios booleans.
#
# Fails open: if the diff cannot be determined for any reason, every area is
# reported as changed so a broken detection never hides a broken build.
#
# Manual target overrides (MANUAL_ANDROID, MANUAL_WEB, MANUAL_LINUX, MANUAL_IOS):
# When any manual target is set to "true", only build those targets and skip
# change detection. This enables workflow_dispatch target selection.
#
# Deliberately no pipefail: `grep -q` exits on its first match, which can leave
# the writer in the pipe with SIGPIPE and would make matching flaky.
set -u

out="${GITHUB_OUTPUT:-/dev/stdout}"

emit() {
  printf 'android=%s\nweb=%s\nlinux=%s\nios=%s\n' "$1" "$2" "$3" "$4" >>"$out"
  printf 'android=%s web=%s linux=%s ios=%s\n' "$1" "$2" "$3" "$4"
}

emit_all() {
  echo "$1"
  emit true true true true
  exit 0
}

# Check for manual target selection (workflow_dispatch inputs).
# When any manual target is selected, use only those and skip detection.
manual_android="${MANUAL_ANDROID:-false}"
manual_web="${MANUAL_WEB:-false}"
manual_linux="${MANUAL_LINUX:-false}"
manual_ios="${MANUAL_IOS:-false}"

if [ "$manual_android" = "true" ] || [ "$manual_web" = "true" ] || [ "$manual_linux" = "true" ] || [ "$manual_ios" = "true" ]; then
  echo "Manual target selection active."
  emit "$manual_android" "$manual_web" "$manual_linux" "$manual_ios"
  exit 0
fi

[ "${FORCE_ALL:-false}" = "true" ] && emit_all "Building everything on request."

base="${BASE_REF:-}"
[ -n "$base" ] || emit_all "No base ref available, building everything."

# A shallow checkout may already carry the base branch; only fetch if it does not.
git fetch --no-tags --depth=200 origin "+refs/heads/$base:refs/remotes/origin/$base" >/dev/null 2>&1 || true

base_ref=""
for candidate in "refs/remotes/origin/$base" "refs/heads/$base"; do
  if git rev-parse --verify --quiet "$candidate" >/dev/null; then
    base_ref="$candidate"
    break
  fi
done

[ -n "$base_ref" ] || emit_all "Base branch $base is not available, building everything."

merge_base=$(git merge-base "$base_ref" HEAD 2>/dev/null) ||
  emit_all "No merge base with $base_ref, building everything."

files=$(git diff --name-only "$merge_base" HEAD) ||
  emit_all "Could not diff against $merge_base, building everything."

[ -n "$files" ] && printf 'Changed files:\n%s\n\n' "$files"

# Anything that can change how every platform is built.
shared='^(pubspec\.(yaml|lock)|\.github/|scripts/ci/|analysis_options\.yaml)'

# A here-string rather than a pipe: `grep -q` exits on its first match, and a
# pipe writer would then take SIGPIPE once the file list outgrows the buffer.
matches() { grep -qE "$1" <<<"$files"; }

android=false
web=false
linux=false
ios=false

matches "$shared|^(android/|assets/l10n/|scripts/generate-locale-config\.sh)" && android=true
# Dart changes are included here because dart:io usage that analysis accepts
# still breaks the web build.
matches "$shared|^(web/|lib/|assets/|scripts/prepare-web\.sh)" && web=true
matches "$shared|^(linux/|appimage/|scripts/build-(linux|appimage)\.sh)" && linux=true
# Shared Dart code and iOS-specific changes affect iOS builds.
matches "$shared|^(ios/|lib/|assets/)" && ios=true

emit "$android" "$web" "$linux" "$ios"
