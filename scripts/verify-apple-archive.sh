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
require_command file
require_command plutil
require_command swift
require_command unzip
[[ -x /usr/libexec/PlistBuddy ]] || die "missing required command: PlistBuddy"

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

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

verify_framework() {
  local identifier="$1"
  local supported_platform="$2"
  local minimum_version_key="$3"
  local minimum_version="$4"
  shift 4

  local framework="$xcframework/$identifier/XrayRust.framework"
  local binary="$framework/XrayRust"
  local info_plist="$framework/Info.plist"

  if [[ "$supported_platform" == "MacOSX" ]]; then
    info_plist="$framework/Versions/A/Resources/Info.plist"
    [[ -L "$framework/Versions/Current" ]] &&
      [[ "$(readlink "$framework/Versions/Current")" == "A" ]] ||
      die "Apple archive has no current macOS framework version for $identifier"
    for entry in Headers Modules Resources XrayRust; do
      [[ -L "$framework/$entry" ]] ||
        die "Apple archive has a non-versioned macOS framework $entry for $identifier"
      [[ "$(readlink "$framework/$entry")" == "Versions/Current/$entry" ]] ||
        die "Apple archive has an invalid macOS framework $entry link for $identifier"
    done
    [[ ! -e "$framework/Info.plist" ]] ||
      die "Apple archive has a shallow macOS framework Info.plist for $identifier"
  fi

  [[ -f "$binary" ]] || die "Apple archive has no binary for $identifier"
  [[ "$(file "$binary")" == *"current ar archive"* ]] ||
    die "Apple archive binary is not static for $identifier"
  lipo "$binary" -verify_arch "$@"

  [[ -f "$framework/Headers/xray_ffi.h" ]] ||
    die "Apple archive has no FFI header for $identifier"
  [[ "$(sha256_file "$framework/Headers/xray_ffi.h")" == \
    "$XRAY_RUST_FFI_HEADER_SHA256" ]] ||
    die "Apple archive contains an unexpected FFI header for $identifier"
  [[ -f "$framework/Modules/module.modulemap" ]] ||
    die "Apple archive has no framework module map for $identifier"
  cmp -s \
    "$MOBILE_ROOT/scripts/apple-framework/module.modulemap" \
    "$framework/Modules/module.modulemap" ||
    die "Apple archive contains an unexpected framework module map for $identifier"

  plutil -lint "$info_plist" >/dev/null ||
    die "Apple archive has an invalid framework Info.plist for $identifier"
  [[ "$(plist_value "$info_plist" CFBundlePackageType)" == "FMWK" ]] ||
    die "Apple archive has an invalid framework package type for $identifier"
  [[ "$(plist_value "$info_plist" CFBundleExecutable)" == "XrayRust" ]] ||
    die "Apple archive has an invalid framework executable for $identifier"
  [[ "$(plist_value "$info_plist" CFBundleName)" == "XrayRust" ]] ||
    die "Apple archive has an invalid framework name for $identifier"
  [[ "$(plist_value "$info_plist" CFBundleIdentifier)" == \
    "org.xrayrust.XrayRust" ]] ||
    die "Apple archive has an invalid bundle identifier for $identifier"
  [[ "$(plist_value "$info_plist" CFBundleShortVersionString)" == \
    "$XRAY_MOBILE_VERSION" ]] ||
    die "Apple archive has an invalid framework version for $identifier"
  [[ "$(plist_value "$info_plist" CFBundleSupportedPlatforms:0)" == \
    "$supported_platform" ]] ||
    die "Apple archive has an invalid supported platform for $identifier"
  [[ "$(plist_value "$info_plist" "$minimum_version_key")" == \
    "$minimum_version" ]] ||
    die "Apple archive has an invalid minimum OS version for $identifier"
}

verify_framework ios-arm64 iPhoneOS MinimumOSVersion \
  "$IOS_DEPLOYMENT_TARGET" arm64
verify_framework ios-arm64_x86_64-simulator iPhoneSimulator MinimumOSVersion \
  "$IOS_DEPLOYMENT_TARGET" arm64 x86_64
verify_framework tvos-arm64 AppleTVOS MinimumOSVersion \
  "$TVOS_DEPLOYMENT_TARGET" arm64
verify_framework tvos-arm64_x86_64-simulator AppleTVSimulator MinimumOSVersion \
  "$TVOS_DEPLOYMENT_TARGET" arm64 x86_64
verify_framework macos-arm64_x86_64 MacOSX LSMinimumSystemVersion \
  "$MACOS_DEPLOYMENT_TARGET" arm64 x86_64

slice_count="$(
  find "$xcframework" -mindepth 1 -maxdepth 1 -type d -print | wc -l | tr -d ' '
)"
[[ "$slice_count" == "5" ]] ||
  die "release XCFramework must contain two iOS, two tvOS, and one macOS slice"

root_info_plist="$xcframework/Info.plist"
plutil -lint "$root_info_plist" >/dev/null ||
  die "Apple archive has an invalid XCFramework Info.plist"
[[ "$(plist_value "$root_info_plist" CFBundlePackageType)" == "XFWK" ]] ||
  die "Apple archive has an invalid XCFramework package type"
[[ "$(plist_value "$root_info_plist" XCFrameworkFormatVersion)" == "1.0" ]] ||
  die "Apple archive has an unsupported XCFramework format version"

library_identifiers=""
for index in 0 1 2 3 4; do
  identifier="$(
    plist_value "$root_info_plist" "AvailableLibraries:$index:LibraryIdentifier" || true
  )"
  [[ -n "$identifier" ]] ||
    die "Apple archive has fewer than five AvailableLibraries entries"
  library_identifiers+="$identifier"$'\n'
  [[ "$(plist_value "$root_info_plist" "AvailableLibraries:$index:LibraryPath")" == \
    "XrayRust.framework" ]] ||
    die "Apple archive has an invalid LibraryPath for $identifier"
  expected_binary_path="XrayRust.framework/XrayRust"
  if [[ "$identifier" == macos-* ]]; then
    expected_binary_path="XrayRust.framework/Versions/A/XrayRust"
  fi
  [[ "$(plist_value "$root_info_plist" "AvailableLibraries:$index:BinaryPath")" == \
    "$expected_binary_path" ]] ||
    die "Apple archive has an invalid BinaryPath for $identifier"
  if plist_value \
    "$root_info_plist" \
    "AvailableLibraries:$index:HeadersPath" >/dev/null; then
    die "Apple archive must not expose HeadersPath for $identifier"
  fi
done
if plist_value "$root_info_plist" "AvailableLibraries:5" >/dev/null; then
  die "Apple archive has more than five AvailableLibraries entries"
fi

actual_identifiers="$(printf '%s' "$library_identifiers" | sort)"
expected_identifiers="$(
  printf '%s\n' \
    ios-arm64 \
    ios-arm64_x86_64-simulator \
    macos-arm64_x86_64 \
    tvos-arm64 \
    tvos-arm64_x86_64-simulator |
    sort
)"
[[ "$actual_identifiers" == "$expected_identifiers" ]] ||
  die "Apple archive contains unexpected library identifiers"

header_count="$(
  find "$xcframework" -path "*/Headers/xray_ffi.h" -type f -print |
    wc -l |
    tr -d ' '
)"
[[ "$header_count" == "5" ]] ||
  die "release XCFramework must contain one FFI header per slice"

module_map_count="$(
  find "$xcframework" -path "*/Modules/module.modulemap" -type f -print |
    wc -l |
    tr -d ' '
)"
[[ "$module_map_count" == "5" ]] ||
  die "release XCFramework must contain one framework module map per slice"

legacy_module_map_count="$(
  find "$xcframework" -path "*/Headers/module.modulemap" -type f -print |
    wc -l |
    tr -d ' '
)"
[[ "$legacy_module_map_count" == "0" ]] ||
  die "release XCFramework must not contain static-library module maps"

legacy_library_count="$(
  find "$xcframework" -name "libxray_ffi.a" -type f -print |
    wc -l |
    tr -d ' '
)"
[[ "$legacy_library_count" == "0" ]] ||
  die "release XCFramework must not contain bare static libraries"

echo "verified Apple release archive: $archive"
