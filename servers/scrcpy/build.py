#!/usr/bin/env python3
"""Rebuild the controlled-device scrcpy capture extension from pinned sources."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile


ROOT = Path(__file__).resolve().parent
VERSION = "5.0.1"
COMMIT = "a60891aea193d92e7e5c3942700eca63f9d19a5f"
URL = "https://codeload.github.com/Genymobile/scrcpy/tar.gz/refs/tags/v5.0.1"
SOURCE_SHA = "a24b996ac23d0f674d3237c00b39a97829d8acbe9e1657a6c216fd51ea488ee5"
PATCH = ROOT / "patches/0001-cooperative-capture-pause.patch"
BUILD = ROOT / ".build"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(*args, cwd=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Rebuild and compare without replacing committed artifacts")
    options = parser.parse_args()
    sdk = Path(os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or Path.home() / "Android/Sdk")
    platform = sdk / "platforms/android-36"
    tools = sdk / "build-tools/36.0.0"
    for required in [platform / "android.jar", platform / "framework.aidl", tools / "aidl", tools / "d8"]:
        if not required.exists():
            raise SystemExit(f"Missing Android SDK 36 prerequisite: {required}")
    BUILD.mkdir(exist_ok=True)
    archive = BUILD / "scrcpy-v5.0.1.tar.gz"
    if not archive.exists():
        with urllib.request.urlopen(URL) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
    if sha(archive) != SOURCE_SHA:
        raise SystemExit(f"Upstream archive SHA mismatch: {archive}")
    source = BUILD / "scrcpy-5.0.1"
    if source.exists():
        shutil.rmtree(source)
    with tarfile.open(archive) as downloaded:
        downloaded.extractall(BUILD, filter="data")
    run("patch", "--batch", "--fuzz=0", "-p1", "-i", PATCH, cwd=source)

    classes = BUILD / "classes"
    generated = BUILD / "generated"
    dex = BUILD / "dex"
    for directory in [classes, generated, dex]:
        if directory.exists():
            shutil.rmtree(directory)
        directory.mkdir()
    config = generated / "com/genymobile/scrcpy/BuildConfig.java"
    config.parent.mkdir(parents=True)
    config.write_text('package com.genymobile.scrcpy;\npublic final class BuildConfig {\n'
                      '    public static final boolean DEBUG = false;\n'
                      f'    public static final String VERSION_NAME = "{VERSION}";\n}}\n')
    server = source / "server"
    aidl = server / "src/main/aidl"
    run(tools / "aidl", f"-o{generated}", "-I.", "android/content/IOnPrimaryClipChangedListener.aidl", cwd=aidl)
    run(tools / "aidl", f"-o{generated}", "-I.", "-p", platform / "framework.aidl", "android/view/IDisplayWindowListener.aidl", cwd=aidl)
    java_sources = sorted((server / "src/main/java").rglob("*.java")) + sorted(generated.rglob("*.java"))
    run("javac", "-encoding", "UTF-8", "-bootclasspath", platform / "android.jar",
        "-cp", tools / "core-lambda-stubs.jar", "-d", classes, "-source", "1.8", "-target", "1.8", *java_sources)
    run(tools / "d8", "--min-api", "21", "--classpath", platform / "android.jar", "--output", dex,
        *sorted(classes.rglob("*.class")))

    artifact = (BUILD / "rebuilt-server.jar") if options.check else (ROOT / "interop-scrcpy-server.jar")
    # Fixed metadata makes the output reproducible with the same JDK/SDK inputs.
    with zipfile.ZipFile(artifact, "w", compression=zipfile.ZIP_STORED) as jar:
        for file in sorted(dex.glob("*.dex")):
            entry = zipfile.ZipInfo(file.name, (1980, 1, 1, 0, 0, 0))
            entry.external_attr = 0o644 << 16
            jar.writestr(entry, file.read_bytes())
    digest = sha(artifact)
    manifest = {
        "upstreamVersion": VERSION,
        "upstreamCommit": COMMIT,
        "sourceUrl": URL,
        "sourceSha256": SOURCE_SHA,
        "patchSha256": sha(PATCH),
        "serverSha256": digest,
        "controlExtension": {"type": 128, "payload": "sequence:u64be,paused:u8(0|1)", "ack": "ACK_CLIPBOARD(sequence)"},
        "androidPlatform": 36,
        "androidBuildTools": "36.0.0",
        "javaCompiler": subprocess.check_output(["javac", "-version"], text=True, stderr=subprocess.STDOUT).strip(),
    }
    if options.check:
        recorded = json.loads((ROOT / "manifest.json").read_text())
        # Compiler identity is diagnostic. The rebuilt bytes must still match
        # exactly, including when another JDK patch version is installed.
        for key, value in manifest.items():
            if key != "javaCompiler" and recorded.get(key) != value:
                raise SystemExit(f"Recorded server manifest differs at {key}")
        if sha(ROOT / "interop-scrcpy-server.jar") != digest or (ROOT / "interop-scrcpy-server.sha256").read_text().strip() != digest:
            raise SystemExit("Committed capture server does not match its pinned sources")
        print(f"Verified reproducible capture server: {digest}")
        return
    (ROOT / "interop-scrcpy-server.sha256").write_text(digest + "\n")
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built {artifact}: {digest}")


if __name__ == "__main__":
    main()
