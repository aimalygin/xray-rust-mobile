#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

core="$(resolve_core_checkout)"
sdk="$(resolve_android_sdk || true)"
[[ -n "$sdk" ]] || die "Android SDK not found; set ANDROID_HOME"
ndk="${ANDROID_NDK_HOME:-$sdk/ndk/$ANDROID_NDK_VERSION}"
[[ -d "$ndk" ]] || die "Android NDK $ANDROID_NDK_VERSION not found: $ndk"

native_dir="${XRAY_FFI_ANDROID_DIR:-$MOBILE_ROOT/.build/android/native}"
cargo_target_dir="${ANDROID_CARGO_TARGET_DIR:-$MOBILE_ROOT/.build/android/cargo}"
gradle_home="${GRADLE_USER_HOME:-$MOBILE_ROOT/.build/android/gradle-home}"

mkdir -p "$native_dir" "$cargo_target_dir" "$gradle_home"
native_dir="$(cd "$native_dir" && pwd -P)"
cargo_target_dir="$(cd "$cargo_target_dir" && pwd -P)"
gradle_home="$(cd "$gradle_home" && pwd -P)"

export ANDROID_HOME="$sdk"
export ANDROID_SDK_ROOT="$sdk"
export ANDROID_NDK_HOME="$ndk"
export ANDROID_NDK_ROOT="$ndk"
export XRAY_FFI_ANDROID_DIR="$native_dir"
export CARGO_TARGET_DIR="$cargo_target_dir"
export GRADLE_USER_HOME="$gradle_home"
export CARGO_INCREMENTAL=0
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH="$(git -C "$core" show -s --format=%ct "$XRAY_RUST_COMMIT")"
export TZ=UTC
export LC_ALL=C

if [[ "${XRAY_USE_PREBUILT_ARTIFACTS:-0}" != "1" ]]; then
  require_command rustup
  rustup run "$RUST_TOOLCHAIN" cargo --version >/dev/null
  RUSTUP_TOOLCHAIN="$RUST_TOOLCHAIN" \
    OUT_DIR="$native_dir" \
    "$core/scripts/build-android-libs.sh"
fi

tasks=("$@")
if [[ "${#tasks[@]}" -eq 0 ]]; then
  tasks=(
    :xraymobile:testDebugUnitTest
    :xraymobile:assembleRelease
    :xraymobile:publishReleasePublicationToStagingRepository
  )
fi

"$MOBILE_ROOT/android/gradlew" \
  -p "$MOBILE_ROOT/android" \
  "${tasks[@]}" \
  --no-daemon

aar="$MOBILE_ROOT/android/xraymobile/build/outputs/aar/xraymobile-release.aar"
"$SCRIPT_DIR/verify-android-aar.sh" "$aar" "$native_dir"
echo "$aar"
