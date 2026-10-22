#!/usr/bin/env python3
"""Build the pinned, decode-only FFmpeg profile; never use a system FFmpeg.

The cache retains upstream archives and license text for source correspondence.
Only avcodec/avutil/swscale are linked; there is no avformat, protocol or player.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import urllib.request

PACKAGE = Path(__file__).resolve().parents[1]
WORKSPACE = PACKAGE.parents[1]
LOCK = json.loads((PACKAGE / "third_party/ffmpeg.lock.json").read_text())


def run(command, cwd, environment, log):
    with log.open("a", encoding="utf-8") as output:
        output.write("\n" + repr([str(x) for x in command]) + "\n")
        output.flush()
        result = subprocess.run([str(x) for x in command], cwd=cwd, env=environment,
                                stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text(errors="replace")[-16000:], flush=True)
        raise RuntimeError(f"Native dependency build failed; see {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["linux", "windows", "android", "macos", "ios"], required=True)
    parser.add_argument("--arch", default="x64", choices=["x64", "arm64", "arm"])
    parser.add_argument("--api", type=int, default=24)
    parser.add_argument("--sdk", default="")
    parser.add_argument("--ndk", default=os.environ.get("ANDROID_NDK_HOME", ""))
    parser.add_argument("--prefix", type=Path)
    parser.add_argument("--jobs", type=int, default=min(6, os.cpu_count() or 2))
    args = parser.parse_args()
    cache = WORKSPACE / ".dart_tool/media_codec"
    prefix = (args.prefix or cache / "ffmpeg" / f"{args.platform}-{args.arch}").resolve()
    prefix.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    options = ["--disable-everything", "--disable-autodetect", "--disable-programs", "--disable-doc",
               "--disable-debug", "--disable-network", "--disable-avformat", "--disable-avdevice",
               "--disable-avfilter", "--disable-swresample", "--enable-avcodec", "--enable-avutil",
               "--enable-swscale", "--enable-static", "--disable-shared", "--enable-pic",
               "--enable-decoder=h264,hevc,av1,vp8,vp9", "--enable-parser=h264,hevc,av1,vp8,vp9",
               "--enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,extract_extradata",
               "--disable-gpl", "--disable-nonfree", "--disable-version3", "--enable-optimizations"]
    # Keep SIMD and runtime CPU dispatch: smaller must not mean slower fallback.
    if args.platform == "linux":
        options += ["--enable-vaapi", "--enable-hwaccel=h264_vaapi,hevc_vaapi,av1_vaapi,vp8_vaapi,vp9_vaapi"]
    elif args.platform == "windows":
        options += ["--toolchain=msvc", "--enable-d3d11va",
                    "--enable-hwaccel=h264_d3d11va,hevc_d3d11va,av1_d3d11va,vp8_d3d11va,vp9_d3d11va"]
    elif args.platform == "android":
        ndk = Path(args.ndk)
        if not ndk.is_dir():
            raise RuntimeError("Pass --ndk pointing to an installed Android NDK")
        host = {"Linux": "linux-x86_64", "Darwin": "darwin-x86_64", "Windows": "windows-x86_64"}[platform.system()]
        tools = ndk / "toolchains/llvm/prebuilt" / host / "bin"
        triple = {"x64": "x86_64-linux-android", "arm64": "aarch64-linux-android", "arm": "armv7a-linux-androideabi"}[args.arch]
        arch = {"x64": "x86_64", "arm64": "aarch64", "arm": "arm"}[args.arch]
        executable = ".cmd" if os.name == "nt" else ""
        options += ["--target-os=android", "--enable-cross-compile", f"--arch={arch}",
                    f"--cc={tools / (triple + str(args.api) + '-clang' + executable)}",
                    f"--cxx={tools / (triple + str(args.api) + '-clang++' + executable)}",
                    f"--ar={tools / 'llvm-ar'}", f"--ranlib={tools / 'llvm-ranlib'}",
                    f"--strip={tools / 'llvm-strip'}", "--enable-jni", "--enable-mediacodec",
                    "--enable-decoder=h264_mediacodec,hevc_mediacodec,av1_mediacodec,vp8_mediacodec,vp9_mediacodec"]
    else:
        sdk = args.sdk or ("macosx" if args.platform == "macos" else "iphoneos")
        supported_sdks = {"macos": {"macosx"}, "ios": {"iphoneos", "iphonesimulator"}}
        if sdk not in supported_sdks[args.platform]:
            raise RuntimeError(f"Unsupported {args.platform} SDK: {sdk}")
        if args.arch == "arm" or (sdk == "iphoneos" and args.arch != "arm64"):
            raise RuntimeError(f"Unsupported Apple architecture {args.arch} for {sdk}")
        sysroot = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
        cc = subprocess.check_output(["xcrun", "--sdk", sdk, "--find", "clang"], text=True).strip()
        arch = "arm64" if args.arch == "arm64" else "x86_64"
        target = (f"{arch}-apple-macos10.15" if args.platform == "macos" else
                  f"{arch}-apple-ios13.0" + ("-simulator" if sdk == "iphonesimulator" else ""))
        options += ["--target-os=darwin", "--enable-cross-compile", f"--arch={arch}", f"--cc={cc}",
                    f"--sysroot={sysroot}", f"--extra-cflags=-target {target}", f"--extra-ldflags=-target {target}",
                    "--enable-videotoolbox", "--enable-hwaccel=h264_videotoolbox,hevc_videotoolbox,av1_videotoolbox,vp9_videotoolbox"]
    identity = {"revision": LOCK["revision"], "platform": args.platform, "arch": args.arch,
                "api": args.api if args.platform == "android" else None, "sdk": args.sdk, "options": options}
    receipt = prefix / "media-codec-build.json"
    if receipt.exists() and json.loads(receipt.read_text()) == identity and (prefix / "include/libavcodec/avcodec.h").exists():
        print(prefix, flush=True)
        return
    if shutil.disk_usage(cache).free < 3 * 1024**3:
        raise RuntimeError("Less than 3 GiB available; clean stale build outputs first")
    archives = cache / "source"
    archives.mkdir(parents=True, exist_ok=True)
    archive = archives / f"ffmpeg-{LOCK['revision']}.tar.gz"
    if not archive.exists():
        temporary = archive.with_suffix(".download")
        urllib.request.urlretrieve(LOCK["url"], temporary)
        temporary.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != LOCK["sha256"]:
        raise RuntimeError("Pinned FFmpeg source SHA-256 mismatch")
    source = archives / f"FFmpeg-{LOCK['revision']}"
    if not source.is_dir():
        with tarfile.open(archive) as compressed:
            compressed.extractall(archives, filter="data")
    work = cache / "work" / f"{args.platform}-{args.arch}"
    work.mkdir(parents=True, exist_ok=True)
    log = work / "build.log"
    log.write_text("")
    bash = shutil.which("bash") or ("C:/Program Files/Git/bin/bash.exe" if os.name == "nt" else "sh")
    print(f"Building decode-only FFmpeg for {args.platform}/{args.arch}; log: {log}", flush=True)
    run([bash, source / "configure", f"--prefix={prefix.as_posix()}"] + options, work, environment, log)
    run(["make", f"-j{args.jobs}"], work, environment, log)
    run(["make", "install"], work, environment, log)
    licenses = prefix / "share/media_codec"
    licenses.mkdir(parents=True, exist_ok=True)
    for name in ["COPYING.LGPLv2.1", "LICENSE.md"]:
        shutil.copy2(source / name, licenses / name)
    shutil.copy2(PACKAGE / "third_party/ffmpeg.lock.json", licenses / "ffmpeg-source.json")
    shutil.copy2(work / "config.h", licenses / "ffmpeg-config.h")
    shutil.copy2(work / "config_components.h", licenses / "ffmpeg-components.h")
    receipt.write_text(json.dumps(identity, indent=2) + "\n")
    print(prefix, flush=True)


if __name__ == "__main__":
    main()
