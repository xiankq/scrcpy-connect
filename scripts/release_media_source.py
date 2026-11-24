#!/usr/bin/env python3
"""Collect the pinned media sources used to build the release."""
import argparse
from pathlib import Path
import sys
import tarfile

from src.packaging_log import stage

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packages/media_codec/tool"))

from build_ffmpeg import DEPENDENCIES, LOCK, verified_source_archive, verify_ffmpeg_patches


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    cache = ROOT / ".dart_tool/media_codec"
    with stage("Media source/verify inputs"):
        verify_ffmpeg_patches()
        archives = [verified_source_archive(name, lock, cache)
                    for name, lock in {"FFmpeg": LOCK, **DEPENDENCIES}.items()]

    with stage("Media source/archive"):
        # Upstream files are already compressed. Use a fast outer gzip for the sidecar files.
        with tarfile.open(args.output, "w:gz", compresslevel=1) as bundle:
            bundle.add(ROOT / "docs/releasing.md", arcname="REBUILD.md")
            for archive in archives:
                bundle.add(archive, arcname=f"upstream/{archive.name}")
            bundle.add(ROOT / "packages/media_codec/third_party", arcname="third_party")
            bundle.add(ROOT / "packages/media_codec/tool", arcname="tool",
                       filter=lambda member: None if "__pycache__" in member.name else member)


if __name__ == "__main__":
    main()
