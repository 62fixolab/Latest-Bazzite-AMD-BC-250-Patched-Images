#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
PUBLISH=0
OWNER=""
REPO=""

usage() {
  cat <<'EOF'
Usage:
  scripts/backfill-releases.sh [--publish]

Creates local release-preview/*.md files for every date found in GHCR.
With --publish, creates or updates one GitHub Release per date.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish)
      PUBLISH=1
      shift
      ;;
    --owner)
      OWNER="${2:?Missing value for --owner}"
      shift 2
      ;;
    --repo)
      REPO="${2:?Missing value for --repo}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$OWNER" || -z "$REPO" ]]; then
  OWNER="${OWNER:-$(gh repo view --json owner --jq '.owner.login')}"
  REPO="${REPO:-$(gh repo view --json name --jq '.name')}"
fi

dates=()
while IFS= read -r release_date; do
  dates+=("$release_date")
done < <("$ROOT/scripts/generate-release-notes.py" --owner "$OWNER" --repo "$REPO" --list-dates)

for release_date in "${dates[@]}"; do
  cmd=("$ROOT/scripts/publish-release.sh" --owner "$OWNER" --repo "$REPO" --date "$release_date")

  package_commit="$(
    "$ROOT/scripts/generate-release-notes.py" \
      --owner "$OWNER" \
      --repo "$REPO" \
      --date "$release_date" \
      --print-package-commit-tag
  )"
  if [[ -n "$package_commit" ]]; then
    target_commit="$(git rev-parse --verify --quiet "${package_commit}^{commit}" || true)"
    if [[ -n "$target_commit" ]]; then
      cmd+=(--target "$target_commit")
    fi
  fi

  if [[ "$PUBLISH" -eq 1 ]]; then
    cmd+=(--publish)
  fi
  "${cmd[@]}"
done
