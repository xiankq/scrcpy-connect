#!/usr/bin/env python3
"""Rebuild all checked-in Android helpers with pinned Rust and NDK versions."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CRATE = ROOT / "crates/android_helper"
CARGO = Path.home() / ".cargo/bin/cargo"
NDK = Path(os.environ.get("ANDROID_NDK_HOME", Path.home() / "Android/Sdk/ndk/28.2.13676358"))
TOOLCHAIN = NDK / "toolchains/llvm/prebuilt/linux-x86_64/bin"
TARGETS = {
    "arm64-v8a": ("aarch64-linux-android", "aarch64-linux-android21-clang"),
    "armeabi-v7a": ("armv7-linux-androideabi", "armv7a-linux-androideabi21-clang"),
    "x86_64": ("x86_64-linux-android", "x86_64-linux-android21-clang"),
    "x86": ("i686-linux-android", "i686-linux-android21-clang"),
}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    if "Pkg.Revision = 28.2.13676358" not in (NDK / "source.properties").read_text():
        raise SystemExit("NDK 28.2.13676358 is required")
    env = os.environ.copy()
    env["SOURCE_DATE_EPOCH"] = "0"
    env["CARGO_TARGET_DIR"] = str(CRATE / "target")
    env["RUSTFLAGS"] = " ".join([
        "--remap-path-prefix=" + str(ROOT) + "=/interop",
        "--remap-path-prefix=" + str(Path.home() / ".cargo") + "=/cargo",
        "-C", "link-arg=-Wl,--build-id=none",
    ])
    artifacts = []
    for abi, (target, linker) in TARGETS.items():
        env["CARGO_TARGET_" + target.upper().replace("-", "_") + "_LINKER"] = str(TOOLCHAIN / linker)
        subprocess.run(["rtk", "proxy", str(CARGO), "+1.99.1", "build", "--locked", "--release", "--manifest-path", str(CRATE / "Cargo.toml"), "--target", target], env=env, check=True)
        destination = HERE / "bin" / abi / "interop-rename"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(CRATE / "target" / target / "release/interop-android-helper", destination)
        destination.chmod(0o644)
        artifacts.append({"abi": abi, "target": target, "file": str(destination.relative_to(HERE)), "sha256": digest(destination), "size": destination.stat().st_size})
    manifest = {"protocol": 1, "rust": "1.99.1", "ndk": "28.2.13676358", "minAndroidApi": 21,
                "sources": {str(path.relative_to(ROOT)): digest(path) for path in [CRATE / "Cargo.toml", CRATE / "Cargo.lock", CRATE / "src/main.rs", HERE / "build.py"]}, "artifacts": artifacts}
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

if __name__ == "__main__":
    main()
