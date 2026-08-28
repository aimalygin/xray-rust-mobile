#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

include_maven=1
if [[ "${1:-}" == "--standalone-only" ]]; then
  include_maven=0
  shift
fi
[[ "$#" -le 1 ]] || die "usage: $0 [--standalone-only] [aar]"

aar="${1:-$MOBILE_ROOT/android/xraymobile/build/outputs/aar/xraymobile-release.aar}"
dist_dir="${DIST_DIR:-$MOBILE_ROOT/dist/v$XRAY_MOBILE_VERSION}"
[[ -f "$aar" ]] || die "Android AAR not found: $aar"
require_command shasum
mkdir -p "$dist_dir"
dist_dir="$(cd "$dist_dir" && pwd -P)"

output="$dist_dir/xray-rust-mobile-$XRAY_MOBILE_VERSION.aar"
cp "$aar" "$output"
maven_output="$dist_dir/xray-rust-mobile-$XRAY_MOBILE_VERSION-maven.zip"
if [[ "$include_maven" -eq 0 ]]; then
  rm -f "$maven_output"
  printf '%s  %s\n' "$(sha256_file "$output")" "$(basename "$output")" \
    >"$dist_dir/SHA256SUMS.android"
  echo "$output"
  exit 0
fi

require_command zip
require_command git
maven_repository="$MOBILE_ROOT/android/build/maven-repository"
[[ -d "$maven_repository" ]] ||
  die "staged Maven repository not found: $maven_repository"
rm -f "$maven_output"

group="$(awk -F= '$1 == "GROUP" {print $2}' "$MOBILE_ROOT/android/gradle.properties")"
artifact="$(awk -F= '$1 == "POM_ARTIFACT_ID" {print $2}' "$MOBILE_ROOT/android/gradle.properties")"
[[ -n "$group" && -n "$artifact" ]] || die "missing Maven coordinates"
group_path="${group//.//}"
version_dir="$maven_repository/$group_path/$artifact/$XRAY_MOBILE_VERSION"
metadata="$maven_repository/$group_path/$artifact/maven-metadata.xml"
[[ -d "$version_dir" ]] || die "staged Maven version is missing: $version_dir"
[[ -f "$metadata" ]] || die "staged Maven metadata is missing: $metadata"

temporary="$(mktemp -d "$MOBILE_ROOT/.build/maven-package.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/$group_path/$artifact"
cp -R "$version_dir" "$temporary/$group_path/$artifact/"
cp "$metadata" "$temporary/$group_path/$artifact/"

core="$(resolve_core_checkout)"
last_updated="$(
  TZ=UTC git -C "$core" show -s \
    --format=%cd \
    --date=format-local:%Y%m%d%H%M%S \
    "$XRAY_RUST_COMMIT"
)"
[[ "$last_updated" =~ ^[0-9]{14}$ ]] ||
  die "could not derive deterministic Maven timestamp"
packaged_metadata="$temporary/$group_path/$artifact/maven-metadata.xml"
sed \
  "s|<lastUpdated>[^<]*</lastUpdated>|<lastUpdated>$last_updated</lastUpdated>|" \
  "$packaged_metadata" >"$packaged_metadata.tmp"
mv "$packaged_metadata.tmp" "$packaged_metadata"

if command -v md5sum >/dev/null 2>&1; then
  metadata_md5="$(md5sum "$packaged_metadata" | awk '{print $1}')"
elif command -v md5 >/dev/null 2>&1; then
  metadata_md5="$(md5 -q "$packaged_metadata")"
else
  die "missing required command: md5sum or md5"
fi
printf '%s' "$metadata_md5" >"$packaged_metadata.md5"
for algorithm in 1 256 512; do
  digest="$(shasum -a "$algorithm" "$packaged_metadata" | awk '{print $1}')"
  case "$algorithm" in
    1) suffix=sha1 ;;
    *) suffix="sha$algorithm" ;;
  esac
  printf '%s' "$digest" >"$packaged_metadata.$suffix"
done

export TZ=UTC
touch_stamp="${last_updated:0:12}.${last_updated:12:2}"
find "$temporary" -exec touch -t "$touch_stamp" {} +
(
  cd "$temporary"
  find . -type f -print | LC_ALL=C sort | zip -q -X "$maven_output" -@
)
{
  printf '%s  %s\n' "$(sha256_file "$output")" "$(basename "$output")"
  printf '%s  %s\n' "$(sha256_file "$maven_output")" "$(basename "$maven_output")"
} >"$dist_dir/SHA256SUMS.android"

echo "$output"
echo "$maven_output"
