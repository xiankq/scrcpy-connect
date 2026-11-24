#!/usr/bin/env bash
set -Eeuo pipefail

stage=validate
started=$SECONDS
trap 'status=$?; if (( status != 0 )); then printf "ERROR [GitHub release/%s] Failed after %ss (exit %s)\n" "$stage" "$((SECONDS - started))" "$status" >&2; fi' EXIT

begin() {
  printf 'INFO [GitHub release/%s] Completed in %ss\n' "$stage" "$((SECONDS - started))"
  stage="$1"
  started=$SECONDS
  printf 'INFO [GitHub release/%s] Started\n' "$stage"
}

tag="${GITHUB_REF_NAME:?Missing release tag}"
repo="${GITHUB_REPOSITORY:?Missing GitHub repository}"
preview="${PREVIEW:?Missing release channel}"
notes="$2"
cd "$1"
sha256sum --check --strict SHA256SUMS
expected="$({ cat SHA256SUMS; sha256sum SHA256SUMS; } | jq -Rn '
  [inputs | capture("^(?<hash>[a-f0-9]{64})  (?<name>[a-zA-Z0-9._-]+)$")
    | {name, digest: ("sha256:" + .hash)}] | sort_by(.name)')"

begin draft
draft="$(gh api --paginate "repos/$repo/releases?per_page=100" |
  jq -sr --arg tag "$tag" 'flatten[] | select(.tag_name == $tag) | .draft')"
case "$draft" in
  '')
    gh release create "$tag" --repo "$repo" --draft --verify-tag \
      --title "Interconnect $tag" --notes-file "$notes"
    ;;
  true)
    gh release edit "$tag" --repo "$repo" --notes-file "$notes"
    ;;
  false)
    printf 'ERROR [GitHub release/draft] %s is already public.\n' "$tag" >&2
    exit 1
    ;;
esac
release_id="$(gh release view "$tag" --repo "$repo" --json databaseId --jq .databaseId)"
assets_endpoint="repos/$repo/releases/$release_id/assets?per_page=100"

begin upload
uploaded="$(gh api "$assets_endpoint")"
pending="$(jq -r --argjson uploaded "$uploaded" '
  .[] | . as $asset
  | select(all($uploaded[]; .state != "uploaded" or {name, digest} != $asset))
  | .name' <<< "$expected")"
if [[ -n "$pending" ]]; then
  files=()
  while IFS= read -r name; do files+=("$name"); done <<< "$pending"
  gh release upload "$tag" --repo "$repo" --clobber "${files[@]}"
fi

begin 'verify remote checksums'
gh api "$assets_endpoint" | jq -e --argjson expected "$expected" '
  map(select(.state == "uploaded") | {name, digest}) | sort_by(.name) == $expected' >/dev/null

begin publish
if [[ "$preview" == true ]]; then
  gh release edit "$tag" --repo "$repo" --draft=false --prerelease --latest=false
else
  gh release edit "$tag" --repo "$repo" --draft=false --latest
fi
printf 'INFO [GitHub release/%s] Completed in %ss\n' "$stage" "$((SECONDS - started))"
