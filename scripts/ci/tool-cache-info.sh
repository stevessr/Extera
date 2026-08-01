#!/usr/bin/env bash
# Emits the runner tool cache location to $GITHUB_OUTPUT.
#
# Read from the environment rather than the runner.tool_cache expression, which
# is not guaranteed to be populated outside GitHub — an empty value would turn
# a cache path into an absolute root path.
set -euo pipefail

root="${RUNNER_TOOL_CACHE:-}"
if [ -z "$root" ]; then
  echo "RUNNER_TOOL_CACHE is not set; cannot cache the JDK." >&2
  exit 1
fi

{
  echo "path=$root"
  echo "java=$root/Java_Zulu_jdk"
} >>"${GITHUB_OUTPUT:-/dev/stdout}"

echo "Tool cache at $root"
