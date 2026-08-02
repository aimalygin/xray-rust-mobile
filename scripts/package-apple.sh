#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

require_command swift
require_command zip

xcframework="${1:-$MOBILE_ROOT/Artifacts/XrayRust.xcframework}"
dist_dir="${DIST_DIR:-$MOBILE_ROOT/dist/v$XRAY_MOBILE_VERSION}"
[[ -d "$xcframework" ]] || die "XCFramework not found: $xcframework"
[[ -n "$dist_dir" && "$dist_dir" != "/" ]] || die "unsafe distribution directory"
mkdir -p "$dist_dir" "$MOBILE_ROOT/.build"
dist_dir="$(cd "$dist_dir" && pwd -P)"

package_dir="$(mktemp -d "$MOBILE_ROOT/.build/apple-package.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT

cp -R "$xcframework" "$package_dir/XrayRust.xcframework"
xattr -cr "$package_dir/XrayRust.xcframework" 2>/dev/null || true
find "$package_dir/XrayRust.xcframework" -exec touch -t 198001010000 {} +

archive="$dist_dir/XrayRust.xcframework.zip"
rm -f "$archive"
(
  cd "$package_dir"
  COPYFILE_DISABLE=1 zip -qry -X "$archive" XrayRust.xcframework
)

checksum="$(swift package compute-checksum "$archive")"
printf '%s\n' "$checksum" >"$dist_dir/XrayRust.xcframework.checksum"
printf '%s  %s\n' "$(sha256_file "$archive")" "$(basename "$archive")" \
  >"$dist_dir/SHA256SUMS.apple"

echo "$archive"
echo "$checksum"
