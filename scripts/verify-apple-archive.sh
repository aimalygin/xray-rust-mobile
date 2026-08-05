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
require_command otool
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

expected_platform() {
  case "$1" in
  ios-*) echo ios ;;
  tvos-*) echo tvos ;;
  macos-*) echo macos ;;
  *) die "unknown library identifier: $1" ;;
  esac
}

expected_platform_variant() {
  case "$1" in
  *-simulator) echo simulator ;;
  *) echo "" ;;
  esac
}

# Each slice is a bare static library: no framework bundle, no headers, and no
# module map. The public C API is published from the XrayRustFFI Clang target
# instead, because Xcode flattens the headers of a static-library XCFramework
# into $BUILT_PRODUCTS_DIR/include, where the fixed module.modulemap name
# collides with any other static-library XCFramework in the same target.
verify_library() {
  local identifier="$1"
  shift

  local slice="$xcframework/$identifier"
  local library="$slice/libxray_ffi.a"

  [[ -f "$library" ]] || die "Apple archive has no library for $identifier"
  [[ "$(file "$library")" == *"current ar archive"* ]] ||
    die "Apple archive library is not static for $identifier"
  lipo "$library" -verify_arch "$@"

  # grep -c rather than grep -q: an early -q exit kills otool with SIGPIPE, and
  # under `set -o pipefail` that turns the whole check into a silent no-op.
  local bitcode_sections
  bitcode_sections="$(
    otool -l "$library" 2>/dev/null | grep -c "sectname __bitcode" || true
  )"
  [[ "$bitcode_sections" == "0" ]] ||
    die "Apple archive library still embeds LLVM bitcode for $identifier"

  local entries
  entries="$(find "$slice" -mindepth 1 -print | wc -l | tr -d ' ')"
  [[ "$entries" == "1" ]] ||
    die "Apple archive slice $identifier must contain only libxray_ffi.a"
}

verify_library ios-arm64 arm64
verify_library ios-arm64_x86_64-simulator arm64 x86_64
verify_library tvos-arm64 arm64
verify_library tvos-arm64_x86_64-simulator arm64 x86_64
verify_library macos-arm64_x86_64 arm64 x86_64

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
    "libxray_ffi.a" ]] ||
    die "Apple archive has an invalid LibraryPath for $identifier"
  [[ "$(plist_value "$root_info_plist" "AvailableLibraries:$index:BinaryPath")" == \
    "libxray_ffi.a" ]] ||
    die "Apple archive has an invalid BinaryPath for $identifier"
  if plist_value \
    "$root_info_plist" \
    "AvailableLibraries:$index:HeadersPath" >/dev/null; then
    die "Apple archive must not expose HeadersPath for $identifier"
  fi
  [[ "$(plist_value "$root_info_plist" "AvailableLibraries:$index:SupportedPlatform")" == \
    "$(expected_platform "$identifier")" ]] ||
    die "Apple archive has an invalid supported platform for $identifier"
  variant="$(
    plist_value \
      "$root_info_plist" \
      "AvailableLibraries:$index:SupportedPlatformVariant" || true
  )"
  [[ "$variant" == "$(expected_platform_variant "$identifier")" ]] ||
    die "Apple archive has an invalid platform variant for $identifier"
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
  find "$xcframework" \( -name "*.h" -o -name "module.modulemap" \) -print |
    wc -l |
    tr -d ' '
)"
[[ "$header_count" == "0" ]] ||
  die "release XCFramework must not package headers or module maps"

framework_count="$(
  find "$xcframework" -name "*.framework" -print | wc -l | tr -d ' '
)"
[[ "$framework_count" == "0" ]] ||
  die "release XCFramework must not contain framework bundles"

library_count="$(
  find "$xcframework" -name "libxray_ffi.a" -type f -print | wc -l | tr -d ' '
)"
[[ "$library_count" == "5" ]] ||
  die "release XCFramework must contain one static library per slice"

echo "verified Apple release archive: $archive"
