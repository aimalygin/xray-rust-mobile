#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

mode="strict"
if [[ "${1:-}" == "--prepare" ]]; then
  mode="prepare"
  shift
fi

tag="${1:-}"
[[ "$#" -le 1 ]] || die "usage: $0 [--prepare] [v$XRAY_MOBILE_VERSION]"
[[ "$XRAY_MOBILE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] ||
  die "invalid mobile SemVer: $XRAY_MOBILE_VERSION"
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
grep -Fq 'include_macos="${APPLE_INCLUDE_MACOS:-1}"' \
  "$MOBILE_ROOT/scripts/build-apple.sh" ||
  die "Apple builds do not include macOS by default"
grep -Fq 'export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"' \
  "$MOBILE_ROOT/scripts/build-apple.sh" ||
  die "Apple builds do not use the locked macOS deployment target"
grep -Fq 'APPLE_INCLUDE_MACOS=1 "$SCRIPT_DIR/build-apple.sh"' \
  "$MOBILE_ROOT/scripts/prepare-release.sh" ||
  die "local release preparation does not include macOS"
grep -Fq 'APPLE_INCLUDE_MACOS=1 scripts/build-apple.sh' \
  "$MOBILE_ROOT/.github/workflows/prepare-release.yml" ||
  die "Prepare release workflow does not include macOS"
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
if [[ "$mode" == "strict" ]]; then
  [[ "$checksum" != "0000000000000000000000000000000000000000000000000000000000000000" ]] ||
    die "Package.swift still contains a placeholder checksum"
  [[ "$APPLE_ARTIFACT_RUN_ID" =~ ^[1-9][0-9]*$ ]] ||
    die "strict release validation requires a prepared Apple workflow artifact run id"
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
done

wrapper_jar_sha="$(sha256_file "$MOBILE_ROOT/android/gradle/wrapper/gradle-wrapper.jar")"
[[ "$wrapper_jar_sha" == "7d3a4ac4de1c32b59bc6a4eb8ecb8e612ccd0cf1ae1e99f66902da64df296172" ]] ||
  die "Gradle wrapper JAR checksum differs"
grep -Fq \
  "distributionUrl=https\\://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip" \
  "$MOBILE_ROOT/android/gradle/wrapper/gradle-wrapper.properties" ||
  die "Gradle distribution differs from the toolchain lock"

for script in "$MOBILE_ROOT"/scripts/*.sh; do
  if ! bash -n "$script"; then
    die "invalid shell syntax: $script"
  fi
done

if [[ "${SKIP_CORE_VERIFY:-0}" != "1" ]]; then
  "$SCRIPT_DIR/verify-core.sh"
  "$SCRIPT_DIR/verify-source-sync.sh"
fi

echo "verified mobile release metadata for v$XRAY_MOBILE_VERSION"
