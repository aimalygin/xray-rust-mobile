#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

require_command swift
require_command xcrun

xcframework="$MOBILE_ROOT/Artifacts/XrayRust.xcframework"
[[ -d "$xcframework" ]] || die "local XCFramework not found; run scripts/build-apple.sh"

check_target() {
  local name="$1"
  local sdk="$2"
  local triple="$3"
  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

  CLANG_MODULE_CACHE_PATH="$MOBILE_ROOT/.build/clang-module-cache-$name" \
    swift build \
      --disable-sandbox \
      --disable-netrc \
      --package-path "$MOBILE_ROOT" \
      --cache-path "$MOBILE_ROOT/.build/swiftpm-cache-$name" \
      --config-path "$MOBILE_ROOT/.build/swiftpm-config-$name" \
      --security-path "$MOBILE_ROOT/.build/swiftpm-security-$name" \
      --scratch-path "$MOBILE_ROOT/.build/swiftpm-$name" \
      --configuration release \
      --sdk "$sdk_path" \
      --triple "$triple"
}

mkdir -p "$MOBILE_ROOT/.build"
check_target ios-device iphoneos "arm64-apple-ios$IOS_DEPLOYMENT_TARGET"
check_target ios-simulator-arm64 iphonesimulator \
  "arm64-apple-ios$IOS_DEPLOYMENT_TARGET-simulator"
check_target ios-simulator-x86_64 iphonesimulator \
  "x86_64-apple-ios$IOS_DEPLOYMENT_TARGET-simulator"

if [[ -d "$xcframework/macos-arm64_x86_64" ]]; then
  CLANG_MODULE_CACHE_PATH="$MOBILE_ROOT/.build/clang-module-cache-tests" \
    swift test \
      --disable-sandbox \
      --disable-netrc \
      --package-path "$MOBILE_ROOT" \
      --cache-path "$MOBILE_ROOT/.build/swiftpm-cache-tests" \
      --config-path "$MOBILE_ROOT/.build/swiftpm-config-tests" \
      --security-path "$MOBILE_ROOT/.build/swiftpm-security-tests" \
      --scratch-path "$MOBILE_ROOT/.build/swiftpm-tests"
fi
