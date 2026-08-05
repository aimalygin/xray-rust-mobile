#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

require_command cargo
require_command lipo
require_command rustc
require_command rustup
require_command xcodebuild

llvm_objcopy="$(resolve_llvm_objcopy)"

# rustup ships std and compiler_builtins as rlibs that already carry an
# embedded __LLVM,__bitcode section, and rustc copies those objects verbatim
# into a staticlib. Apple dropped bitcode in Xcode 14, so the section is dead
# weight: it accounts for well over half of every slice. It cannot be disabled
# at build time because -C embed-bitcode=no is rejected together with -C lto.
strip_embedded_bitcode() {
  local archive="$1"
  "$llvm_objcopy" \
    --remove-section=__LLVM,__bitcode \
    --remove-section=__LLVM,__cmdline \
    "$archive"
}

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
strip_embedded_bitcode "$slice_dir/ios-device/libxray_ffi.a"
lipo -create \
  "$(target_library aarch64-apple-ios-sim)" \
  "$(target_library x86_64-apple-ios)" \
  -output "$slice_dir/ios-simulator/libxray_ffi.a"
strip_embedded_bitcode "$slice_dir/ios-simulator/libxray_ffi.a"

header_dir="$core/crates/xray-ffi/include"

# The XCFramework ships bare `.a` slices and no headers on purpose. Xcode
# copies the headers of a static-library XCFramework into a flat
# `$BUILT_PRODUCTS_DIR/include` directory, and the `module.modulemap` name
# there is fixed, so two such XCFrameworks in one target collide with
# "Multiple commands produce .../include/module.modulemap". The public API is
# published from the XrayRustFFI Clang target instead, which vendors these two
# files from the pinned core.
for vendored in xray_ffi.h module.modulemap; do
  cmp -s \
    "$header_dir/$vendored" \
    "$MOBILE_ROOT/Sources/XrayRustFFI/include/$vendored" ||
    die "Sources/XrayRustFFI/include/$vendored differs from $XRAY_RUST_TAG"
done

xcframework_args=(
  -create-xcframework
  -library "$slice_dir/ios-device/libxray_ffi.a"
  -library "$slice_dir/ios-simulator/libxray_ffi.a"
)

if [[ "$include_tvos" == "1" ]]; then
  build_target aarch64-apple-tvos
  build_target aarch64-apple-tvos-sim
  build_target x86_64-apple-tvos
  mkdir -p "$slice_dir/tvos-device" "$slice_dir/tvos-simulator"
  cp \
    "$(target_library aarch64-apple-tvos)" \
    "$slice_dir/tvos-device/libxray_ffi.a"
  strip_embedded_bitcode "$slice_dir/tvos-device/libxray_ffi.a"
  lipo -create \
    "$(target_library aarch64-apple-tvos-sim)" \
    "$(target_library x86_64-apple-tvos)" \
    -output "$slice_dir/tvos-simulator/libxray_ffi.a"
  strip_embedded_bitcode "$slice_dir/tvos-simulator/libxray_ffi.a"
  xcframework_args+=(
    -library "$slice_dir/tvos-device/libxray_ffi.a"
    -library "$slice_dir/tvos-simulator/libxray_ffi.a"
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
  strip_embedded_bitcode "$slice_dir/macos/libxray_ffi.a"
  xcframework_args+=(
    -library "$slice_dir/macos/libxray_ffi.a"
  )
fi

rm -rf "$xcframework"
xcodebuild "${xcframework_args[@]}" -output "$xcframework"

lipo "$xcframework/ios-arm64/libxray_ffi.a" -verify_arch arm64
lipo "$xcframework/ios-arm64_x86_64-simulator/libxray_ffi.a" \
  -verify_arch arm64 x86_64
if [[ "$include_tvos" == "1" ]]; then
  lipo "$xcframework/tvos-arm64/libxray_ffi.a" \
    -verify_arch arm64
  lipo "$xcframework/tvos-arm64_x86_64-simulator/libxray_ffi.a" \
    -verify_arch arm64 x86_64
fi
if [[ "$include_macos" == "1" ]]; then
  lipo "$xcframework/macos-arm64_x86_64/libxray_ffi.a" \
    -verify_arch arm64 x86_64
fi

packaged_headers="$(
  find "$xcframework" \( -name "*.h" -o -name "module.modulemap" \) -print |
    wc -l |
    tr -d ' '
)"
[[ "$packaged_headers" == "0" ]] ||
  die "XCFramework must not package headers; they belong to XrayRustFFI"

echo "$xcframework"
