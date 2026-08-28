#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

version="${1:-}"
[[ "$version" == "$XRAY_MOBILE_VERSION" ]] ||
  die "usage: $0 $XRAY_MOBILE_VERSION"
release_channel="$("$SCRIPT_DIR/release-channel.sh" "$version")"

"$SCRIPT_DIR/check-release.sh" --prepare
APPLE_INCLUDE_MACOS=1 APPLE_INCLUDE_TVOS=1 "$SCRIPT_DIR/build-apple.sh"
apple_output="$("$SCRIPT_DIR/package-apple.sh")"
apple_archive="$(sed -n '1p' <<<"$apple_output")"
"$SCRIPT_DIR/verify-apple-archive.sh" --structural "$apple_archive"
apple_checksum="$(swift package compute-checksum "$apple_archive")"
"$SCRIPT_DIR/build-android.sh"
if [[ "$release_channel" == "prerelease" ]]; then
  "$SCRIPT_DIR/package-android.sh" --standalone-only
  cp "$MOBILE_ROOT/LICENSE" \
    "$MOBILE_ROOT/dist/v$version/LICENSE"
  cp "$MOBILE_ROOT/THIRD_PARTY_NOTICES.md" \
    "$MOBILE_ROOT/dist/v$version/THIRD_PARTY_NOTICES.md"
else
  "$SCRIPT_DIR/package-android.sh"
fi
"$SCRIPT_DIR/write-release-manifest.sh" \
  "$MOBILE_ROOT/dist/v$version" \
  "$release_channel"

echo "release v$version is staged under $MOBILE_ROOT/dist/v$version"
echo "local Apple checksum: $apple_checksum"
echo "this local preflight does not update release locks; dispatch Prepare release before tagging"
