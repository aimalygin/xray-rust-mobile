#!/usr/bin/env python3
"""Verify JNI name-based callbacks in an actual minified consumer mapping."""

import re
import sys
from pathlib import Path


def verify(mapping: str) -> None:
    required = {
        "org.xrayrust.mobile.NativeTunAdmission":
            "boolean admitNative(long,int,byte[],int,byte[],int)",
        "org.xrayrust.mobile.NativeTunDiagnosticEvent":
            "void <init>(int,int,java.lang.String,java.lang.String,java.lang.String,long[])",
    }
    current = None
    found = set()
    for line in mapping.splitlines():
        if line.startswith("#"):
            continue
        if line and not line[0].isspace():
            current = None
            for name in required:
                if line.startswith(name + " -> "):
                    if line != f"{name} -> {name}:":
                        raise ValueError(f"JNI class renamed: {name}")
                    current = name
        elif current:
            # R8 may prefix/suffix signatures with source/target line ranges.
            member = re.sub(r"^\s*(?:\d+:\d+:)?", "", line)
            signature, separator, target = member.partition(" -> ")
            signature = re.sub(r":\d+(?::\d+)?$", "", signature)
            if separator and signature == required[current]:
                method = signature.split("(")[0].split()[-1]
                if target != method:
                    raise ValueError(f"JNI callback renamed: {current}.{method}")
                found.add(current)
    if missing := required.keys() - found:
        raise ValueError(f"JNI callbacks missing from minified consumer: {sorted(missing)}")


if __name__ == "__main__":
    verify(Path(sys.argv[1]).read_text())
    print("verified JNI callback names in minified consumer")
