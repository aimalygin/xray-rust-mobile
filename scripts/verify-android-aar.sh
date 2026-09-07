#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

aar="${1:-}"
native_dir="${2:-$MOBILE_ROOT/.build/android/native}"
[[ -f "$aar" ]] || die "usage: $0 <aar> [native-dir]"

require_command cmp
require_command diff
require_command python3
require_command sort
require_command unzip

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk" ]]; then
  for candidate in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    if [[ -d "$candidate" ]]; then
      sdk="$candidate"
      break
    fi
  done
fi
[[ -n "$sdk" ]] || die "Android SDK not found"

ndk="${ANDROID_NDK_HOME:-$sdk/ndk/$ANDROID_NDK_VERSION}"
case "$(uname -s)" in
  Darwin) host_candidates=("darwin-$(uname -m)" "darwin-x86_64") ;;
  Linux) host_candidates=("linux-$(uname -m)" "linux-x86_64") ;;
  *) die "unsupported host for Android verification: $(uname -s)" ;;
esac

readelf=""
for host in "${host_candidates[@]}"; do
  candidate="$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-readelf"
  if [[ -x "$candidate" ]]; then
    readelf="$candidate"
    break
  fi
done
[[ -x "$readelf" ]] || die "NDK llvm-readelf not found under $ndk"

python3 "$SCRIPT_DIR/verify-aar-surface.py" "$aar"
unzip -tqq "$aar"
entries="$(unzip -Z1 "$aar")"
temporary="$(mktemp -d "$MOBILE_ROOT/.build/android-aar.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT

verify_alignment() {
  local library="$1"
  local saw_load=0
  local alignment
  while IFS= read -r alignment; do
    saw_load=1
    if (( alignment < 0x4000 )); then
      die "ELF LOAD alignment is below 16 KiB: $library ($alignment)"
    fi
  done < <("$readelf" -lW "$library" | awk '$1 == "LOAD" {print $NF}')
  (( saw_load == 1 )) || die "ELF has no LOAD segment: $library"
}

verify_dependencies() {
  local library="$1"
  local needed
  local saw_xray_ffi=0
  while IFS= read -r needed; do
    case "$(basename "$library"):$needed" in
      *libxray_ffi.so:libc.so|*libxray_ffi.so:libdl.so|*libxray_ffi.so:liblog.so|*libxray_ffi.so:libm.so) ;;
      *libxray_mobile_jni.so:libc.so|*libxray_mobile_jni.so:libdl.so|*libxray_mobile_jni.so:liblog.so|*libxray_mobile_jni.so:libm.so) ;;
      *libxray_mobile_jni.so:libxray_ffi.so) saw_xray_ffi=1 ;;
      *) die "ELF has an unexpected runtime dependency: $library ($needed)" ;;
    esac
  done < <("$readelf" -d "$library" | awk -F'[][]' '/NEEDED/ {print $2}')
  if [[ "$(basename "$library")" == *libxray_mobile_jni.so ]] && (( saw_xray_ffi == 0 )); then
    die "JNI library does not depend on libxray_ffi.so: $library"
  fi
}

write_exports() {
  local library="$1"
  local output="$2"
  "$readelf" --dyn-syms --wide "$library" |
    awk '$7 != "UND" && ($5 == "GLOBAL" || $5 == "WEAK") { name=$8; sub(/@.*/, "", name); print name }' |
    sort -u >"$output"
}

expected_ffi_exports="$temporary/expected-ffi-exports.txt"
expected_jni_exports="$temporary/expected-jni-exports.txt"
grep -Eo 'xray_[a-z0-9_]+\(' "$native_dir/include/xray_ffi.h" |
  sed 's/($//' | sort -u >"$expected_ffi_exports"
sort -u "$MOBILE_ROOT/release/android-jni-exports.txt" >"$expected_jni_exports"
[[ -s "$expected_ffi_exports" && -s "$expected_jni_exports" ]] ||
  die "native export allowlist is empty"

for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  for library in libxray_ffi.so libxray_mobile_jni.so; do
    entry="jni/$abi/$library"
    grep -Fxq "$entry" <<<"$entries" || die "AAR is missing $entry"
    extracted="$temporary/$abi-$library"
    unzip -p "$aar" "$entry" >"$extracted"
    verify_alignment "$extracted"
    verify_dependencies "$extracted"

    actual_exports="$temporary/$abi-$library.exports"
    write_exports "$extracted" "$actual_exports"

    if [[ "$library" == "libxray_ffi.so" ]]; then
      cmp "$native_dir/jniLibs/$abi/$library" "$extracted" ||
        die "AAR Rust library differs from the locked native artifact: $abi"
      diff -u "$expected_ffi_exports" "$actual_exports" ||
        die "Rust FFI export surface differs from its locked header: $abi"
    else
      diff -u "$expected_jni_exports" "$actual_exports" ||
        die "JNI export surface differs from the release allowlist: $abi"
    fi
  done
done

grep -Fxq "proguard.txt" <<<"$entries" ||
  die "AAR is missing consumer ProGuard rules"

echo "verified Android AAR: $aar"
