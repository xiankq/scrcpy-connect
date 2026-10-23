#!/usr/bin/env python3
"""Build the pinned, decode-only FFmpeg profile; never use a system FFmpeg.

The cache retains upstream archives and license text for source correspondence.
Only avcodec/avutil/swscale are linked; there is no avformat, protocol or player.
"""
import argparse
from contextlib import contextmanager
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import shlex
import sys
import subprocess
import tarfile
import urllib.request

PACKAGE = Path(__file__).resolve().parents[1]
WORKSPACE = PACKAGE.parents[1]
LOCK = json.loads((PACKAGE / "third_party/ffmpeg.lock.json").read_text())
DEPENDENCIES = {name: json.loads((PACKAGE / f"third_party/{name}.lock.json").read_text())
                for name in ["dav1d", "nv-codec-headers"]}


def run(command, cwd, environment, log):
    with log.open("a", encoding="utf-8") as output:
        output.write("\n" + repr([str(x) for x in command]) + "\n")
        output.flush()
        result = subprocess.run([str(x) for x in command], cwd=cwd, env=environment,
                                stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text(errors="replace")[-16000:], flush=True)
        raise RuntimeError(f"Native dependency build failed; see {log}")



def windows_environment(environment, arch, cache):
    """Load MSVC and the Windows SDK without requiring a developer shell."""
    if os.name != "nt":
        raise RuntimeError("Windows FFmpeg must be built on Windows with MSVC")
    if shutil.which("cl.exe", path=environment.get("PATH")) and environment.get("WindowsSdkDir"):
        return environment
    vswhere = Path(environment.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Microsoft Visual Studio/Installer/vswhere.exe"
    if not vswhere.is_file():
        raise RuntimeError("Install Visual Studio Desktop development with C++ and a Windows SDK")
    installation = subprocess.check_output(
        [str(vswhere), "-latest", "-products", "*", "-requires",
         "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"],
        text=True).strip()
    vcvars = Path(installation) / "VC/Auxiliary/Build/vcvarsall.bat"
    if not vcvars.is_file():
        raise RuntimeError("Visual Studio C++ build tools are missing")
    target = {"x64": "x64", "arm64": "x64_arm64", "arm": "x64_arm"}[arch]
    cache.mkdir(parents=True, exist_ok=True)
    script = cache / ("msvc-environment-" + arch + ".cmd")
    script.write_text('@echo off\ncall "' + str(vcvars) + '" ' + target +
                      ' >nul\nif errorlevel 1 exit /b %errorlevel%\nset\n')
    comspec = environment.get("COMSPEC", "C:/Windows/System32/cmd.exe")
    command = '"' + comspec + '" /d /u /s /c ""' + str(script) + '""'
    try:
        output = subprocess.check_output(command, env=environment, encoding="utf-16le")
    finally:
        script.unlink(missing_ok=True)
    result = environment.copy()
    for line in output.splitlines():
        key, separator, value = line.partition("=")
        if separator and key:
            result[key] = value
    if not result.get("WindowsSdkDir"):
        raise RuntimeError("The Visual Studio installation lacks Windows SDK headers and libraries")
    return result



@contextmanager
def prefix_lock(prefix):
    """Serialize manual/CMake builds of one prefix, including cache replacement."""
    path = prefix.parent / (prefix.name + ".lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        if os.name == "nt":
            import msvcrt
            handle.seek(0)
            handle.write(b"\0")
            handle.flush()
            handle.seek(0)
            # LK_LOCK only retries ten seconds; dependency builds may take minutes.
            import time
            while True:
                try:
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                    break
                except OSError:
                    time.sleep(1)
            try:
                yield
            finally:
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(handle, fcntl.LOCK_UN)


def source_archive(name, lock, cache):
    with prefix_lock(cache / "source" / name):
        return extract_source_archive(name, lock, cache)


def extract_source_archive(name, lock, cache):
    archives = cache / "source"
    archives.mkdir(parents=True, exist_ok=True)
    archive = archives / f"{name}-{lock['revision']}.tar.gz"
    if not archive.is_file():
        temporary = archive.with_suffix(f".{os.getpid()}.download")
        try:
            urllib.request.urlretrieve(lock["url"], temporary)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != lock["sha256"]:
                raise RuntimeError(f"Pinned {name} source SHA-256 mismatch")
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != lock["sha256"]:
        raise RuntimeError(f"Pinned {name} source SHA-256 mismatch")
    directory = archives / f"{name}-{lock['revision']}"
    if not directory.is_dir():
        temporary = archives / f"extract-{name}-{os.getpid()}"
        temporary.mkdir()
        try:
            with tarfile.open(archive) as compressed:
                if sys.version_info >= (3, 12):
                    compressed.extractall(temporary, filter="data")
                else:
                    # Hash-pinned official archives; still reject absolute/traversal paths.
                    for member in compressed.getmembers():
                        if Path(member.name).is_absolute() or ".." in Path(member.name).parts:
                            raise RuntimeError("Unsafe source archive member")
                    compressed.extractall(temporary)
            extracted = list(temporary.iterdir())
            if len(extracted) != 1 or not extracted[0].is_dir():
                raise RuntimeError(f"Unexpected {name} archive layout")
            extracted[0].rename(directory)
        finally:
            shutil.rmtree(temporary, ignore_errors=True)
    return directory


def verify_ffmpeg_patches():
    patches = LOCK.get("patches", [])
    for patch in patches:
        path = PACKAGE / "third_party" / patch["file"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != patch["sha256"]:
            raise RuntimeError(f"FFmpeg patch SHA-256 mismatch: {path}")
    return patches


def patched_ffmpeg_source(cache, upstream):
    """Keep the hash-pinned upstream intact; patch a separate immutable tree."""
    patches = verify_ffmpeg_patches()
    if not patches:
        return upstream
    identity = {"upstream_sha256": LOCK["sha256"], "patches": patches}
    digest = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    destination = cache / "source" / f"FFmpeg-{LOCK['revision']}-patched-{digest[:16]}"
    with prefix_lock(destination):
        marker = destination / "media-codec-source.json"
        if destination.is_dir():
            if not marker.is_file() or json.loads(marker.read_text()) != identity:
                raise RuntimeError(f"Patched source identity mismatch: {destination}")
            return destination
        temporary = destination.with_name(destination.name + f"-{os.getpid()}.tmp")
        try:
            shutil.copytree(upstream, temporary)
            for patch in patches:
                path = (PACKAGE / "third_party" / patch["file"]).resolve()
                # git apply works without a .git directory on both Unix and
                # Windows and refuses mismatched hunks instead of fuzzy edits.
                subprocess.run(["git", "apply", "--check", str(path)], cwd=temporary, check=True)
                subprocess.run(["git", "apply", str(path)], cwd=temporary, check=True)
            (temporary / "media-codec-source.json").write_text(json.dumps(identity, indent=2) + "\n")
            temporary.rename(destination)
        finally:
            shutil.rmtree(temporary, ignore_errors=True)
    return destination


def meson_command(environment):
    executable = shutil.which("meson", path=environment.get("PATH"))
    if executable:
        return [executable]
    if importlib.util.find_spec("mesonbuild"):
        return [sys.executable, "-m", "mesonbuild.mesonmain"]
    raise RuntimeError("Install Meson >=0.54 and Ninja (python -m pip install meson ninja)")


def meson_value(value):
    return "'" + str(value).replace("\\", "/").replace("'", "\\'") + "'"


def cross_file(work, args, binaries, flags):
    family = {"x64": "x86_64", "arm64": "aarch64", "arm": "arm"}[args.arch]
    system = "android" if args.platform == "android" else "darwin"
    output = ["[binaries]"]
    output += [f"{name} = {meson_value(value)}" for name, value in binaries.items()]
    output += ["[host_machine]", f"system = '{system}'", f"cpu_family = '{family}'",
               f"cpu = '{family}'", "endian = 'little'", "[properties]", "needs_exe_wrapper = true",
               "[built-in options]", "c_args = [" + ", ".join(map(meson_value, flags)) + "]",
               "c_link_args = [" + ", ".join(map(meson_value, flags)) + "]"]
    path = work / "dav1d-cross.ini"
    path.write_text("\n".join(output) + "\n")
    return path


def build(args, cache, prefix):
    # Check source inputs even when a matching compiled prefix can be reused.
    verify_ffmpeg_patches()
    environment = os.environ.copy()
    options = ["--disable-everything", "--disable-autodetect", "--disable-programs", "--disable-doc",
               "--disable-debug", "--disable-network", "--disable-avformat", "--disable-avdevice",
               "--disable-avfilter", "--disable-swresample", "--enable-avcodec", "--enable-avutil",
               "--enable-swscale", "--enable-static", "--disable-shared", "--enable-pic",
               "--enable-decoder=h264,hevc,av1,vp8,vp9,libdav1d", "--enable-libdav1d",
               "--enable-parser=h264,hevc,av1,vp8,vp9",
               "--enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,extract_extradata",
               "--disable-gpl", "--disable-nonfree", "--disable-version3", "--enable-optimizations"]
    binaries, flags = {}, []
    # Keep SIMD and runtime CPU dispatch, including dav1d's 8/10/12-bit fallback.
    if args.platform == "linux":
        actual_arch = "arm64" if platform.machine().lower() in ["aarch64", "arm64"] else "x64"
        if args.arch != actual_arch:
            raise RuntimeError("Linux cross compilation requires an explicit sysroot/toolchain; build natively")
        options += ["--enable-vaapi", "--enable-libdrm", "--enable-ffnvcodec", "--enable-cuda", "--enable-nvdec",
                    "--enable-hwaccel=h264_vaapi,hevc_vaapi,av1_vaapi,vp8_vaapi,vp9_vaapi",
                    "--enable-hwaccel=h264_nvdec,hevc_nvdec,av1_nvdec,vp8_nvdec,vp9_nvdec"]
    elif args.platform == "windows":
        environment = windows_environment(environment, args.arch, cache)
        try:
            make_version = subprocess.check_output(["make", "--version"], env=environment, text=True)
        except (OSError, subprocess.CalledProcessError) as error:
            raise RuntimeError("Install MSYS2 make and add it, Git Bash, and NASM to PATH") from error
        if "msys" not in make_version.lower():
            raise RuntimeError("Use MSYS2 make; native Win32 GNU make cannot resolve Git Bash source paths")
        environment["CC"] = "cl"
        options += ["--toolchain=msvc", "--target-os=win32", "--extra-cflags=-MD",
                    "--arch=" + {"x64": "x86_64", "arm64": "aarch64", "arm": "arm"}[args.arch],
                    "--enable-d3d11va",
                    # *va2 exposes HW_DEVICE_CTX + AV_PIX_FMT_D3D11. This pinned
                    # upstream Makefile gates their shared dxva2_*.o on *va, so
                    # retain both variants. Upstream has no VP8 D3D11VA path.
                    "--enable-hwaccel=h264_d3d11va,h264_d3d11va2,hevc_d3d11va,hevc_d3d11va2,av1_d3d11va,av1_d3d11va2,vp9_d3d11va,vp9_d3d11va2"]
    elif args.platform == "android":
        ndk = Path(args.ndk)
        if not args.ndk or not ndk.is_dir():
            raise RuntimeError("Pass --ndk pointing to an installed Android NDK")
        host = {"Linux": "linux-x86_64", "Darwin": "darwin-x86_64", "Windows": "windows-x86_64"}[platform.system()]
        tools = ndk / "toolchains/llvm/prebuilt" / host / "bin"
        triple = {"x64": "x86_64-linux-android", "arm64": "aarch64-linux-android", "arm": "armv7a-linux-androideabi"}[args.arch]
        arch = {"x64": "x86_64", "arm64": "aarch64", "arm": "arm"}[args.arch]
        executable = ".cmd" if os.name == "nt" else ""
        binaries = {"c": tools / (triple + str(args.api) + "-clang" + executable),
                    "ar": tools / "llvm-ar", "strip": tools / "llvm-strip"}
        options += ["--target-os=android", "--enable-cross-compile", f"--arch={arch}",
                    f"--cc={binaries['c']}",
                    f"--cxx={tools / (triple + str(args.api) + '-clang++' + executable)}",
                    f"--ar={binaries['ar']}", f"--ranlib={tools / 'llvm-ranlib'}",
                    f"--strip={binaries['strip']}", "--enable-jni", "--enable-mediacodec",
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
        binaries = {"c": cc, "ar": subprocess.check_output(["xcrun", "--sdk", sdk, "--find", "ar"], text=True).strip(),
                    "strip": subprocess.check_output(["xcrun", "--sdk", sdk, "--find", "strip"], text=True).strip()}
        flags = ["-target", target, "-isysroot", sysroot]
        # CocoaPods inherits the target SDKROOT. FFmpeg's executable code
        # generators must still run on macOS, including iOS simulator builds.
        host_sysroot = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
        host_cc = subprocess.check_output(["xcrun", "--sdk", "macosx", "--find", "clang"], text=True).strip()
        host_arch = "arm64" if platform.machine() in {"arm64", "aarch64"} else "x86_64"
        host_flags = f"-target {host_arch}-apple-macos11.0 -isysroot {host_sysroot}"
        options += [f"--host-cc={host_cc}", f"--host-cflags={host_flags}", f"--host-ldflags={host_flags}"]
        options += ["--target-os=darwin", "--enable-cross-compile", f"--arch={arch}", f"--cc={cc}",
                    f"--sysroot={sysroot}", f"--extra-cflags=-target {target}", f"--extra-ldflags=-target {target}",
                    "--enable-videotoolbox", "--enable-hwaccel=h264_videotoolbox,hevc_videotoolbox,av1_videotoolbox,vp9_videotoolbox"]
    # FFmpeg's native av1 decoder is hardware-only; libdav1d is mandatory fallback.
    dependency_locks = {"dav1d": DEPENDENCIES["dav1d"]}
    if args.platform == "linux":
        dependency_locks["nv-codec-headers"] = DEPENDENCIES["nv-codec-headers"]
    identity = {"profile": 3, "revision": LOCK["revision"], "patches": LOCK.get("patches", []),
                "dependencies": dependency_locks,
                "platform": args.platform, "arch": args.arch,
                "api": args.api if args.platform == "android" else None, "sdk": args.sdk,
                "options": options.copy()}
    receipt = prefix / "media-codec-build.json"
    libraries = [prefix / "lib" / (f"{name}.lib" if args.platform == "windows" else f"lib{name}.a")
                 for name in ["avcodec", "avutil", "swscale", "dav1d"]]
    previous = json.loads(receipt.read_text()) if receipt.exists() else None
    if previous:
        # Profile 2 initially recorded the local pkg-config proxy command. Its
        # path is an invocation detail, not a codec capability/cache identity.
        previous["options"] = [option for option in previous.get("options", [])
                               if not option.startswith("--pkg-config")]
    if (previous == identity and
            (prefix / "include/libavcodec/avcodec.h").is_file() and all(p.is_file() for p in libraries)):
        if json.loads(receipt.read_text()) != identity:
            receipt.write_text(json.dumps(identity, indent=2) + "\n")
        print(prefix, flush=True)
        return
    cache.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(cache).free < 3 * 1024**3:
        raise RuntimeError("Less than 3 GiB available; clean stale build outputs first")
    source = patched_ffmpeg_source(cache, source_archive("FFmpeg", LOCK, cache))
    dav1d = source_archive("dav1d", DEPENDENCIES["dav1d"], cache)
    nvcodec = source_archive("nv-codec-headers", DEPENDENCIES["nv-codec-headers"], cache) if args.platform == "linux" else None
    work = cache / "work" / f"{args.platform}-{args.arch}"
    # Reconfigure alone leaves obsolete members in static archives. Rebuild the
    # derived output directories whenever the complete locked profile changes.
    shutil.rmtree(work, ignore_errors=True)
    shutil.rmtree(prefix, ignore_errors=True)
    work.mkdir(parents=True)
    prefix.mkdir(parents=True)
    log = work / "build.log"
    log.write_text("")
    print(f"Building decode-only FFmpeg + dav1d for {args.platform}/{args.arch}; log: {log}", flush=True)
    meson = meson_command(environment)
    setup = [*meson, "setup", work / "dav1d", dav1d, f"--prefix={prefix}", "--libdir=lib",
             "--default-library=static", "--buildtype=release", "-Db_staticpic=true", "-Db_ndebug=true",
             "-Denable_tools=false", "-Denable_tests=false", "-Denable_examples=false", "-Denable_docs=false"]
    if binaries:
        setup += ["--cross-file", cross_file(work, args, binaries, flags)]
    if args.platform == "windows":
        setup += ["-Db_vscrt=md"]
    run(setup, work, environment, log)
    run([*meson, "compile", "-C", work / "dav1d", "-j", str(args.jobs)], work, environment, log)
    run([*meson, "install", "-C", work / "dav1d", "--no-rebuild"], work, environment, log)
    if args.platform == "windows":
        # dav1d deliberately names its static MSVC archive libdav1d.a. Rust and
        # FFmpeg's MSVC linker adapter resolve -ldav1d as dav1d.lib instead.
        shutil.copy2(prefix / "lib/libdav1d.a", prefix / "lib/dav1d.lib")
    if nvcodec:
        shutil.copytree(nvcodec / "include/ffnvcodec", prefix / "include/ffnvcodec", dirs_exist_ok=True)
    environment["MC_FFMPEG_PREFIX"] = str(prefix)
    environment["MC_SYSTEM_PKG_CONFIG"] = shutil.which("pkg-config", path=environment.get("PATH")) or ""
    proxy = PACKAGE / "tool/pkg_config.py"
    options += ["--pkg-config=" + shlex.quote(Path(sys.executable).as_posix()) + " " + shlex.quote(proxy.as_posix()),
                "--pkg-config-flags=--static"]
    bash = shutil.which("bash", path=environment.get("PATH")) or ("C:/Program Files/Git/bin/bash.exe" if os.name == "nt" else "sh")
    ffmpeg_work = work / "ffmpeg"
    ffmpeg_work.mkdir()
    run([bash, source / "configure", f"--prefix={prefix.as_posix()}"] + options, ffmpeg_work, environment, log)
    run(["make", f"-j{args.jobs}"], ffmpeg_work, environment, log)
    run(["make", "install"], ffmpeg_work, environment, log)
    licenses = prefix / "share/media_codec"
    licenses.mkdir(parents=True, exist_ok=True)
    for name in ["COPYING.LGPLv2.1", "LICENSE.md"]:
        shutil.copy2(source / name, licenses / name)
    shutil.copy2(dav1d / "COPYING", licenses / "dav1d-COPYING")
    if nvcodec:
        # This upstream revision carries its notices in individual headers.
        notices = []
        for header in sorted((nvcodec / "include/ffnvcodec").glob("*.h")):
            text = header.read_text()
            notices.append(header.name + "\n" + text[:text.index("*/") + 2])
        (licenses / "nv-codec-headers-COPYING").write_text("\n\n".join(notices) + "\n")
    for name in ["ffmpeg", *dependency_locks]:
        shutil.copy2(PACKAGE / f"third_party/{name}.lock.json", licenses / f"{name}-source.json")
    for patch in LOCK.get("patches", []):
        output = licenses / patch["file"]
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(PACKAGE / "third_party" / patch["file"], output)
    shutil.copy2(ffmpeg_work / "config.h", licenses / "ffmpeg-config.h")
    shutil.copy2(ffmpeg_work / "config_components.h", licenses / "ffmpeg-components.h")
    receipt.write_text(json.dumps(identity, indent=2) + "\n")
    print(prefix, flush=True)


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
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    cache = WORKSPACE / ".dart_tool/media_codec"
    prefix = (args.prefix or cache / "ffmpeg" / f"{args.platform}-{args.arch}").resolve()
    with prefix_lock(prefix):
        build(args, cache, prefix)


if __name__ == "__main__":
    main()
