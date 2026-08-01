#!/usr/bin/env bash
# Resolves the tag, version and prerelease flag for a release run and writes
# them to $GITHUB_OUTPUT. Reads RELEASE_TAG when set (manual dispatch),
# otherwise the pushed ref.
set -euo pipefail

tag="${RELEASE_TAG:-}"
[ -n "$tag" ] || tag="${GITHUB_REF_NAME:-}"

if [ -z "$tag" ]; then
  echo "No tag supplied and GITHUB_REF_NAME is empty." >&2
  exit 1
fi

if ! printf '%s' "$tag" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$'; then
  echo "Tag '$tag' is not of the form vMAJOR.MINOR.PATCH[-suffix]." >&2
  exit 1
fi

version="${tag#v}"

# A suffix after the patch number marks a prerelease, e.g. v1.2.3-rc1.
case "$version" in
  *-*) prerelease=true ;;
  *) prerelease=false ;;
esac

pubspec_version=$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml | head -1 || true)
if [ "$prerelease" = "false" ] && [ "$pubspec_version" != "$version" ]; then
  echo "Tag $tag does not match pubspec.yaml version $pubspec_version." >&2
  exit 1
fi

{
  echo "tag=$tag"
  echo "version=$version"
  echo "prerelease=$prerelease"
} >>"${GITHUB_OUTPUT:-/dev/stdout}"

echo "tag=$tag version=$version prerelease=$prerelease"
