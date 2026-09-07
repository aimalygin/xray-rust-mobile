#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

mode="strict"
case "${1:-}" in
  --prepare) mode="prepare"; shift ;;
  --generated) mode="generated"; shift ;;
esac

tag="${1:-}"
[[ "$#" -le 1 ]] || die "usage: $0 [--prepare | --generated] [v$XRAY_MOBILE_VERSION]"
[[ -z "$tag" || "$mode" == "strict" ]] ||
  die "release tags require strict committed-source validation"
release_channel="$("$SCRIPT_DIR/release-channel.sh" "$XRAY_MOBILE_VERSION")"
if [[ -n "$tag" && "$tag" != "v$XRAY_MOBILE_VERSION" ]]; then
  die "release tag $tag does not match v$XRAY_MOBILE_VERSION"
fi
if [[ -n "$tag" ]]; then
  [[ "$(git -C "$MOBILE_ROOT" cat-file -t "$tag" 2>/dev/null || true)" == "tag" ]] ||
    die "release tag must be annotated: $tag"
  tag_commit="$(git -C "$MOBILE_ROOT" rev-parse "$tag^{commit}")"
  head_commit="$(git -C "$MOBILE_ROOT" rev-parse HEAD)"
  [[ "$tag_commit" == "$head_commit" ]] ||
    die "release tag $tag does not point to HEAD"
fi

grep -Fq "let releaseVersion = \"$XRAY_MOBILE_VERSION\"" \
  "$MOBILE_ROOT/Package.swift" ||
  die "Package.swift version differs from release/version.env"
grep -Fq "VERSION_NAME=$XRAY_MOBILE_VERSION" \
  "$MOBILE_ROOT/android/gradle.properties" ||
  die "Gradle version differs from release/version.env"
macos_major="${MACOS_DEPLOYMENT_TARGET%%.*}"
grep -Fq ".macOS(.v$macos_major)" "$MOBILE_ROOT/Package.swift" ||
  die "Package.swift does not match the macOS deployment target"
tvos_major="${TVOS_DEPLOYMENT_TARGET%%.*}"
grep -Fq ".tvOS(.v$tvos_major)" "$MOBILE_ROOT/Package.swift" ||
  die "Package.swift does not match the tvOS deployment target"
grep -Fq 'include_macos="${APPLE_INCLUDE_MACOS:-1}"' \
  "$MOBILE_ROOT/scripts/build-apple.sh" ||
  die "Apple builds do not include macOS by default"
grep -Fq 'export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"' \
  "$MOBILE_ROOT/scripts/build-apple.sh" ||
  die "Apple builds do not use the locked macOS deployment target"
grep -Fq 'include_tvos="${APPLE_INCLUDE_TVOS:-1}"' \
  "$MOBILE_ROOT/scripts/build-apple.sh" ||
  die "Apple builds do not include tvOS by default"
grep -Fq 'export TVOS_DEPLOYMENT_TARGET="$TVOS_DEPLOYMENT_TARGET"' \
  "$MOBILE_ROOT/scripts/build-apple.sh" ||
  die "Apple builds do not use the locked tvOS deployment target"
grep -Fq 'cargo "+$TVOS_RUST_TOOLCHAIN" build' \
  "$MOBILE_ROOT/scripts/build-apple.sh" ||
  die "tvOS builds do not use the locked nightly Rust toolchain"
grep -Fq -- '-Z build-std=std,panic_unwind' \
  "$MOBILE_ROOT/scripts/build-apple.sh" ||
  die "tvOS builds do not build std for unsupported Rust targets"
grep -Fq 'APPLE_INCLUDE_MACOS=1 APPLE_INCLUDE_TVOS=1 "$SCRIPT_DIR/build-apple.sh"' \
  "$MOBILE_ROOT/scripts/prepare-release.sh" ||
  die "local release preparation does not include macOS and tvOS"
grep -Fq 'APPLE_INCLUDE_MACOS=1 APPLE_INCLUDE_TVOS=1 scripts/build-apple.sh' \
  "$MOBILE_ROOT/.github/workflows/prepare-release.yml" ||
  die "Prepare release workflow does not include macOS and tvOS"
grep -Eq "^## $XRAY_MOBILE_VERSION - [0-9]{4}-[0-9]{2}-[0-9]{2}$" \
  "$MOBILE_ROOT/CHANGELOG.md" ||
  die "CHANGELOG.md has no dated section for $XRAY_MOBILE_VERSION"

checksum="$(
  awk -F'"' '/^let releaseChecksum = / {print $2}' "$MOBILE_ROOT/Package.swift"
)"
[[ "$checksum" =~ ^[0-9a-f]{64}$ ]] ||
  die "Package.swift has no valid SwiftPM checksum"
[[ "$checksum" == "$APPLE_XCFRAMEWORK_SHA256" ]] ||
  die "Package.swift checksum differs from release/artifacts.env"
if [[ "$APPLE_ARTIFACT_RUN_ID" == "0" ]]; then
  [[ "$APPLE_ARTIFACT_NAME" == "apple-release-v$XRAY_MOBILE_VERSION-unprepared" ]] ||
    die "unprepared Apple artifact name differs from the mobile version"
else
  [[ "$APPLE_ARTIFACT_NAME" == "apple-release-v$XRAY_MOBILE_VERSION" ]] ||
    die "prepared Apple artifact name differs from the mobile version"
fi
[[ "$APPLE_ARTIFACT_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
  die "Apple artifact source commit is invalid"
[[ "$APPLE_ARTIFACT_SOURCE_TREE" =~ ^[0-9a-f]{40}$ ]] ||
  die "Apple artifact source tree is invalid"
if [[ "$mode" != "prepare" ]]; then
  [[ "$checksum" != "0000000000000000000000000000000000000000000000000000000000000000" ]] ||
    die "Package.swift still contains a placeholder checksum"
  [[ "$APPLE_ARTIFACT_RUN_ID" =~ ^[1-9][0-9]*$ ]] ||
    die "strict release validation requires a prepared Apple workflow artifact run id"
  [[ "$APPLE_ARTIFACT_SOURCE_COMMIT" != "0000000000000000000000000000000000000000" ]] ||
    die "strict release validation requires the Apple artifact source commit"
  [[ "$APPLE_ARTIFACT_SOURCE_TREE" != "0000000000000000000000000000000000000000" ]] ||
    die "strict release validation requires the Apple artifact source tree"
  verify_apple_artifact_source "$MOBILE_ROOT" \
    "$APPLE_ARTIFACT_SOURCE_COMMIT" "$APPLE_ARTIFACT_SOURCE_TREE" "$mode"
fi

grep -Fq "compileSdk = $ANDROID_COMPILE_SDK" \
  "$MOBILE_ROOT/android/xraymobile/build.gradle.kts" ||
  die "Android compileSdk differs from the toolchain lock"
grep -Fq "minSdk = $ANDROID_MIN_SDK" \
  "$MOBILE_ROOT/android/xraymobile/build.gradle.kts" ||
  die "Android minSdk differs from the toolchain lock"
grep -Fq "ndkVersion = \"$ANDROID_NDK_VERSION\"" \
  "$MOBILE_ROOT/android/xraymobile/build.gradle.kts" ||
  die "Android NDK differs from the toolchain lock"
grep -Fq "version = \"$ANDROID_CMAKE_VERSION\"" \
  "$MOBILE_ROOT/android/xraymobile/build.gradle.kts" ||
  die "Android CMake differs from the toolchain lock"
grep -Fq "id(\"com.android.library\") version \"$ANDROID_GRADLE_PLUGIN_VERSION\"" \
  "$MOBILE_ROOT/android/build.gradle.kts" ||
  die "Android Gradle Plugin differs from the toolchain lock"
grep -Fq "id(\"org.jetbrains.kotlin.android\") version \"$KOTLIN_VERSION\"" \
  "$MOBILE_ROOT/android/build.gradle.kts" ||
  die "Kotlin plugin differs from the toolchain lock"

for workflow in ci.yml prepare-release.yml release.yml; do
  grep -Fq \
    "DEVELOPER_DIR: /Applications/Xcode_$XCODE_VERSION.app/Contents/Developer" \
    "$MOBILE_ROOT/.github/workflows/$workflow" ||
    die "$workflow does not select locked Xcode $XCODE_VERSION"
  grep -Fq 'rustup toolchain install "$TVOS_RUST_TOOLCHAIN"' \
    "$MOBILE_ROOT/.github/workflows/$workflow" ||
    die "$workflow does not install the locked tvOS Rust toolchain"
done

wrapper_jar_sha="$(sha256_file "$MOBILE_ROOT/android/gradle/wrapper/gradle-wrapper.jar")"
[[ "$wrapper_jar_sha" == "7d3a4ac4de1c32b59bc6a4eb8ecb8e612ccd0cf1ae1e99f66902da64df296172" ]] ||
  die "Gradle wrapper JAR checksum differs"
grep -Fq \
  "distributionUrl=https\\://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip" \
  "$MOBILE_ROOT/android/gradle/wrapper/gradle-wrapper.properties" ||
  die "Gradle distribution differs from the toolchain lock"

for metadata in \
  "$MOBILE_ROOT/android/gradle/verification-metadata.xml" \
  "$MOBILE_ROOT/smoke/android/gradle/verification-metadata.xml"; do
  [[ -f "$metadata" ]] || die "missing Gradle dependency verification metadata: $metadata"
  grep -Fq '<verify-metadata>true</verify-metadata>' "$metadata" ||
    die "Gradle metadata verification is disabled: $metadata"
  if grep -Fq 'origin="Generated by Gradle"' "$metadata"; then
    die "Gradle metadata still contains trust-on-first-use origins: $metadata"
  fi
  [[ "$(grep -c '<sha256 ' "$metadata")" -ge 400 ]] ||
    die "Gradle dependency checksum coverage is unexpectedly small: $metadata"
done
if grep -Fq '<trusted-artifacts>' "$MOBILE_ROOT/android/gradle/verification-metadata.xml"; then
  die "main Android build must not bypass Gradle dependency verification"
fi
[[ "$(grep -c '<trust group="io.github.aimalygin" name="xray-rust-mobile"/>' \
  "$MOBILE_ROOT/smoke/android/gradle/verification-metadata.xml")" -eq 1 ]] ||
  die "consumer smoke may trust only the same-workflow staged SDK artifact"
grep -Fq -- '--dependency-verification strict' "$MOBILE_ROOT/scripts/build-android.sh" ||
  die "Android build does not explicitly enforce strict dependency verification"
grep -Fq -- '--dependency-verification strict' "$MOBILE_ROOT/scripts/check-android-consumer.sh" ||
  die "Android consumer smoke does not explicitly enforce strict dependency verification"
for token in \
  'verify_dependencies "$extracted"' \
  'write_exports "$extracted" "$actual_exports"' \
  'release/android-jni-exports.txt'; do
  grep -Fq "$token" "$MOBILE_ROOT/scripts/verify-android-aar.sh" ||
    die "Android AAR verifier is missing native surface guard: $token"
done
grep -Fq '"-Wl,--exclude-libs,ALL"' \
  "$MOBILE_ROOT/android/xraymobile/src/main/cpp/CMakeLists.txt" ||
  die "Android JNI build does not hide statically linked runtime symbols"

for script in "$MOBILE_ROOT"/scripts/*.sh; do
  if ! bash -n "$script"; then
    die "invalid shell syntax: $script"
  fi
done

"$SCRIPT_DIR/check-release-workflows.sh"

if [[ "${SKIP_CORE_VERIFY:-0}" != "1" ]]; then
  "$SCRIPT_DIR/verify-core.sh"
  "$SCRIPT_DIR/verify-source-sync.sh"
fi

echo "verified $release_channel mobile release metadata for v$XRAY_MOBILE_VERSION"
