#!/usr/bin/env bash
# Reports whether the runner actually offers a cache service.
#
# Worth checking on every job: when the cache is disabled, or the cache server
# is not reachable from the job container, actions/cache only warns and the
# build carries on rebuilding everything from scratch. That failure is
# invisible unless someone reads the log closely.
#
# Set CACHE_REQUIRED=true to turn a missing cache into a hard failure.
set -euo pipefail

url="${ACTIONS_CACHE_URL:-}"

if [ -z "$url" ]; then
  echo "::warning::No ACTIONS_CACHE_URL: this runner provides no cache, every dependency will be re-downloaded. Set cache.enabled in the runner config."
  if [ "${CACHE_REQUIRED:-false}" = "true" ]; then
    exit 1
  fi
  exit 0
fi

echo "Cache service: $url"

# A cache miss answers 204, a hit 200; anything else means the server is not
# reachable from inside the job container, which is the usual Docker
# networking mistake (runner needs cache.host / cache.proxy_port set).
probe=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
  "${url%/}/_apis/artifactcache/cache?keys=ci-cache-probe&version=1" 2>/dev/null) || true
probe="${probe:-000}"

case "$probe" in
  200 | 204)
    echo "Cache service reachable (HTTP $probe)."
    ;;
  *)
    echo "::warning::Cache service at $url did not answer (HTTP $probe). Caches will silently miss on every run."
    if [ "${CACHE_REQUIRED:-false}" = "true" ]; then
      exit 1
    fi
    ;;
esac
