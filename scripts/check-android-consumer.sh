#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

repository="${1:-$MOBILE_ROOT/android/build/maven-repository}"
[[ -d "$repository" ]] ||
  die "staged Maven repository not found: $repository"

sdk="$(resolve_android_sdk || true)"
[[ -n "$sdk" ]] || die "Android SDK not found; set ANDROID_HOME"
export ANDROID_HOME="$sdk"
export ANDROID_SDK_ROOT="$sdk"

export XRAY_MAVEN_REPOSITORY
XRAY_MAVEN_REPOSITORY="$(cd "$repository" && pwd -P)"
export XRAY_MOBILE_VERSION
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$MOBILE_ROOT/.build/android/gradle-home}"

"$MOBILE_ROOT/android/gradlew" \
  -p "$MOBILE_ROOT/smoke/android" \
  :consumer:assembleRelease \
  --no-daemon

manifest="$(
  find "$MOBILE_ROOT/smoke/android/consumer/build/intermediates" \
    -path '*/release/*' -name AndroidManifest.xml -type f -print |
    sort |
    tail -n 1
)"
[[ -f "$manifest" ]] || die "merged release manifest was not produced"
[[ "$(grep -c 'android:name="org.xrayrust.mobile.smoke.AppVpnService"' "$manifest")" -eq 1 ]] ||
  die "consumer manifest must contain exactly one concrete VPN service"
grep -Fq 'android:foregroundServiceType="systemExempted"' "$manifest" ||
  die "consumer VPN service is missing systemExempted"
grep -Fq 'android:permission="android.permission.BIND_VPN_SERVICE"' "$manifest" ||
  die "consumer VPN service is missing BIND_VPN_SERVICE"
grep -Fq 'android:exported="false"' "$manifest" ||
  die "consumer VPN service must not be exported"
grep -Fq 'android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED' "$manifest" ||
  die "consumer manifest is missing FOREGROUND_SERVICE_SYSTEM_EXEMPTED"
if grep -Fq 'android:name="org.xrayrust.mobile.XrayVpnService"' "$manifest"; then
  die "consumer manifest unexpectedly registers the base VPN service"
fi

apk="$MOBILE_ROOT/smoke/android/consumer/build/outputs/apk/release/consumer-release-unsigned.apk"
[[ -f "$apk" ]] || die "minified consumer APK was not produced"
entries="$(unzip -Z1 "$apk")"
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  for library in libxray_ffi.so libxray_mobile_jni.so; do
    grep -Fxq "lib/$abi/$library" <<<"$entries" ||
      die "consumer APK is missing lib/$abi/$library"
  done
done

echo "verified minified Android consumer: $apk"
