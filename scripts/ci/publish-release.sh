#!/usr/bin/env bash
# Publishes a release on Forgejo through the Gitea-compatible API.
#
# The release is created as a draft, every asset is uploaded, and only then is
# the draft flag cleared — so a release is never visible half-populated. Re-runs
# are safe: existing assets with the same name are replaced.
#
# Required environment:
#   RELEASE_TOKEN, GITHUB_API_URL, GITHUB_REPOSITORY, TAG
# Optional:
#   PRERELEASE (false), ASSETS_DIR (release-assets), NOTES_FILE (release-notes.md),
#   KEEP_DRAFT (false), TARGET_COMMITISH
set -euo pipefail

: "${RELEASE_TOKEN:?RELEASE_TOKEN is required}"
: "${GITHUB_API_URL:?GITHUB_API_URL is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${TAG:?TAG is required}"

prerelease="${PRERELEASE:-false}"
assets_dir="${ASSETS_DIR:-release-assets}"
notes_file="${NOTES_FILE:-release-notes.md}"
keep_draft="${KEEP_DRAFT:-false}"

api="$GITHUB_API_URL/repos/$GITHUB_REPOSITORY"

# Passing the token through a config file keeps it out of curl's argv, which is
# world-readable via /proc on a shared runner.
curl_config=$(mktemp)
response=$(mktemp)
trap 'rm -f "$curl_config" "$response"' EXIT
chmod 600 "$curl_config"
printf 'header = "Authorization: token %s"\nsilent\nshow-error\n' "$RELEASE_TOKEN" >"$curl_config"

api_curl() {
  curl --config "$curl_config" "$@"
}

# --fail-with-body writes the error body to stdout, so keep it and surface it
# instead of discarding the only diagnostic a failed call produces.
api_call() {
  if ! api_curl --fail-with-body "$@" >"$response" 2>&1; then
    echo "Request failed:" >&2
    cat "$response" >&2
    return 1
  fi
}

notes="ExteraNext $TAG"
if [ -s "$notes_file" ]; then
  notes=$(cat "$notes_file")
fi

status=$(api_curl -o "$response" -w '%{http_code}' "$api/releases/tags/$TAG")

if [ "$status" = "200" ]; then
  release_id=$(jq -r '.id' "$response")
  echo "Reusing release #$release_id for $TAG."
  payload=$(jq -n --arg body "$notes" --argjson pre "$prerelease" \
    '{body: $body, prerelease: $pre, draft: true}')
  api_call -X PATCH -H 'Content-Type: application/json' -d "$payload" \
    "$api/releases/$release_id"
else
  payload=$(jq -n \
    --arg tag "$TAG" \
    --arg body "$notes" \
    --arg target "${TARGET_COMMITISH:-}" \
    --argjson pre "$prerelease" \
    '{tag_name: $tag, name: $tag, body: $body, draft: true, prerelease: $pre}
     + (if $target == "" then {} else {target_commitish: $target} end)')
  api_call -X POST -H 'Content-Type: application/json' -d "$payload" "$api/releases"
  release_id=$(jq -r '.id // empty' "$response")
  if [ -z "$release_id" ]; then
    echo "Release was created but the response carried no id:" >&2
    cat "$response" >&2
    exit 1
  fi
  echo "Created draft release #$release_id for $TAG."
fi

delete_existing_asset() {
  local name="$1" id
  for id in $(api_curl "$api/releases/$release_id/assets" |
              jq -r --arg name "$name" '.[]? | select(.name == $name) | .id'); do
    api_curl -X DELETE "$api/releases/$release_id/assets/$id" >/dev/null
  done
}

upload_asset() {
  local file="$1" name attempt
  name=$(basename "$file")
  delete_existing_asset "$name"

  for attempt in 1 2 3; do
    if api_call -X POST -F "attachment=@$file" \
         "$api/releases/$release_id/assets?name=$name"; then
      echo "  uploaded $name"
      return 0
    fi
    echo "  attempt $attempt to upload $name failed" >&2
    sleep $((attempt * 5))
  done

  echo "Giving up on $name after 3 attempts." >&2
  return 1
}

shopt -s nullglob
assets=("$assets_dir"/*)
shopt -u nullglob

if [ ${#assets[@]} -eq 0 ]; then
  echo "No assets found in $assets_dir." >&2
  exit 1
fi

for asset in "${assets[@]}"; do
  if [ -f "$asset" ]; then
    upload_asset "$asset"
  fi
done

if [ "$keep_draft" = "true" ]; then
  echo "Release #$release_id left as a draft."
  exit 0
fi

api_call -X PATCH -H 'Content-Type: application/json' -d '{"draft": false}' \
  "$api/releases/$release_id"

echo "Published release $TAG (#$release_id)."
