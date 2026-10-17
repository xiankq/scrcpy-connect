#!/usr/bin/env python3
"""Build a test-only API36 Sharesheet recipient, with all artifacts below /tmp.

This script does not invoke adb, Gradle, Flutter, or change device state.
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, default=Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or Path.home() / "Android/Sdk"))
    parser.add_argument("--output", type=Path, default=Path("/tmp/connect-content-delivery-fixture"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    output = args.output.resolve()
    if Path("/tmp") not in output.parents:
        parser.error("--output must be a directory below /tmp")
    output.mkdir(parents=True, exist_ok=True)
    build_tools = args.sdk / "build-tools/36.0.0"
    android_jar = args.sdk / "platforms/android-36/android.jar"
    keystore = output / "fixture-test-only.keystore"
    if not keystore.exists():
        run("keytool", "-genkeypair", "-keystore", keystore, "-storepass", "android", "-keypass", "android", "-alias", "deliveryfixture", "-keyalg", "RSA", "-keysize", "2048", "-validity", "3650", "-dname", "CN=DeliveryFixtureTestOnly", "-noprompt")
    with tempfile.TemporaryDirectory(prefix="compile-", dir=output) as work_path:
        work = Path(work_path)
        classes, dex = work / "classes", work / "dex"
        classes.mkdir()
        dex.mkdir()
        run(build_tools / "aapt2", "link", "-I", android_jar, "--manifest", root / "AndroidManifest.xml", "-o", work / "base.apk")
        run("javac", "--release", "8", "-encoding", "UTF-8", "-classpath", android_jar, "-d", classes, *sorted(root.glob("src/**/*.java")))
        run(build_tools / "d8", "--lib", android_jar, "--min-api", "36", "--output", dex, *sorted(classes.glob("**/*.class")))
        unsigned = work / "unsigned.apk"
        shutil.copyfile(work / "base.apk", unsigned)
        with zipfile.ZipFile(unsigned, "a") as apk:
            apk.write(dex / "classes.dex", "classes.dex", compress_type=zipfile.ZIP_STORED)
        run(build_tools / "zipalign", "-p", "4", unsigned, work / "aligned.apk")
        apk = output / "content-delivery-fixture.apk"
        run(build_tools / "apksigner", "sign", "--ks", keystore, "--ks-key-alias", "deliveryfixture", "--ks-pass", "pass:android", "--key-pass", "pass:android", "--out", apk, work / "aligned.apk")
        run(build_tools / "apksigner", "verify", "--verbose", apk)
        print(apk)


if __name__ == "__main__":
    main()
