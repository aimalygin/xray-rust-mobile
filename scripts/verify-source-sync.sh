#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

core="$(resolve_core_checkout)"

compare_tree() {
  local upstream="$1"
  local mobile="$2"
  if ! diff -ru "$upstream" "$mobile"; then
    die "adapter sources differ: $mobile"
  fi
}

compare_file() {
  local upstream="$1"
  local mobile="$2"
  if ! diff -u "$upstream" "$mobile"; then
    die "adapter source differs: $mobile"
  fi
}

compare_tree \
  "$core/platform/apple/Sources/XrayMobileAdapter" \
  "$MOBILE_ROOT/Sources/XrayMobileAdapter"
compare_tree \
  "$core/platform/apple/Sources/XrayAppleShared" \
  "$MOBILE_ROOT/Sources/XrayAppleShared"
compare_tree \
  "$core/platform/apple/Sources/XrayAppleTunnel" \
  "$MOBILE_ROOT/Sources/XrayAppleTunnel"
compare_tree \
  "$core/platform/apple/Tests/XrayMobileAdapterTests" \
  "$MOBILE_ROOT/Tests/XrayMobileAdapterTests"
compare_tree \
  "$core/platform/apple/Tests/XrayAppleSharedTests" \
  "$MOBILE_ROOT/Tests/XrayAppleSharedTests"
compare_tree \
  "$core/platform/apple/Tests/XrayAppleTunnelTests" \
  "$MOBILE_ROOT/Tests/XrayAppleTunnelTests"
compare_tree \
  "$core/platform/android/xraymobile/src/main/java" \
  "$MOBILE_ROOT/android/xraymobile/src/main/java"
compare_tree \
  "$core/platform/android/xraymobile/src/test" \
  "$MOBILE_ROOT/android/xraymobile/src/test"
compare_file \
  "$core/platform/android/xraymobile/src/main/cpp/xray_mobile_jni.cpp" \
  "$MOBILE_ROOT/android/xraymobile/src/main/cpp/xray_mobile_jni.cpp"

echo "verified mobile adapters against $XRAY_RUST_TAG"

