#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

: "${JAVA_HOME:?set JAVA_HOME to a JDK with JNI headers}"
core="$(resolve_core_checkout)"
sdk="$(resolve_android_sdk)"
export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$MOBILE_ROOT/.build/android/gradle-home}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$MOBILE_ROOT/.build/host-jni/cargo}"
export CARGO_INCREMENTAL=0

case "$(uname -s)" in
  Darwin) platform=darwin; extension=dylib; link_mode=-dynamiclib ;;
  Linux) platform=linux; extension=so; link_mode=-shared ;;
  *) die "host JNI tests support macOS and Linux" ;;
esac

test_root="$(mktemp -d "${TMPDIR:-/tmp}/xray-sdk-jni.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
cargo "+$RUST_TOOLCHAIN" build --locked --manifest-path "$core/Cargo.toml" -p xray-ffi
native_dir="$(cd "$CARGO_TARGET_DIR/debug" && pwd -P)"
"${CXX:-c++}" -std=c++17 -fPIC "$link_mode" -Wall -Wextra -Werror \
  -I "$JAVA_HOME/include" -I "$JAVA_HOME/include/$platform" \
  -I "$MOBILE_ROOT/Sources/XrayRustFFI/include" \
  "$MOBILE_ROOT/android/xraymobile/src/main/cpp/xray_mobile_jni.cpp" \
  -L "$native_dir" -lxray_ffi -Wl,-rpath,"$native_dir" \
  -o "$test_root/libxray_mobile_jni.$extension"

"$MOBILE_ROOT/android/gradlew" -p "$MOBILE_ROOT/android" \
  :xraymobile:testDebugUnitTest \
  "-PxrayNativeImportLibraryPath=$test_root:$native_dir" \
  "-PxrayNativeImportFixtureRoot=$core" \
  --tests '*XrayProfileImporter*' --tests '*XrayOutboundProbeNative*' \
  --tests '*XrayHysteriaNative*' --tests '*XrayTunAdmissionNative*' \
  --tests '*SdkTransportOptionsNative*' \
  --dependency-verification strict --no-daemon --console=plain "$@"

# A successful Gradle task alone is insufficient: native tests may be skipped
# when their opt-in property is lost. Only the external Hysteria fixture is optional.
python3 - "$MOBILE_ROOT/android/xraymobile/build/test-results/testDebugUnitTest" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

required = {"XrayProfileImporterNativeTest", "XrayOutboundProbeNativeTest",
            "XrayHysteriaNativeTest", "XrayTunAdmissionNativeTest",
            "SdkTransportOptionsNativeTest"}
seen = set()
passed = skipped = 0
for path in Path(sys.argv[1]).glob("TEST-*.xml"):
    suite = ET.parse(path).getroot()
    name = suite.attrib["name"].rsplit(".", 1)[-1]
    if name not in required:
        continue
    cases = suite.findall("testcase")
    assert cases, f"empty native test suite: {name}"
    seen.add(name)
    for case in cases:
        assert case.find("failure") is None and case.find("error") is None, case.attrib
        if case.find("skipped") is not None:
            assert name == "XrayHysteriaNativeTest" and case.attrib["name"] == "liveRebindRetainsTcpThroughActualJni", case.attrib
            assert not os.environ.get("XRAY_TEST_HYSTERIA_CONFIG"), "configured live fixture was skipped"
            skipped += 1
        else:
            passed += 1
assert seen == required, f"missing native suites: {required - seen}"
print(f"Verified host JNI native tests: {passed} passed, {skipped} optional live-fixture skips")
PY
