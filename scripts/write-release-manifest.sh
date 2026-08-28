#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

dist_dir="${1:-$MOBILE_ROOT/dist/v$XRAY_MOBILE_VERSION}"
release_channel="${2:-$("$SCRIPT_DIR/release-channel.sh" "$XRAY_MOBILE_VERSION")}"
expected_channel="$("$SCRIPT_DIR/release-channel.sh" "$XRAY_MOBILE_VERSION")"
[[ "$release_channel" == "$expected_channel" ]] ||
  die "release channel $release_channel does not match $XRAY_MOBILE_VERSION"
apple="$dist_dir/XrayRust.xcframework.zip"
android="$dist_dir/xray-rust-mobile-$XRAY_MOBILE_VERSION.aar"
maven="$dist_dir/xray-rust-mobile-$XRAY_MOBILE_VERSION-maven.zip"
license="$dist_dir/LICENSE"
notices="$dist_dir/THIRD_PARTY_NOTICES.md"
[[ -f "$apple" ]] || die "missing Apple release artifact: $apple"
[[ -f "$android" ]] || die "missing Android release artifact: $android"

apple_sha="$(sha256_file "$apple")"
android_sha="$(sha256_file "$android")"
manifest="$dist_dir/release-manifest.json"

case "$release_channel" in
  stable)
    [[ -f "$maven" ]] || die "missing Maven repository archive: $maven"
    maven_sha="$(sha256_file "$maven")"
    release_fields=""
    printf -v artifact_fields \
      '    "XrayRust.xcframework.zip": "%s",\n    "xray-rust-mobile-%s.aar": "%s",\n    "xray-rust-mobile-%s-maven.zip": "%s"' \
      "$apple_sha" \
      "$XRAY_MOBILE_VERSION" \
      "$android_sha" \
      "$XRAY_MOBILE_VERSION" \
      "$maven_sha"
    checksum_files=(
      XrayRust.xcframework.zip
      "xray-rust-mobile-$XRAY_MOBILE_VERSION.aar"
      "xray-rust-mobile-$XRAY_MOBILE_VERSION-maven.zip"
    )
    ;;
  prerelease)
    [[ -f "$license" ]] || die "missing prerelease license: $license"
    [[ -f "$notices" ]] || die "missing prerelease notices: $notices"
    [[ ! -e "$maven" ]] ||
      die "prerelease distribution must not contain a Maven repository archive"
    license_sha="$(sha256_file "$license")"
    notices_sha="$(sha256_file "$notices")"
    release_fields=$'  "releaseChannel": "prerelease",\n  "remoteMavenPublication": false,\n'
    printf -v artifact_fields \
      '    "XrayRust.xcframework.zip": "%s",\n    "xray-rust-mobile-%s.aar": "%s",\n    "LICENSE": "%s",\n    "THIRD_PARTY_NOTICES.md": "%s"' \
      "$apple_sha" \
      "$XRAY_MOBILE_VERSION" \
      "$android_sha" \
      "$license_sha" \
      "$notices_sha"
    checksum_files=(
      XrayRust.xcframework.zip
      "xray-rust-mobile-$XRAY_MOBILE_VERSION.aar"
      LICENSE
      THIRD_PARTY_NOTICES.md
    )
    ;;
  *)
    die "unsupported release channel: $release_channel"
    ;;
esac

cat >"$manifest" <<JSON
{
${release_fields}  "mobileVersion": "$XRAY_MOBILE_VERSION",
  "ffiAbiMajor": $XRAY_FFI_ABI_MAJOR,
  "core": {
    "repository": "$XRAY_RUST_REPOSITORY",
    "tag": "$XRAY_RUST_TAG",
    "tagObject": "$XRAY_RUST_TAG_OBJECT",
    "commit": "$XRAY_RUST_COMMIT",
    "tree": "$XRAY_RUST_TREE",
    "cargoLockSha256": "$XRAY_RUST_CARGO_LOCK_SHA256",
    "ffiHeaderSha256": "$XRAY_RUST_FFI_HEADER_SHA256",
    "moduleMapSha256": "$XRAY_RUST_MODULEMAP_SHA256"
  },
  "appleWorkflowArtifact": {
    "runId": $APPLE_ARTIFACT_RUN_ID,
    "name": "$APPLE_ARTIFACT_NAME"
  },
  "artifacts": {
$artifact_fields
  },
  "toolchains": {
    "rust": "$RUST_TOOLCHAIN",
    "tvosRust": "$TVOS_RUST_TOOLCHAIN",
    "xcode": "$XCODE_VERSION",
    "iosDeploymentTarget": "$IOS_DEPLOYMENT_TARGET",
    "tvosDeploymentTarget": "$TVOS_DEPLOYMENT_TARGET",
    "androidMinSdk": $ANDROID_MIN_SDK,
    "androidCompileSdk": $ANDROID_COMPILE_SDK,
    "androidNdk": "$ANDROID_NDK_VERSION",
    "androidCMake": "$ANDROID_CMAKE_VERSION",
    "jdk": $JDK_VERSION,
    "gradle": "$GRADLE_VERSION",
    "androidGradlePlugin": "$ANDROID_GRADLE_PLUGIN_VERSION",
    "kotlin": "$KOTLIN_VERSION"
  }
}
JSON

(
  cd "$dist_dir"
  shasum -a 256 "${checksum_files[@]}" release-manifest.json >SHA256SUMS
)

echo "$manifest"
