#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

dist_dir="${1:-$MOBILE_ROOT/dist/v$XRAY_MOBILE_VERSION}"
apple="$dist_dir/XrayRust.xcframework.zip"
android="$dist_dir/xray-rust-mobile-$XRAY_MOBILE_VERSION.aar"
maven="$dist_dir/xray-rust-mobile-$XRAY_MOBILE_VERSION-maven.zip"
[[ -f "$apple" ]] || die "missing Apple release artifact: $apple"
[[ -f "$android" ]] || die "missing Android release artifact: $android"
[[ -f "$maven" ]] || die "missing Maven repository archive: $maven"

apple_sha="$(sha256_file "$apple")"
android_sha="$(sha256_file "$android")"
maven_sha="$(sha256_file "$maven")"
manifest="$dist_dir/release-manifest.json"

cat >"$manifest" <<JSON
{
  "mobileVersion": "$XRAY_MOBILE_VERSION",
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
    "XrayRust.xcframework.zip": "$apple_sha",
    "xray-rust-mobile-$XRAY_MOBILE_VERSION.aar": "$android_sha",
    "xray-rust-mobile-$XRAY_MOBILE_VERSION-maven.zip": "$maven_sha"
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
  shasum -a 256 \
    XrayRust.xcframework.zip \
    "xray-rust-mobile-$XRAY_MOBILE_VERSION.aar" \
    "xray-rust-mobile-$XRAY_MOBILE_VERSION-maven.zip" \
    release-manifest.json >SHA256SUMS
)

echo "$manifest"
