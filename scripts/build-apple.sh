#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

require_command cargo
require_command lipo
require_command plutil
require_command rustup
require_command xcodebuild

actual_xcode_version="$(xcodebuild -version | sed -n '1s/^Xcode //p')"
[[ -n "$actual_xcode_version" ]] || die "could not determine the selected Xcode version"
if [[ "$actual_xcode_version" != "$XCODE_VERSION" ]] &&
  [[ "${XRAY_ALLOW_UNPINNED_XCODE:-0}" != "1" ]]; then
  die "selected Xcode is $actual_xcode_version, expected $XCODE_VERSION; set XRAY_ALLOW_UNPINNED_XCODE=1 only for local experiments"
fi

core="$(resolve_core_checkout)"
profile="${PROFILE:-release}"
out_dir="${APPLE_OUT_DIR:-$MOBILE_ROOT/Artifacts}"
xcframework="$out_dir/XrayRust.xcframework"
cargo_target_dir="${APPLE_CARGO_TARGET_DIR:-$MOBILE_ROOT/.build/apple/cargo}"
include_macos="${APPLE_INCLUDE_MACOS:-1}"
include_tvos="${APPLE_INCLUDE_TVOS:-1}"

[[ -n "$out_dir" && "$out_dir" != "/" ]] || die "unsafe Apple output directory"
mkdir -p "$out_dir" "$cargo_target_dir"
out_dir="$(cd "$out_dir" && pwd -P)"
cargo_target_dir="$(cd "$cargo_target_dir" && pwd -P)"

export CARGO_TARGET_DIR="$cargo_target_dir"
export CARGO_INCREMENTAL=0
export IPHONEOS_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET"
export TVOS_DEPLOYMENT_TARGET="$TVOS_DEPLOYMENT_TARGET"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH="$(git -C "$core" show -s --format=%ct "$XRAY_RUST_COMMIT")"
export TZ=UTC
export LC_ALL=C

profile_args=()
profile_dir="$profile"
if [[ "$profile" == "release" ]]; then
  profile_args+=(--release)
elif [[ "$profile" == "dev" || "$profile" == "debug" ]]; then
  profile_dir="debug"
else
  profile_args+=(--profile "$profile")
fi

build_target() {
  local target="$1"
  if [[ "$target" == *"apple-tvos"* ]]; then
    cargo "+$TVOS_RUST_TOOLCHAIN" build \
      -Z build-std=std,panic_unwind \
      --locked \
      --manifest-path "$core/Cargo.toml" \
      --package xray-ffi \
      --target "$target" \
      "${profile_args[@]}"
  else
    cargo "+$RUST_TOOLCHAIN" build \
      --locked \
      --manifest-path "$core/Cargo.toml" \
      --package xray-ffi \
      --target "$target" \
      "${profile_args[@]}"
  fi
}

target_library() {
  echo "$cargo_target_dir/$1/$profile_dir/libxray_ffi.a"
}

build_target aarch64-apple-ios
build_target aarch64-apple-ios-sim
build_target x86_64-apple-ios

slice_dir="$MOBILE_ROOT/.build/apple/slices"
[[ -n "$slice_dir" && "$slice_dir" != "/" ]] || die "unsafe Apple slice directory"
rm -rf "$slice_dir"
mkdir -p "$slice_dir/ios-device" "$slice_dir/ios-simulator"
cp "$(target_library aarch64-apple-ios)" "$slice_dir/ios-device/libxray_ffi.a"
lipo -create \
  "$(target_library aarch64-apple-ios-sim)" \
  "$(target_library x86_64-apple-ios)" \
  -output "$slice_dir/ios-simulator/libxray_ffi.a"

header_dir="$core/crates/xray-ffi/include"
framework_template="$SCRIPT_DIR/apple-framework"

make_static_framework() {
  local binary="$1"
  local destination="$2"
  local supported_platform="$3"
  local minimum_version_key="$4"
  local minimum_version="$5"
  local framework="$destination/XrayRust.framework"
  local framework_contents="$framework"
  local info_plist

  if [[ "$supported_platform" == "MacOSX" ]]; then
    framework_contents="$framework/Versions/A"
    mkdir -p \
      "$framework_contents/Headers" \
      "$framework_contents/Modules" \
      "$framework_contents/Resources"
    ln -s A "$framework/Versions/Current"
    ln -s Versions/Current/Headers "$framework/Headers"
    ln -s Versions/Current/Modules "$framework/Modules"
    ln -s Versions/Current/Resources "$framework/Resources"
    ln -s Versions/Current/XrayRust "$framework/XrayRust"
    info_plist="$framework_contents/Resources/Info.plist"
  else
    mkdir -p "$framework_contents/Headers" "$framework_contents/Modules"
    info_plist="$framework_contents/Info.plist"
  fi

  cp "$binary" "$framework_contents/XrayRust"
  cp "$header_dir/xray_ffi.h" "$framework_contents/Headers/xray_ffi.h"
  cp "$framework_template/module.modulemap" \
    "$framework_contents/Modules/module.modulemap"
  cp "$framework_template/Info.plist" "$info_plist"
  plutil -replace CFBundleShortVersionString \
    -string "$XRAY_MOBILE_VERSION" "$info_plist"
  plutil -replace CFBundleSupportedPlatforms.0 \
    -string "$supported_platform" "$info_plist"
  if [[ "$minimum_version_key" == "MinimumOSVersion" ]]; then
    plutil -replace MinimumOSVersion -string "$minimum_version" "$info_plist"
  else
    plutil -remove MinimumOSVersion "$info_plist"
    plutil -insert "$minimum_version_key" -string "$minimum_version" "$info_plist"
  fi
}

make_static_framework \
  "$slice_dir/ios-device/libxray_ffi.a" \
  "$slice_dir/ios-device" \
  iPhoneOS \
  MinimumOSVersion \
  "$IOS_DEPLOYMENT_TARGET"
make_static_framework \
  "$slice_dir/ios-simulator/libxray_ffi.a" \
  "$slice_dir/ios-simulator" \
  iPhoneSimulator \
  MinimumOSVersion \
  "$IOS_DEPLOYMENT_TARGET"

xcframework_args=(
  -create-xcframework
  -framework "$slice_dir/ios-device/XrayRust.framework"
  -framework "$slice_dir/ios-simulator/XrayRust.framework"
)

if [[ "$include_tvos" == "1" ]]; then
  build_target aarch64-apple-tvos
  build_target aarch64-apple-tvos-sim
  build_target x86_64-apple-tvos
  mkdir -p "$slice_dir/tvos-device" "$slice_dir/tvos-simulator"
  cp \
    "$(target_library aarch64-apple-tvos)" \
    "$slice_dir/tvos-device/libxray_ffi.a"
  lipo -create \
    "$(target_library aarch64-apple-tvos-sim)" \
    "$(target_library x86_64-apple-tvos)" \
    -output "$slice_dir/tvos-simulator/libxray_ffi.a"
  make_static_framework \
    "$slice_dir/tvos-device/libxray_ffi.a" \
    "$slice_dir/tvos-device" \
    AppleTVOS \
    MinimumOSVersion \
    "$TVOS_DEPLOYMENT_TARGET"
  make_static_framework \
    "$slice_dir/tvos-simulator/libxray_ffi.a" \
    "$slice_dir/tvos-simulator" \
    AppleTVSimulator \
    MinimumOSVersion \
    "$TVOS_DEPLOYMENT_TARGET"
  xcframework_args+=(
    -framework "$slice_dir/tvos-device/XrayRust.framework"
    -framework "$slice_dir/tvos-simulator/XrayRust.framework"
  )
fi

if [[ "$include_macos" == "1" ]]; then
  build_target aarch64-apple-darwin
  build_target x86_64-apple-darwin
  mkdir -p "$slice_dir/macos"
  lipo -create \
    "$(target_library aarch64-apple-darwin)" \
    "$(target_library x86_64-apple-darwin)" \
    -output "$slice_dir/macos/libxray_ffi.a"
  make_static_framework \
    "$slice_dir/macos/libxray_ffi.a" \
    "$slice_dir/macos" \
    MacOSX \
    LSMinimumSystemVersion \
    "$MACOS_DEPLOYMENT_TARGET"
  xcframework_args+=(
    -framework "$slice_dir/macos/XrayRust.framework"
  )
fi

rm -rf "$xcframework"
xcodebuild "${xcframework_args[@]}" -output "$xcframework"

lipo "$xcframework/ios-arm64/XrayRust.framework/XrayRust" -verify_arch arm64
lipo "$xcframework/ios-arm64_x86_64-simulator/XrayRust.framework/XrayRust" \
  -verify_arch arm64 x86_64
if [[ "$include_tvos" == "1" ]]; then
  lipo "$xcframework/tvos-arm64/XrayRust.framework/XrayRust" \
    -verify_arch arm64
  lipo "$xcframework/tvos-arm64_x86_64-simulator/XrayRust.framework/XrayRust" \
    -verify_arch arm64 x86_64
fi
if [[ "$include_macos" == "1" ]]; then
  lipo "$xcframework/macos-arm64_x86_64/XrayRust.framework/XrayRust" \
    -verify_arch arm64 x86_64
fi

while IFS= read -r header; do
  [[ "$(sha256_file "$header")" == "$XRAY_RUST_FFI_HEADER_SHA256" ]] ||
    die "packaged FFI header checksum differs: $header"
done < <(find "$xcframework" -path "*/Headers/xray_ffi.h" -type f -print)

echo "$xcframework"
