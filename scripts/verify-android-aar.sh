#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

aar="${1:-}"
native_dir="${2:-$MOBILE_ROOT/.build/android/native}"
[[ -f "$aar" ]] || die "usage: $0 <aar> [native-dir]"

require_command cmp
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

manifest="$temporary/AndroidManifest.xml"
unzip -p "$aar" AndroidManifest.xml >"$manifest"
grep -Fq "android.permission.INTERNET" "$manifest" ||
  die "AAR manifest is missing INTERNET"
grep -Fq "android.permission.FOREGROUND_SERVICE" "$manifest" ||
  die "AAR manifest is missing FOREGROUND_SERVICE"
if grep -Fq "android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED" "$manifest"; then
  die "AAR must leave the target-SDK-specific foreground-service permission to the host"
fi
if grep -Fq "org.xrayrust.mobile.XrayVpnService" "$manifest"; then
  die "AAR must not register the base XrayVpnService; the host must register its subclass"
fi

for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  for library in libxray_ffi.so libxray_mobile_jni.so; do
    entry="jni/$abi/$library"
    grep -Fxq "$entry" <<<"$entries" || die "AAR is missing $entry"
    extracted="$temporary/$abi-$library"
    unzip -p "$aar" "$entry" >"$extracted"
    verify_alignment "$extracted"

    if [[ "$library" == "libxray_ffi.so" ]]; then
      cmp "$native_dir/jniLibs/$abi/$library" "$extracted" ||
        die "AAR Rust library differs from the locked native artifact: $abi"
    else
      needed="$("$readelf" -d "$extracted" | awk -F'[][]' '/NEEDED/ {print $2}')"
      grep -Fxq "libxray_ffi.so" <<<"$needed" ||
        die "JNI library does not load libxray_ffi.so by soname: $abi"
      if grep -Eq '^/|libc\+\+_shared\.so' <<<"$needed"; then
        die "JNI library has a forbidden runtime dependency: $abi"
      fi
    fi
  done
done

grep -Fxq "proguard.txt" <<<"$entries" ||
  die "AAR is missing consumer ProGuard rules"

echo "verified Android AAR: $aar"
