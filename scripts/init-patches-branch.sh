#!/usr/bin/env bash
# Build the `islandzed/applied` branch inside source/ from patches/*.patch.
#
# Run this once after a fresh clone (or after deleting the branch) so the
# subsequent regen / rebase workflow has commits to operate on.
#
# Usage:
#   ./scripts/init-patches-branch.sh
#
# This script is idempotent only in the sense that it refuses to clobber an
# existing branch -- delete it first if you want to rebuild:
#   git -C source branch -D islandzed/applied

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$REPO_ROOT/patches"
ZED_DIR="$REPO_ROOT/source"
BRANCH="islandzed/applied"

# Patch order — must match scripts/apply-patches.sh
PATCHES=(
  rounded-content-mask.patch
  floating-island.patch
  scrollbar-style.patch
  tab-style.patch
  title-bar.patch
  windows-build-docs.patch
  windows-vs-devshell.patch
  project-panel-style.patch
)

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RST=$'\033[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_RST=
fi
ok()   { printf '%s%s%s\n' "$C_GRN" "$*" "$C_RST"; }
warn() { printf '%s%s%s\n' "$C_YEL" "$*" "$C_RST" >&2; }
err()  { printf '%s%s%s\n' "$C_RED" "$*" "$C_RST" >&2; }

if [[ ! -d "$ZED_DIR/.git" && ! -f "$ZED_DIR/.git" ]]; then
  err "source/ submodule is not initialized. Run: git submodule update --init"
  exit 1
fi

pin="$(git -C "$REPO_ROOT" ls-files -s source | awk '{print $2}')"
if [[ -z "$pin" ]]; then
  err "Could not read submodule pin for 'source'."
  exit 1
fi

zed_head="$(git -C "$ZED_DIR" rev-parse HEAD)"
if [[ "$zed_head" != "$pin" ]]; then
  err "source/ HEAD ($zed_head) does not match pin ($pin)."
  err "Run: scripts/apply-patches.sh reset"
  exit 1
fi

if ! git -C "$ZED_DIR" diff --quiet || ! git -C "$ZED_DIR" diff --cached --quiet; then
  err "source/ working tree is dirty. Refusing to init."
  err "Run: scripts/apply-patches.sh reset"
  exit 1
fi

if git -C "$ZED_DIR" rev-parse --verify --quiet "$BRANCH" >/dev/null; then
  err "Branch $BRANCH already exists in source/."
  err "Delete first if you want to rebuild: git -C source branch -D $BRANCH"
  exit 1
fi

git -C "$ZED_DIR" checkout -q -b "$BRANCH" "$pin"

for p in "${PATCHES[@]}"; do
  patch_file="$PATCH_DIR/$p"
  if [[ ! -f "$patch_file" ]]; then
    err "Missing patch file: $patch_file"
    exit 2
  fi
  if ! git -C "$ZED_DIR" apply "$patch_file"; then
    err "[$p] failed to apply onto $BRANCH"
    exit 2
  fi
  git -C "$ZED_DIR" add -A
  # Fixed identity + date so format-patch output is bit-stable across machines
  GIT_AUTHOR_NAME="IslandZed" GIT_AUTHOR_EMAIL="islandzed@local" \
  GIT_COMMITTER_NAME="IslandZed" GIT_COMMITTER_EMAIL="islandzed@local" \
  GIT_AUTHOR_DATE="2026-05-07T00:00:00+0000" \
  GIT_COMMITTER_DATE="2026-05-07T00:00:00+0000" \
    git -C "$ZED_DIR" commit -q -m "${p%.patch}"
  ok "[$p] committed as $(git -C "$ZED_DIR" rev-parse --short HEAD)"
done

ok "Built $BRANCH at $(git -C "$ZED_DIR" rev-parse --short "$BRANCH") (${#PATCHES[@]} commits on top of $pin)"
echo
echo "Next steps:"
echo "  - Edit code on this branch and commit/amend as usual"
echo "  - Run scripts/regen-patches.sh to refresh patches/*.patch from the branch"
echo "  - When the submodule pin bumps, rebase: git -C source rebase <new-pin> $BRANCH"
