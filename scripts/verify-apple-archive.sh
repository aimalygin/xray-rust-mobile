#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

expected_checksum="$APPLE_XCFRAMEWORK_SHA256"
if [[ "${1:-}" == "--structural" ]]; then
  expected_checksum=""
  shift
fi

archive="${1:-}"
[[ -f "$archive" && "$#" -eq 1 ]] ||
  die "usage: $0 [--structural] <XrayRust.xcframework.zip>"
require_command lipo
require_command swift
require_command unzip

checksum="$(swift package compute-checksum "$archive")"
if [[ -n "$expected_checksum" ]]; then
  [[ "$checksum" == "$expected_checksum" ]] ||
    die "Apple archive checksum is $checksum, expected $expected_checksum"
fi

mkdir -p "$MOBILE_ROOT/.build"
temporary="$(mktemp -d "$MOBILE_ROOT/.build/apple-archive.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
unzip -q "$archive" -d "$temporary"
xcframework="$temporary/XrayRust.xcframework"

[[ -f "$xcframework/ios-arm64/libxray_ffi.a" ]] ||
  die "Apple archive has no iOS device slice"
[[ -f "$xcframework/ios-arm64_x86_64-simulator/libxray_ffi.a" ]] ||
  die "Apple archive has no iOS simulator slice"
[[ -f "$xcframework/macos-arm64_x86_64/libxray_ffi.a" ]] ||
  die "Apple archive has no universal macOS slice"
lipo "$xcframework/ios-arm64/libxray_ffi.a" -verify_arch arm64
lipo "$xcframework/ios-arm64_x86_64-simulator/libxray_ffi.a" \
  -verify_arch arm64 x86_64
lipo "$xcframework/macos-arm64_x86_64/libxray_ffi.a" \
  -verify_arch arm64 x86_64

slice_count="$(
  find "$xcframework" -mindepth 1 -maxdepth 1 -type d -print | wc -l | tr -d ' '
)"
[[ "$slice_count" == "3" ]] ||
  die "release XCFramework must contain two iOS slices and one macOS slice"

while IFS= read -r header; do
  [[ "$(sha256_file "$header")" == "$XRAY_RUST_FFI_HEADER_SHA256" ]] ||
    die "Apple archive contains an unexpected FFI header"
done < <(find "$xcframework" -path "*/Headers/xray_ffi.h" -type f -print)

header_count="$(
  find "$xcframework" -path "*/Headers/xray_ffi.h" -type f -print |
    wc -l |
    tr -d ' '
)"
[[ "$header_count" == "3" ]] ||
  die "release XCFramework must contain one FFI header per slice"

while IFS= read -r module_map; do
  [[ "$(sha256_file "$module_map")" == "$XRAY_RUST_MODULEMAP_SHA256" ]] ||
    die "Apple archive contains an unexpected module map"
done < <(find "$xcframework" -path "*/Headers/module.modulemap" -type f -print)

module_map_count="$(
  find "$xcframework" -path "*/Headers/module.modulemap" -type f -print |
    wc -l |
    tr -d ' '
)"
[[ "$module_map_count" == "3" ]] ||
  die "release XCFramework must contain one module map per slice"

echo "verified Apple release archive: $archive"
