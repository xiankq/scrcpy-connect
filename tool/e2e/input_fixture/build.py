#!/usr/bin/env python3
"""Build the independent input receiver APK using only the installed Android SDK.

No installation, device access, product dependency, or downloaded build system.
Generated classes, signing key and APK stay in the chosen temporary output path.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True, timeout=120)


def newest(directory, prefix=""):
    candidates = [p for p in directory.iterdir() if p.is_dir() and p.name.startswith(prefix)]
    return max(candidates, key=lambda p: tuple(int(x) for x in p.name.removeprefix(prefix).split(".") if x.isdigit()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, default=Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or Path.home() / "Android/Sdk"))
    parser.add_argument("--output", type=Path, default=Path(tempfile.gettempdir()) / "connect-input-fixture")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    build_tools = newest(args.sdk / "build-tools")
    android_jar = newest(args.sdk / "platforms", "android-") / "android.jar"
    keystore = output / "fixture-test-only.keystore"
    if not keystore.exists():
        run("keytool", "-genkeypair", "-keystore", keystore, "-storepass", "android", "-keypass", "android", "-alias", "inputfixture", "-keyalg", "RSA", "-keysize", "2048", "-validity", "3650", "-dname", "CN=InteropInputFixtureTestOnly", "-noprompt")
    with tempfile.TemporaryDirectory(prefix="compile-", dir=output) as work_path:
        work = Path(work_path)
        generated, classes, dex = [work / name for name in ("generated", "classes", "dex")]
        for directory in (generated, classes, dex):
            directory.mkdir()
        run(build_tools / "aapt2", "compile", "--dir", root / "res", "-o", work / "resources.zip")
        run(build_tools / "aapt2", "link", "-I", android_jar, "--manifest", root / "AndroidManifest.xml", "--java", generated, "-o", work / "base.apk", work / "resources.zip")
        run("javac", "-source", "8", "-target", "8", "-classpath", android_jar, "-d", classes, *root.glob("src/**/*.java"), *generated.glob("**/*.java"))
        run(build_tools / "d8", "--lib", android_jar, "--min-api", "23", "--output", dex, *classes.glob("**/*.class"))
        unsigned = work / "unsigned.apk"
        shutil.copyfile(work / "base.apk", unsigned)
        with zipfile.ZipFile(unsigned, "a") as apk:
            apk.write(dex / "classes.dex", "classes.dex", compress_type=zipfile.ZIP_STORED)
        run(build_tools / "zipalign", "-p", "4", unsigned, work / "aligned.apk")
        apk = output / "input-fixture.apk"
        run(build_tools / "apksigner", "sign", "--ks", keystore, "--ks-key-alias", "inputfixture", "--ks-pass", "pass:android", "--key-pass", "pass:android", "--out", apk, work / "aligned.apk")
        run(build_tools / "apksigner", "verify", "--verbose", apk)
        print(apk)


if __name__ == "__main__":
    main()
