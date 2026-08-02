#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ "${1:-}" == "--force" && "$#" -eq 1 ]] ||
  die "usage: $0 --force (overwrites the adapter snapshots and removes extra files)"

require_command rsync
core="$(resolve_core_checkout)"

sync_tree() {
  local upstream="$1"
  local mobile="$2"
  mkdir -p "$mobile"
  rsync -a --delete "$upstream/" "$mobile/"
}

sync_tree \
  "$core/platform/apple/Sources/XrayMobileAdapter" \
  "$MOBILE_ROOT/Sources/XrayMobileAdapter"
sync_tree \
  "$core/platform/apple/Sources/XrayAppleShared" \
  "$MOBILE_ROOT/Sources/XrayAppleShared"
sync_tree \
  "$core/platform/apple/Sources/XrayAppleTunnel" \
  "$MOBILE_ROOT/Sources/XrayAppleTunnel"
sync_tree \
  "$core/platform/apple/Tests/XrayMobileAdapterTests" \
  "$MOBILE_ROOT/Tests/XrayMobileAdapterTests"
sync_tree \
  "$core/platform/apple/Tests/XrayAppleSharedTests" \
  "$MOBILE_ROOT/Tests/XrayAppleSharedTests"
sync_tree \
  "$core/platform/apple/Tests/XrayAppleTunnelTests" \
  "$MOBILE_ROOT/Tests/XrayAppleTunnelTests"
sync_tree \
  "$core/platform/android/xraymobile/src/main/java" \
  "$MOBILE_ROOT/android/xraymobile/src/main/java"
sync_tree \
  "$core/platform/android/xraymobile/src/test" \
  "$MOBILE_ROOT/android/xraymobile/src/test"
cp \
  "$core/platform/android/xraymobile/src/main/cpp/xray_mobile_jni.cpp" \
  "$MOBILE_ROOT/android/xraymobile/src/main/cpp/xray_mobile_jni.cpp"

"$SCRIPT_DIR/verify-source-sync.sh"
echo "synced adapters from $XRAY_RUST_TAG"
