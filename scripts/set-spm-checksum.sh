#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

archive="${1:-}"
[[ -f "$archive" ]] || die "usage: $0 <XrayRust.xcframework.zip>"
require_command swift

checksum="$(swift package compute-checksum "$archive")"
[[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || die "invalid SwiftPM checksum: $checksum"

temporary="$(mktemp "$MOBILE_ROOT/.Package.swift.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
awk -v checksum="$checksum" '
  /^let releaseChecksum = / {
    print "let releaseChecksum = \"" checksum "\""
    updated = 1
    next
  }
  { print }
  END {
    if (!updated) {
      exit 1
    }
  }
' "$MOBILE_ROOT/Package.swift" >"$temporary"
chmod 0644 "$temporary"
mv "$temporary" "$MOBILE_ROOT/Package.swift"
trap - EXIT

echo "$checksum"
