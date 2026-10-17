#!/usr/bin/env python3
"""Local signing, single-ABI builds, and independent APK validation."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps/connect"
ANDROID = APP / "android"
PLATFORMS = {
    "arm64": ("android-arm64", ["arm64-v8a"]),
    "arm": ("android-arm", ["armeabi-v7a"]),
    "x64": ("android-x64", ["x86_64"]),
    "universal": ("android-arm,android-arm64,android-x64", ["armeabi-v7a", "arm64-v8a", "x86_64"]),
}


def run(command, **kwargs):
    return subprocess.run([str(arg) for arg in command], check=True, **kwargs)


def initialize_signing():
    properties = ANDROID / "key.properties"
    if properties.exists():
        print("Keeping existing android/key.properties and signing identity.")
        return
    key = ANDROID / "keystores/connect-local-release.jks"
    if key.exists():
        raise ValueError("Signing key already exists; restore its key.properties. It will not be replaced.")
    keytool = shutil.which("keytool")
    if keytool is None:
        raise ValueError("keytool is required (install JDK 21 and add its bin directory to PATH).")
    key.parent.mkdir(parents=True, exist_ok=True)
    password = secrets.token_urlsafe(32)
    environment = {**os.environ, "CONNECT_LOCAL_KEY_PASSWORD": password}
    # keytool creates the keystore itself; a private temporary directory keeps
    # a partial or failed generation from replacing an existing signing identity.
    with tempfile.TemporaryDirectory(prefix="signing-", dir=key.parent) as work:
        candidate = Path(work) / key.name
        run([
            keytool, "-genkeypair", "-keystore", candidate, "-storetype", "JKS",
            "-alias", "interconnect", "-keyalg", "RSA", "-keysize", "3072",
            "-validity", "10000", "-dname", "CN=Interconnect Local Release,O=Interconnect",
            "-storepass:env", "CONNECT_LOCAL_KEY_PASSWORD",
            "-keypass:env", "CONNECT_LOCAL_KEY_PASSWORD",
        ], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        # Exclusive creation also protects against another initializer racing us.
        key_created = False
        try:
            with key.open("xb") as destination:
                key_created = True
                os.chmod(key, 0o600)
                destination.write(candidate.read_bytes())
        except BaseException:
            if key_created:
                key.unlink()
            raise
    properties_created = False
    try:
        with properties.open("x", encoding="utf-8") as destination:
            properties_created = True
            os.chmod(properties, 0o600)
            destination.write(
                "# Machine-local sideload signing identity. Keep both files backed up privately.\n"
                "storeFile=keystores/connect-local-release.jks\n"
                "keyAlias=interconnect\n"
                f"storePassword={password}\nkeyPassword={password}\n"
            )
    except BaseException:
        # This invocation created key exclusively, so it owns only this file.
        if properties_created:
            properties.unlink()
        key.unlink()
        raise
    print("Created a persistent local release signing identity; credentials are Git-ignored.")
    print("For distribution, replace key.properties with your chosen release keystore.")


def sdk_tools():
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if sdk is None:
        candidates = [Path.home() / "Android/Sdk", Path.home() / "Library/Android/sdk"]
        if os.environ.get("LOCALAPPDATA"):
            candidates.append(Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk")
        sdk = next((str(path) for path in candidates if path.is_dir()), None)
    if sdk is None:
        raise ValueError("Set ANDROID_HOME to the Android SDK directory.")
    candidates = list((Path(sdk) / "build-tools").glob("*"))
    def version(path):
        try:
            return tuple(int(part) for part in path.name.split("."))
        except ValueError:
            return ()
    suffix = ".bat" if os.name == "nt" else ""
    for path in sorted(candidates, key=version, reverse=True):
        signer = path / f"apksigner{suffix}"
        aapt = path / ("aapt2.exe" if os.name == "nt" else "aapt2")
        align = path / ("zipalign.exe" if os.name == "nt" else "zipalign")
        if signer.is_file() and aapt.is_file() and align.is_file():
            return signer, aapt, align
    raise ValueError("Install Android SDK build-tools (apksigner, aapt2, zipalign).")


def verify_apk(apk, expected_abis=None):
    apk = apk.resolve(strict=True)
    signer, aapt, align = sdk_tools()
    with zipfile.ZipFile(apk) as archive:
        bad_entry = archive.testzip()
        if bad_entry:
            raise ValueError(f"Corrupt APK entry: {bad_entry}")
        names = archive.namelist()
        for required in ("AndroidManifest.xml", "classes.dex", "resources.arsc"):
            if required not in names:
                raise ValueError(f"APK lacks {required}; use the final APK, not an intermediate ZIP.")
        abis = sorted({name.split("/")[1] for name in names if name.startswith("lib/") and name.endswith(".so")})
        if expected_abis is not None and set(abis) != set(expected_abis):
            raise ValueError(f"APK ABIs {abis} differ from requested {expected_abis}.")
        headers = {"armeabi-v7a": (1, 40), "arm64-v8a": (2, 183), "x86_64": (2, 62)}
        for abi in abis:
            for library in ("libflutter.so", "libapp.so", "libinterop_bridge.so"):
                name = f"lib/{abi}/{library}"
                if library == "libapp.so" and name not in names:
                    if "assets/flutter_assets/kernel_blob.bin" in names:
                        continue  # Debug uses a Dart kernel instead of AOT.
                    raise ValueError(f"Release APK lacks its Dart AOT library: {name}")
                with archive.open(name) as binary:
                    header = binary.read(20)
                elf_class, machine = headers[abi]
                if (len(header) != 20 or header[:4] != b"\x7fELF" or header[4:6] != bytes([elf_class, 1])
                        or int.from_bytes(header[18:20], "little") != machine):
                    raise ValueError(f"Invalid packaged native architecture: {name}")
    signature = run([signer, "verify", "--verbose", "--print-certs", apk], capture_output=True, text=True).stdout
    run([align, "-c", "-P", "16", "-v", "4", apk], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    badging = run([aapt, "dump", "badging", apk], capture_output=True, text=True).stdout
    package = next((line for line in badging.splitlines() if line.startswith("package: ")), None)
    if package is None or "name=''" in package:
        raise ValueError("The final APK has no readable package identity.")
    if not any(line.startswith("launchable-activity:") for line in badging.splitlines()):
        raise ValueError("The final APK has no launchable activity.")
    with apk.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    receipt = {
        "apk": str(apk), "bytes": apk.stat().st_size, "sha256": digest,
        "abis": abis, "package": package, "signatureVerified": True,
        "zipIntegrityVerified": True, "zipAlignmentVerified": True,
        "zipNativePageAlignmentBytes": 16384,
        "signerCertificates": [line for line in signature.splitlines() if "certificate SHA-256 digest:" in line],
    }
    print(json.dumps(receipt, ensure_ascii=False, indent=2))
    return receipt


def build_apk(args):
    if args.mode == "release" and not (ANDROID / "key.properties").exists():
        raise ValueError("No release signing identity. Run: python3 tool/android.py init-signing")
    flutter = shutil.which("flutter")
    if flutter is None:
        raise ValueError("Add Flutter to PATH.")
    platforms, abis = PLATFORMS[args.abi]
    command = [flutter, "build", "apk", f"--{args.mode}", "--target-platform", platforms]
    if args.no_pub:
        command.append("--no-pub")
    started = time.monotonic()
    run(command, cwd=APP)
    elapsed = time.monotonic() - started
    apk = APP / f"build/app/outputs/flutter-apk/app-{args.mode}.apk"
    verify_apk(apk, abis)
    print(f"Build wall time: {elapsed:.2f}s. Reuse .dart_tool/hooks_runner and Gradle caches between builds.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init-signing", help="Create a private stable local sideload identity, without replacing an existing key.")
    build = commands.add_parser("build", help="Build and verify; defaults to release for an arm64 phone.")
    build.add_argument("--abi", choices=PLATFORMS, default="arm64")
    build.add_argument("--mode", choices=("debug", "release"), default="release")
    build.add_argument("--no-pub", action="store_true", help="Skip dependency resolution after a successful pub get.")
    verify = commands.add_parser("verify", help="Check a final APK's ZIP, manifest, signature and native binaries.")
    verify.add_argument("apk", type=Path)
    args = parser.parse_args()
    if args.command == "init-signing":
        initialize_signing()
    elif args.command == "build":
        build_apk(args)
    else:
        verify_apk(args.apk)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        # Never echo keytool output or command environments: they can contain
        # local credentials. APK tool failures contain no key material.
        print(f"Android packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
