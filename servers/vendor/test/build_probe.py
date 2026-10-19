#!/usr/bin/env python3
"""Build an API-21 app_process probe; writes only the requested output JAR."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--sdk", default=os.environ.get("ANDROID_HOME"))
    args = parser.parse_args()
    if not args.sdk or not os.environ.get("JAVA_HOME"):
        parser.error("Set ANDROID_HOME (or --sdk) and JAVA_HOME")
    sdk = Path(args.sdk).resolve()
    java = Path(os.environ["JAVA_HOME"]).resolve()
    source = Path(__file__).with_name("ScrcpyApi21Probe.java")
    android_jar = sdk / "platforms/android-36/android.jar"
    with tempfile.TemporaryDirectory(prefix="scrcpy-api21-probe-") as directory:
        root = Path(directory)
        subprocess.run([str(java / "bin/javac"), "-source", "8", "-target", "8", "-classpath", str(android_jar), "-d", str(root), str(source)], check=True)
        subprocess.run([str(sdk / "build-tools/36.0.0/d8"), "--min-api", "21", "--lib", str(android_jar), "--output", str(root)] + [str(p) for p in sorted(root.glob("*.class"))], check=True)
        with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_STORED) as archive:
            info = zipfile.ZipInfo("classes.dex", (1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            archive.writestr(info, (root / "classes.dex").read_bytes())
    print(args.output.resolve())


if __name__ == "__main__":
    main()
