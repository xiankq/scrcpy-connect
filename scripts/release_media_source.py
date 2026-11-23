#!/usr/bin/env python3
"""Collect the pinned media sources used to build the release."""
import argparse
from pathlib import Path
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packages/media_codec/tool"))

from build_ffmpeg import DEPENDENCIES, LOCK, source_archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    cache = ROOT / ".dart_tool/media_codec"
    sources = {"FFmpeg": LOCK, **DEPENDENCIES}
    for name, lock in sources.items():
        source_archive(name, lock, cache)

    with tarfile.open(args.output, "w:gz") as bundle:
        for name, lock in sources.items():
            archive = f"{name}-{lock['revision']}.tar.gz"
            bundle.add(cache / "source" / archive, arcname=f"upstream/{archive}")
        bundle.add(ROOT / "packages/media_codec/third_party", arcname="third_party")
        bundle.add(ROOT / "packages/media_codec/tool", arcname="tool",
                   filter=lambda member: None if "__pycache__" in member.name else member)
    print(f"Collected pinned media sources in {args.output}")


if __name__ == "__main__":
    main()
