#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

require_command cargo
require_command lipo
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
include_macos="${APPLE_INCLUDE_MACOS:-0}"

[[ -n "$out_dir" && "$out_dir" != "/" ]] || die "unsafe Apple output directory"
mkdir -p "$out_dir" "$cargo_target_dir"
out_dir="$(cd "$out_dir" && pwd -P)"
cargo_target_dir="$(cd "$cargo_target_dir" && pwd -P)"

export CARGO_TARGET_DIR="$cargo_target_dir"
export CARGO_INCREMENTAL=0
export IPHONEOS_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET"
export MACOSX_DEPLOYMENT_TARGET="11.0"
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
  cargo "+$RUST_TOOLCHAIN" build \
    --locked \
    --manifest-path "$core/Cargo.toml" \
    --package xray-ffi \
    --target "$target" \
    "${profile_args[@]}"
}

target_library() {
  echo "$cargo_target_dir/$1/$profile_dir/libxray_ffi.a"
}

build_target aarch64-apple-ios
build_target aarch64-apple-ios-sim
build_target x86_64-apple-ios

slice_dir="$MOBILE_ROOT/.build/apple/slices"
mkdir -p "$slice_dir/ios-device" "$slice_dir/ios-simulator"
cp "$(target_library aarch64-apple-ios)" "$slice_dir/ios-device/libxray_ffi.a"
lipo -create \
  "$(target_library aarch64-apple-ios-sim)" \
  "$(target_library x86_64-apple-ios)" \
  -output "$slice_dir/ios-simulator/libxray_ffi.a"

header_dir="$core/crates/xray-ffi/include"
xcframework_args=(
  -create-xcframework
  -library "$slice_dir/ios-device/libxray_ffi.a"
  -headers "$header_dir"
  -library "$slice_dir/ios-simulator/libxray_ffi.a"
  -headers "$header_dir"
)

if [[ "$include_macos" == "1" ]]; then
  build_target aarch64-apple-darwin
  build_target x86_64-apple-darwin
  mkdir -p "$slice_dir/macos"
  lipo -create \
    "$(target_library aarch64-apple-darwin)" \
    "$(target_library x86_64-apple-darwin)" \
    -output "$slice_dir/macos/libxray_ffi.a"
  xcframework_args+=(
    -library "$slice_dir/macos/libxray_ffi.a"
    -headers "$header_dir"
  )
fi

rm -rf "$xcframework"
xcodebuild "${xcframework_args[@]}" -output "$xcframework"

lipo "$xcframework/ios-arm64/libxray_ffi.a" -verify_arch arm64
lipo "$xcframework/ios-arm64_x86_64-simulator/libxray_ffi.a" \
  -verify_arch arm64 x86_64
if [[ "$include_macos" == "1" ]]; then
  lipo "$xcframework/macos-arm64_x86_64/libxray_ffi.a" \
    -verify_arch arm64 x86_64
fi

while IFS= read -r header; do
  [[ "$(sha256_file "$header")" == "$XRAY_RUST_FFI_HEADER_SHA256" ]] ||
    die "packaged FFI header checksum differs: $header"
done < <(find "$xcframework" -path "*/Headers/xray_ffi.h" -type f -print)

echo "$xcframework"
