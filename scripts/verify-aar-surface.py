#!/usr/bin/env python3
"""Fail closed unless an AAR contains exactly the release-owned surface."""

from __future__ import annotations

import stat
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path, PurePosixPath


ABIS = ("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
LIBRARIES = ("libxray_ffi.so", "libxray_mobile_jni.so")
EXPECTED_FILES = {
    "AndroidManifest.xml",
    "R.txt",
    "classes.jar",
    "proguard.txt",
    "META-INF/com/android/build/gradle/aar-metadata.properties",
    *(f"jni/{abi}/{library}" for abi in ABIS for library in LIBRARIES),
}
EXPECTED_DIRS = {
    f"{parent}/"
    for name in EXPECTED_FILES
    for parent in list(PurePosixPath(name).parents)[:-1]
}
ANDROID_NAME = "{http://schemas.android.com/apk/res/android}name"
EXPECTED_PERMISSIONS = {
    "android.permission.INTERNET",
    "android.permission.FOREGROUND_SERVICE",
}
EXPECTED_PACKAGE = "org.xrayrust.mobile"
EXPECTED_MIN_SDK = "24"
MAX_AAR_BYTES = 256 * 1024 * 1024
MAX_EXPANDED_BYTES = 512 * 1024 * 1024


def fail(message: str) -> "None":
    raise ValueError(message)


def validate_name(name: str) -> None:
    if not name or "\\" in name or name.startswith("/"):
        fail(f"unsafe ZIP entry name: {name!r}")
    parts = name.removesuffix("/").split("/")
    if any(part in {"", ".", ".."} for part in parts):
        fail(f"unsafe ZIP entry name: {name!r}")


def validate_manifest(data: bytes) -> None:
    if len(data) > 64 * 1024:
        fail("AndroidManifest.xml exceeds 64 KiB")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        fail(f"invalid AndroidManifest.xml: {error}")
    if root.tag != "manifest":
        fail("AndroidManifest.xml root is not <manifest>")
    if root.attrib != {"package": EXPECTED_PACKAGE}:
        fail(f"manifest attributes differ: {root.attrib!r}")

    permissions: list[str] = []
    uses_sdk_count = 0
    for child in root:
        if child.tag == "uses-permission":
            name = child.attrib.get(ANDROID_NAME)
            if set(child.attrib) != {ANDROID_NAME} or not name:
                fail("uses-permission must contain only android:name")
            permissions.append(name)
        elif child.tag == "uses-sdk":
            uses_sdk_count += 1
            if uses_sdk_count > 1:
                fail("AndroidManifest.xml has duplicate <uses-sdk>")
            if child.attrib != {f"{{http://schemas.android.com/apk/res/android}}minSdkVersion": EXPECTED_MIN_SDK}:
                fail(f"uses-sdk attributes differ: {child.attrib!r}")
        else:
            fail(f"unexpected manifest element: <{child.tag}>")

    if len(permissions) != len(set(permissions)):
        fail("AndroidManifest.xml has duplicate permissions")
    if set(permissions) != EXPECTED_PERMISSIONS:
        fail(
            "manifest permissions differ: "
            f"actual={sorted(permissions)!r} expected={sorted(EXPECTED_PERMISSIONS)!r}"
        )
    if uses_sdk_count != 1:
        fail("AndroidManifest.xml must contain exactly one <uses-sdk>")


def validate(path: str) -> None:
    if Path(path).stat().st_size > MAX_AAR_BYTES:
        fail("AAR exceeds 256 MiB")
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if len(names) != len(set(names)):
            duplicates = sorted({name for name in names if names.count(name) > 1})
            fail(f"duplicate ZIP entries: {duplicates!r}")

        expanded_bytes = 0
        for info in infos:
            validate_name(info.filename)
            mode = info.external_attr >> 16
            if mode and stat.S_ISLNK(mode):
                fail(f"symbolic link is forbidden in AAR: {info.filename}")
            if info.flag_bits & 0x1:
                fail(f"encrypted ZIP entry is forbidden: {info.filename}")
            expanded_bytes += info.file_size
            if expanded_bytes > MAX_EXPANDED_BYTES:
                fail("AAR expands beyond 512 MiB")
            if info.file_size > 1024 * 1024 and info.compress_size * 200 < info.file_size:
                fail(f"unsafe AAR compression ratio: {info.filename}")

        files = {name for name in names if not name.endswith("/")}
        directories = {name for name in names if name.endswith("/")}
        if files != EXPECTED_FILES:
            fail(
                "AAR file allowlist differs: "
                f"missing={sorted(EXPECTED_FILES - files)!r} "
                f"unexpected={sorted(files - EXPECTED_FILES)!r}"
            )
        unexpected_dirs = directories - EXPECTED_DIRS
        if unexpected_dirs:
            fail(f"unexpected AAR directories: {sorted(unexpected_dirs)!r}")

        validate_manifest(archive.read("AndroidManifest.xml"))


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <aar>", file=sys.stderr)
        return 2
    try:
        validate(sys.argv[1])
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
