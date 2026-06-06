#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WORKDIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

sync_repo() {
  local repo="$1"
  local name="$2"
  local clone_dir="$WORKDIR/$name"

  gh repo clone "$repo" "$clone_dir" -- --depth 1

  rsync -a --delete --exclude='.git' "$clone_dir/" "$ROOT/vendor/$name/"
  rsync -a --delete --exclude='.git' "$clone_dir/" "$ROOT/files/system/usr/share/bc250-40cu/vendor/$name/"

  git -C "$clone_dir" rev-parse HEAD > "$ROOT/vendor/$name.UPSTREAM_REF"
  git -C "$clone_dir" rev-parse HEAD > "$ROOT/files/system/usr/share/bc250-40cu/vendor/$name.UPSTREAM_REF"
}

mkdir -p "$ROOT/vendor" "$ROOT/files/system/usr/share/bc250-40cu/vendor"

sync_repo duggasco/bc250-40cu-unlock bc250-40cu-unlock
sync_repo WinnieLV/bc250-cu-live-manager bc250-cu-live-manager

echo "Updated 40CU vendor sources."
