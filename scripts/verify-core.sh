#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

core="$(resolve_core_checkout)"

grep -Fq "pub extern \"C\" fn xray_ffi_version_major() -> u32" \
  "$core/crates/xray-ffi/src/lib.rs" ||
  die "core does not expose xray_ffi_version_major"
ffi_source="$core/crates/xray-ffi/src/lib.rs"
version_major_body="$(
  grep -A2 -F "pub extern \"C\" fn xray_ffi_version_major() -> u32" \
    "$ffi_source"
)"
if ! grep -Eq "^[[:space:]]+$XRAY_FFI_ABI_MAJOR$" <<<"$version_major_body"; then
  grep -Eq \
    "^pub const XRAY_FFI_ABI_MAJOR: u32 = $XRAY_FFI_ABI_MAJOR;$" \
    "$ffi_source" &&
    grep -Eq '^[[:space:]]+XRAY_FFI_ABI_MAJOR$' <<<"$version_major_body" ||
    die "core FFI ABI major differs from $XRAY_FFI_ABI_MAJOR"
fi
grep -Fq "static let expectedFFIMajorVersion: UInt32 = $XRAY_FFI_ABI_MAJOR" \
  "$MOBILE_ROOT/Sources/XrayMobileAdapter/XrayCore.swift" ||
  die "Swift adapter expects a different FFI ABI major"
grep -Fq "constexpr uint32_t kExpectedFfiMajorVersion = $XRAY_FFI_ABI_MAJOR;" \
  "$MOBILE_ROOT/android/xraymobile/src/main/cpp/xray_mobile_jni.cpp" ||
  die "JNI adapter expects a different FFI ABI major"

echo "verified $XRAY_RUST_TAG ($XRAY_RUST_COMMIT), FFI ABI $XRAY_FFI_ABI_MAJOR"
