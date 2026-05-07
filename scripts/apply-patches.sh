#!/usr/bin/env bash
# Apply the patches in patches/ to the source/ directory.
#
# Usage:
#   ./apply-patches.sh         apply all patches in declared order
#   ./apply-patches.sh reset   hard-reset source/ to the submodule pin
#                              and discard all local changes.
#
# The patch files in patches/ are *generated artifacts* of the
# `islandzed/applied` branch maintained inside source/. To edit a patch:
#
#   1. cd source && git checkout islandzed/applied
#   2. Edit code, commit / amend / rebase as usual
#   3. ../scripts/regen-patches.sh   (refreshes patches/*.patch from the branch)
#
# To bump the submodule pin:
#
#   1. Update the submodule pin in the outer repo as usual
#   2. cd source && git rebase <new-pin> islandzed/applied
#   3. Resolve any conflicts (per-commit, with normal git merge tooling)
#   4. ../scripts/regen-patches.sh
#
# After a fresh clone (or if the branch was deleted), bootstrap with:
#   ./scripts/init-patches-branch.sh

set -euo pipefail

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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$REPO_ROOT/patches"
ZED_DIR="$REPO_ROOT/source"

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_DIM=; C_RST=
fi

log()   { printf '%s\n' "$*"; }
info()  { printf '%s%s%s\n' "$C_DIM"  "$*" "$C_RST"; }
ok()    { printf '%s%s%s\n' "$C_GRN"  "$*" "$C_RST"; }
warn()  { printf '%s%s%s\n' "$C_YEL"  "$*" "$C_RST" >&2; }
err()   { printf '%s%s%s\n' "$C_RED"  "$*" "$C_RST" >&2; }

command="${1:-apply}"

if [[ "$command" == "-h" || "$command" == "--help" ]]; then
    sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0
fi

if [[ ! -d "$ZED_DIR/.git" && ! -f "$ZED_DIR/.git" ]]; then
  err "source/ submodule is not initialized."
  err "Run: git submodule update --init"
  exit 1
fi

# 获取子模块锁定版本 (优先从暂存区获取，兼容未 commit 的状态)
pin="$(git -C "$REPO_ROOT" ls-files -s source | awk '{print $2}')"
if [[ -z "$pin" ]]; then
  pin="$(git -C "$REPO_ROOT" ls-tree HEAD source 2>/dev/null | awk '{print $3}')" || true
fi

if [[ -z "$pin" ]]; then
  err "Could not read submodule pin for 'source'."
  exit 1
fi

reset_source() {
  info "Resetting source/ to pin $pin..."
  git -C "$ZED_DIR" checkout --quiet "$pin"
  git -C "$ZED_DIR" checkout -- .
  git -C "$ZED_DIR" clean -fd
  ok "source/ reset successfully."
}

if [[ "$command" == "reset" ]]; then
  reset_source
  exit 0
fi

if [[ "$command" != "apply" ]]; then
  err "Unknown command: $command"
  exit 1
fi

# --- apply 模式的前置检查 ---
zed_head="$(git -C "$ZED_DIR" rev-parse HEAD)"
if [[ "$zed_head" != "$pin" ]]; then
  err "source/ HEAD ($zed_head) does not match pin ($pin)."
  err "Run: $0 reset"
  exit 1
fi

if ! git -C "$ZED_DIR" diff --quiet || ! git -C "$ZED_DIR" diff --cached --quiet; then
  err "source/ working tree is dirty. Refusing to apply patches."
  err "Run: $0 reset"
  exit 1
fi

# --- patch 循环 ---
for name in "${PATCHES[@]}"; do
  patch="$PATCH_DIR/$name"
  if [[ ! -f "$patch" ]]; then
    err "missing patch: $patch"
    exit 2
  fi

  # 总是先做 --check
  if ! git -C "$ZED_DIR" apply --check "$patch" 2>/tmp/apply-patches.err; then
    err "[$name] --check failed:"
    sed 's/^/    /' /tmp/apply-patches.err >&2
    exit 2
  fi

  if ! git -C "$ZED_DIR" apply "$patch"; then
    err "[$name] apply failed after --check passed"
    exit 2
  fi
  ok "[$name] applied"
done

ok "All ${#PATCHES[@]} patches applied successfully."
