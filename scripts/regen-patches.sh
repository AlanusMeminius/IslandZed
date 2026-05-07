#!/usr/bin/env bash
# Regenerate patches/*.patch from the `islandzed/applied` branch in source/.
#
# Workflow:
#   1. Edit code on the branch (`cd source && git checkout islandzed/applied`)
#   2. Commit / amend / rebase as needed
#   3. Run this script to refresh patches/*.patch
#
# After a submodule pin bump, rebase the branch onto the new pin first:
#   cd source && git rebase <new-pin> islandzed/applied
# Then run this script.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$REPO_ROOT/patches"
ZED_DIR="$REPO_ROOT/source"
BRANCH="islandzed/applied"

# Patch order — must match scripts/apply-patches.sh and scripts/init-patches-branch.sh
EXPECTED_PATCHES=(
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

pin="$(git -C "$REPO_ROOT" ls-files -s source | awk '{print $2}')"
if [[ -z "$pin" ]]; then
  err "Could not read submodule pin for 'source'."
  exit 1
fi

if ! git -C "$ZED_DIR" rev-parse --verify --quiet "$BRANCH" >/dev/null; then
  err "Branch $BRANCH not found in source/."
  err "Run: scripts/init-patches-branch.sh"
  exit 1
fi

if ! git -C "$ZED_DIR" merge-base --is-ancestor "$pin" "$BRANCH"; then
  err "$BRANCH is not descended from pin $pin."
  err "Rebase first: git -C source rebase $pin $BRANCH"
  exit 1
fi

# Sanity: count of commits on the branch above pin must equal expected patch count
commit_count=$(git -C "$ZED_DIR" rev-list --count "$pin..$BRANCH")
if [[ "$commit_count" -ne "${#EXPECTED_PATCHES[@]}" ]]; then
  err "Branch has $commit_count commits above pin, expected ${#EXPECTED_PATCHES[@]}."
  err "If you intentionally added/removed a patch, update EXPECTED_PATCHES in:"
  err "  - scripts/regen-patches.sh"
  err "  - scripts/init-patches-branch.sh"
  err "  - scripts/apply-patches.sh"
  exit 2
fi

# Wipe old patches we own, then regenerate
for p in "${EXPECTED_PATCHES[@]}"; do
  rm -f "$PATCH_DIR/$p"
done

# format-patch numbers files like 0001-foo.patch, 0002-bar.patch in commit order.
# We strip the prefix so filenames stay stable across reorderings (the explicit
# array in apply-patches.sh is the source of truth for apply order).
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

git -C "$ZED_DIR" format-patch \
  --quiet \
  --no-stat \
  --no-signature \
  --zero-commit \
  -o "$tmpdir" \
  "$pin..$BRANCH" >/dev/null

# Move + rename, verifying each generated file maps to an expected name
shopt -s nullglob
generated=("$tmpdir"/*.patch)
shopt -u nullglob

if [[ ${#generated[@]} -ne ${#EXPECTED_PATCHES[@]} ]]; then
  err "format-patch produced ${#generated[@]} files, expected ${#EXPECTED_PATCHES[@]}."
  exit 2
fi

# format-patch output is in commit order (oldest first). Match against EXPECTED_PATCHES same order.
i=0
for f in $(printf '%s\n' "${generated[@]}" | sort); do
  expected="${EXPECTED_PATCHES[$i]}"
  expected_subject="${expected%.patch}"
  base="$(basename "$f")"
  # Strip leading NNNN-
  stripped="${base#*-}"
  if [[ "$stripped" != "$expected" ]]; then
    err "Order mismatch at index $i: generated '$base' (subject '${stripped%.patch}'), expected '$expected'."
    err "Reorder commits on $BRANCH or update EXPECTED_PATCHES."
    exit 2
  fi
  mv "$f" "$PATCH_DIR/$expected"
  ok "  -> patches/$expected"
  ((i++))
done

ok "Regenerated ${#EXPECTED_PATCHES[@]} patches from $BRANCH ($pin..$(git -C "$ZED_DIR" rev-parse --short "$BRANCH"))"
