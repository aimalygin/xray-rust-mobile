#!/usr/bin/env bash

set -euo pipefail

MOBILE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# These files contain repository-controlled shell assignments only.
# shellcheck disable=SC1091
source "$MOBILE_ROOT/release/version.env"
# shellcheck disable=SC1091
source "$MOBILE_ROOT/release/core.env"
# shellcheck disable=SC1091
source "$MOBILE_ROOT/release/toolchains.env"
# shellcheck disable=SC1091
source "$MOBILE_ROOT/release/artifacts.env"

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

resolve_android_sdk() {
  local candidate
  for candidate in \
    "${ANDROID_HOME:-}" \
    "${ANDROID_SDK_ROOT:-}" \
    "$HOME/Library/Android/sdk" \
    "$HOME/Android/Sdk"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      (cd "$candidate" && pwd -P)
      return
    fi
  done
  return 1
}

verify_core_checkout() {
  local checkout="$1"
  git -C "$checkout" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    die "not a Git checkout: $checkout"

  local actual_commit
  actual_commit="$(git -C "$checkout" rev-parse HEAD)"
  [[ "$actual_commit" == "$XRAY_RUST_COMMIT" ]] ||
    die "core checkout is $actual_commit, expected $XRAY_RUST_COMMIT"

  local actual_tree
  actual_tree="$(git -C "$checkout" rev-parse 'HEAD^{tree}')"
  [[ "$actual_tree" == "$XRAY_RUST_TREE" ]] ||
    die "core tree is $actual_tree, expected $XRAY_RUST_TREE"

  local actual_tag_object
  actual_tag_object="$(git -C "$checkout" rev-parse "$XRAY_RUST_TAG^{tag}" 2>/dev/null || true)"
  [[ "$actual_tag_object" == "$XRAY_RUST_TAG_OBJECT" ]] ||
    die "core tag object is missing or differs for $XRAY_RUST_TAG"

  local peeled_tag
  peeled_tag="$(git -C "$checkout" rev-parse "$XRAY_RUST_TAG^{commit}")"
  [[ "$peeled_tag" == "$XRAY_RUST_COMMIT" ]] ||
    die "core tag $XRAY_RUST_TAG resolves to $peeled_tag, expected $XRAY_RUST_COMMIT"

  [[ "$(sha256_file "$checkout/Cargo.lock")" == "$XRAY_RUST_CARGO_LOCK_SHA256" ]] ||
    die "core Cargo.lock checksum differs from release/core.env"
  [[ "$(sha256_file "$checkout/crates/xray-ffi/include/xray_ffi.h")" == "$XRAY_RUST_FFI_HEADER_SHA256" ]] ||
    die "core FFI header checksum differs from release/core.env"
  [[ "$(sha256_file "$checkout/crates/xray-ffi/include/module.modulemap")" == "$XRAY_RUST_MODULEMAP_SHA256" ]] ||
    die "core module map checksum differs from release/core.env"

  if [[ "${XRAY_ALLOW_DIRTY_UPSTREAM:-0}" != "1" ]] &&
    [[ -n "$(git -C "$checkout" status --porcelain --untracked-files=no)" ]]; then
    die "core checkout has tracked changes; set XRAY_ALLOW_DIRTY_UPSTREAM=1 only for local experiments"
  fi
}

resolve_core_checkout() {
  local candidate

  if [[ -n "${XRAY_RUST_SOURCE:-}" ]]; then
    candidate="$XRAY_RUST_SOURCE"
    verify_core_checkout "$candidate"
    (cd "$candidate" && pwd -P)
    return
  fi

  candidate="$(cd "$MOBILE_ROOT/.." && pwd -P)/xray-rust"
  if git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
    [[ "$(git -C "$candidate" rev-parse HEAD 2>/dev/null || true)" == "$XRAY_RUST_COMMIT" ]]; then
    verify_core_checkout "$candidate"
    echo "$candidate"
    return
  fi

  candidate="$MOBILE_ROOT/.build/core"
  mkdir -p "$MOBILE_ROOT/.build"
  if ! git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git clone --filter=blob:none --no-checkout "$XRAY_RUST_REPOSITORY" "$candidate" >&2
  fi

  git -C "$candidate" fetch --force origin \
    "$XRAY_RUST_COMMIT" \
    "refs/tags/$XRAY_RUST_TAG:refs/tags/$XRAY_RUST_TAG" >&2
  git -C "$candidate" checkout --detach "$XRAY_RUST_COMMIT" >&2
  verify_core_checkout "$candidate"
  echo "$candidate"
}
