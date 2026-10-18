#!/usr/bin/env python3
"""Build a host application and verify the native libraries in its final bundle."""
import argparse
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT


def pe_machine(path):
    with path.open("rb") as stream:
        if stream.read(2) != b"MZ":
            raise ValueError(f"Invalid PE file: {path}")
        stream.seek(0x3C)
        offset = struct.unpack("<I", stream.read(4))[0]
        stream.seek(offset)
        if stream.read(4) != b"PE\0\0":
            raise ValueError(f"Invalid PE signature: {path}")
        return struct.unpack("<H", stream.read(2))[0]


def verify_windows(bundle):
    for name in ("scrcpy_connect.exe", "flutter_windows.dll", "interop_bridge.dll", "mdk.dll", "ffmpeg-9.dll"):
        files = list(bundle.rglob(name))
        if len(files) != 1 or pe_machine(files[0]) != 0x8664:
            raise ValueError(f"Final Windows bundle lacks one x64 {name}")
    if not (bundle / "data/flutter_assets/AssetManifest.bin").is_file():
        raise ValueError("Windows bundle lacks Flutter assets")


def verify_apple(bundle, platform):
    contents = bundle / "Contents" if platform == "macos" else bundle
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    executable = contents / "MacOS" / info["CFBundleExecutable"] if platform == "macos" else contents / info["CFBundleExecutable"]
    subprocess.run(["xcrun", "lipo", "-verify_arch", "arm64", str(executable)], check=True)
    frameworks = list(contents.rglob("FlutterMacOS" if platform == "macos" else "Flutter"))
    if not any(path.is_file() for path in frameworks):
        raise ValueError("Apple bundle lacks its Flutter engine")
    rust = [path for path in contents.rglob("*") if path.is_file()
            and "interop_bridge" in path.name and path.suffix not in (".plist", ".json", ".h")]
    if not rust:
        raise ValueError("Apple bundle lacks its Rust interop library")
    for library in rust:
        subprocess.run(["xcrun", "lipo", "-verify_arch", "arm64", str(library)], check=True)
    if not any(path.is_file() for path in contents.rglob("mdk")):
        raise ValueError("Apple bundle lacks its MDK framework")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("windows", "ios", "macos"))
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    try:
        if not args.verify_only:
            command = [shutil.which("flutter") or "flutter", "build", args.platform, "--release", "--no-pub"]
            if args.platform == "ios":
                command.append("--no-codesign")
            subprocess.run(command, cwd=APP, check=True)
        if args.platform == "windows":
            bundle = APP / "build/windows/x64/runner/Release"
            verify_windows(bundle)
        else:
            directory = APP / ("build/ios/iphoneos" if args.platform == "ios" else "build/macos/Build/Products/Release")
            bundles = list(directory.glob("*.app"))
            if len(bundles) != 1:
                raise ValueError(f"Expected one final application in {directory}")
            verify_apple(bundles[0], args.platform)
        artifacts = APP / "build/verified"
        artifacts.mkdir(parents=True, exist_ok=True)
        if args.platform == "windows":
            shutil.make_archive(str(artifacts / "windows-release"), "zip", bundle)
        else:
            # Preserve executable modes and framework symlinks across artifact upload.
            with tarfile.open(artifacts / f"{args.platform}-release.tar.gz", "w:gz") as archive:
                archive.add(bundles[0], arcname=bundles[0].name)
        print(f"PASS: final {args.platform} application, Flutter engine, Rust library and MDK")
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
