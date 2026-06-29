#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
DATE=""
PUBLISH=0
OWNER=""
REPO=""
TARGET=""
RUN_URL=""
OUTPUT=""

usage() {
  cat <<'EOF'
Usage:
  scripts/publish-release.sh --date YYYY.MM.DD [--publish]

Options:
  --date DATE       Release date, accepts YYYY.MM.DD, YYYY-MM-DD, or YYYYMMDD.
  --publish         Create or update the GitHub Release. Omit for dry-run.
  --owner OWNER     GitHub/GHCR owner. Defaults to current repo owner.
  --repo REPO       GitHub repo name. Defaults to current repo name.
  --target SHA      Target commit for the Release tag. Defaults to HEAD.
  --run-url URL     Optional workflow run URL for release notes.
  --output FILE     Dry-run notes output path.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)
      DATE="${2:?Missing value for --date}"
      shift 2
      ;;
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
    --target)
      TARGET="${2:?Missing value for --target}"
      shift 2
      ;;
    --run-url)
      RUN_URL="${2:?Missing value for --run-url}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:?Missing value for --output}"
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

if [[ -z "$DATE" ]]; then
  echo "--date is required" >&2
  usage >&2
  exit 2
fi

if [[ -z "$OWNER" || -z "$REPO" ]]; then
  OWNER="${OWNER:-$(gh repo view --json owner --jq '.owner.login')}"
  REPO="${REPO:-$(gh repo view --json name --jq '.name')}"
fi

release_tag="$(
  python3 - "$DATE" <<'PY'
import re
import sys
raw = sys.argv[1]
match = re.fullmatch(r"(\d{4})[.-]?(\d{2})[.-]?(\d{2})", raw)
if not match:
    raise SystemExit(f"Invalid date: {raw}")
print(".".join(match.groups()))
PY
)"

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$ROOT/release-preview/$release_tag.md"
fi

args=(
  "$ROOT/scripts/generate-release-notes.py"
  --owner "$OWNER"
  --repo "$REPO"
  --date "$release_tag"
  --output "$OUTPUT"
)

if [[ -n "$TARGET" ]]; then
  args+=(--commit "$TARGET")
fi

if [[ -n "$RUN_URL" ]]; then
  args+=(--run-url "$RUN_URL")
fi

python3 "${args[@]}"

if [[ "$PUBLISH" -eq 0 ]]; then
  echo "Dry-run release notes written to: $OUTPUT"
  exit 0
fi

if gh release view "$release_tag" >/dev/null 2>&1; then
  edit_args=(release edit "$release_tag" --title "$release_tag" --notes-file "$OUTPUT")
  if [[ -n "$TARGET" ]]; then
    edit_args+=(--target "$TARGET")
  fi
  gh "${edit_args[@]}"
else
  create_args=(release create "$release_tag" --title "$release_tag" --notes-file "$OUTPUT")
  if [[ -n "$TARGET" ]]; then
    create_args+=(--target "$TARGET")
  fi
  gh "${create_args[@]}"
fi

echo "Published GitHub Release: $release_tag"
