#!/usr/bin/env bash
set -euo pipefail

repository="$1"
commit="$2"
while true; do
  result="$(gh api --method GET "repos/$repository/actions/workflows/ci.yml/runs" \
    -f branch=main -f event=push -f "head_sha=$commit" \
    --jq '(first(.workflow_runs[] | select(.conclusion == "success"))
           // .workflow_runs[0] // {status: "missing"})
          | [.status, (.conclusion // "-"), (.html_url // "-")] | @tsv')"
  IFS=$'\t' read -r status conclusion url <<< "$result"
  case "$status/$conclusion" in
    completed/success)
      printf 'Verified main CI: %s\n' "$url"
      exit 0
      ;;
    completed/*)
      printf 'Main CI concluded with %s: %s\n' "$conclusion" "$url" >&2
      exit 1
      ;;
    missing/*)
      printf 'No main push CI found for %s.\n' "$commit" >&2
      exit 1
      ;;
  esac
  printf 'Waiting for main CI (%s): %s\n' "$status" "$url"
  sleep 15
done
