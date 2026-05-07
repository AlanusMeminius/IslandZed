#!/usr/bin/env bash
# Build the IslandZed macOS bundle locally, mirroring the release.yml CI flow.
#
# Usage:
#   ./build-mac.sh                       build for host architecture
#   ./build-mac.sh aarch64               build for aarch64-apple-darwin
#   ./build-mac.sh x86_64                build for x86_64-apple-darwin
#   ./build-mac.sh aarch64-apple-darwin  build for the given full target triple
#
# Always hard-resets source/ to the submodule pin and re-applies patches before
# building, so any uncommitted work inside source/ will be discarded.
#
# Signing/notarization is delegated to source/script/bundle-mac and triggers
# only when MACOS_CERTIFICATE / MACOS_CERTIFICATE_PASSWORD / APPLE_NOTARIZATION_*
# are all present in the environment. Otherwise an ad-hoc signed DMG is produced.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZED_DIR="$REPO_ROOT/source"
APPLY_PATCHES="$REPO_ROOT/scripts/apply-patches.sh"

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_DIM=; C_RST=
fi

info()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RST"; }
ok()    { printf '%s%s%s\n' "$C_GRN" "$*" "$C_RST"; }
warn()  { printf '%s%s%s\n' "$C_YEL" "$*" "$C_RST" >&2; }
err()   { printf '%s%s%s\n' "$C_RED" "$*" "$C_RST" >&2; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "build-mac.sh must run on macOS (uname -s reported '$(uname -s)')."
  exit 1
fi

if [[ ! -d "$ZED_DIR/.git" && ! -f "$ZED_DIR/.git" ]]; then
  err "source/ submodule is not initialized."
  err "Run: git submodule update --init"
  exit 1
fi

if ! command -v xcode-select >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
  err "Xcode Command Line Tools are required."
  err "Run: xcode-select --install"
  exit 1
fi

case "${1:-}" in
  "")
    case "$(uname -m)" in
      arm64)  target_triple="aarch64-apple-darwin" ;;
      x86_64) target_triple="x86_64-apple-darwin" ;;
      *)
        err "Unsupported host architecture: $(uname -m)"
        exit 1
        ;;
    esac
    ;;
  aarch64) target_triple="aarch64-apple-darwin" ;;
  x86_64)  target_triple="x86_64-apple-darwin" ;;
  aarch64-apple-darwin|x86_64-apple-darwin) target_triple="$1" ;;
  *)
    err "Unsupported target: $1"
    err "Expected one of: aarch64, x86_64, aarch64-apple-darwin, x86_64-apple-darwin"
    exit 1
    ;;
esac

case "$target_triple" in
  aarch64-apple-darwin) arch_suffix="aarch64" ;;
  x86_64-apple-darwin)  arch_suffix="x86_64" ;;
esac

warn "About to hard-reset source/ to the submodule pin. Uncommitted work in source/ will be discarded."
info "Target triple: $target_triple"

bash "$APPLY_PATCHES" reset
bash "$APPLY_PATCHES"

info "Invoking source/script/bundle-mac $target_triple"
(
  cd "$ZED_DIR"
  ./script/bundle-mac "$target_triple"
)

dmg_path="$ZED_DIR/target/$target_triple/release/Zed-$arch_suffix.dmg"
remote_server_path="$ZED_DIR/target/zed-remote-server-macos-$arch_suffix.gz"

ok "Build complete."
ok "  DMG:           $dmg_path"
ok "  Remote server: $remote_server_path"
