#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

run_id="${1:-}"
archive="${2:-}"
artifact_name="${3:-}"
[[ "$#" -eq 3 && "$run_id" =~ ^[0-9]+$ ]] ||
  die "usage: $0 <github-run-id> <XrayRust.xcframework.zip> <artifact-name>"
[[ -f "$archive" ]] ||
  die "usage: $0 <github-run-id> <XrayRust.xcframework.zip> <artifact-name>"
[[ "$artifact_name" =~ ^apple-release-v[0-9A-Za-z.-]+$ ]] ||
  die "invalid Apple workflow artifact name: $artifact_name"

checksum="$(sha256_file "$archive")"
package_checksum="$(
  awk -F'"' '/^let releaseChecksum = / {print $2}' "$MOBILE_ROOT/Package.swift"
)"
[[ "$checksum" == "$package_checksum" ]] ||
  die "archive checksum differs from Package.swift"

temporary="$(mktemp "$MOBILE_ROOT/release/.artifacts.env.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
cat >"$temporary" <<LOCK
APPLE_ARTIFACT_RUN_ID=$run_id
APPLE_ARTIFACT_NAME=$artifact_name
APPLE_XCFRAMEWORK_SHA256=$checksum
LOCK
chmod 0644 "$temporary"
mv "$temporary" "$MOBILE_ROOT/release/artifacts.env"
trap - EXIT

echo "$checksum"
