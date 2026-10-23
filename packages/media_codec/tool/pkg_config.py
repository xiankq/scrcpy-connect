#!/usr/bin/env python3
"""Resolve only our pinned static dependencies, delegate system packages.

The rootless Linux sysroot must apply to libva but must not rewrite the absolute
workspace prefix of dav1d. This also avoids requiring pkg-config on Windows.
This is intentionally not a general .pc parser: versions come from our locks.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def main():
    arguments = sys.argv[1:]
    if arguments == ["--version"]:
        print("media-codec-pinned-dependencies-1")
        return 0
    packages = [item for item in arguments if not item.startswith("--")]
    query = " ".join(packages)
    pattern = r"(dav1d|ffnvcodec)(?:\s*(>=|<=|=|>|<)\s*([\d.]+))?"
    matches = list(re.finditer(pattern, query))
    if not matches or re.sub(pattern, "", query).strip():
        command = os.environ.get("MC_SYSTEM_PKG_CONFIG")
        return subprocess.call([command, *arguments]) if command else 1
    name = matches[0][1]
    if any(match[1] != name for match in matches):
        return 1
    root = Path(__file__).resolve().parents[1]
    lock = json.loads((root / "third_party" / ("dav1d.lock.json" if name == "dav1d" else
                                              "nv-codec-headers.lock.json")).read_text())
    version = lock["version"].lstrip("n")
    for match in matches:
        _, operator, requested = match.groups()
        if not requested:
            continue
        actual = tuple(map(int, version.split(".")))
        wanted = tuple(map(int, requested.split(".")))
        size = max(len(actual), len(wanted))
        actual += (0,) * (size - len(actual))
        wanted += (0,) * (size - len(wanted))
        if not {">=": actual >= wanted, "<=": actual <= wanted, "=": actual == wanted,
                ">": actual > wanted, "<": actual < wanted}[operator]:
            return 1
    prefix = Path(os.environ["MC_FFMPEG_PREFIX"])
    if "--modversion" in arguments:
        print(version)
    if "--variable=includedir" in arguments:
        print((prefix / "include").as_posix())
    if "--cflags" in arguments or "--cflags-only-I" in arguments:
        print("-I" + (prefix / "include").as_posix())
    if "--libs" in arguments and name == "dav1d":
        # Threads are provided by the host runtime / FFmpeg's pthread detection.
        print("-L" + (prefix / "lib").as_posix() + " -ldav1d")
    return 0


if __name__ == "__main__":
    sys.exit(main())
