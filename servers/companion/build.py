#!/usr/bin/env python3
"""Build the companion DEX JAR deterministically, or verify it without writes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
TOOLS = {"androidPlatform": "36", "buildTools": "36.0.0", "javaRelease": 8, "minApi": 21}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs(root=HERE):
    return {str(path.relative_to(root)): digest(path)
            for path in sorted([root / "build.py", root / "build.sh", *root.glob("src/**/*.java")])}


def verify_manifest(root=HERE):
    manifest = json.loads((root / "manifest.json").read_text())
    if manifest["tools"] != TOOLS or manifest["sources"] != inputs(root):
        raise ValueError("Companion sources or build tools changed; rebuild servers/companion/build.py")
    jar = root / "companion.jar"
    if manifest["artifact"] != {"sha256": digest(jar), "size": jar.stat().st_size}:
        raise ValueError("Companion JAR differs from its build manifest")


def build(destination):
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or Path.home() / "Android/Sdk")
    java = Path(os.environ["JAVA_HOME"]) / "bin" if os.environ.get("JAVA_HOME") else Path(shutil.which("javac") or "/usr/lib/jvm/java-21-openjdk-amd64/bin/javac").parent
    suffix = ".exe" if os.name == "nt" else ""
    javac = java / ("javac" + suffix)
    version = subprocess.check_output([str(javac), "-version"], stderr=subprocess.STDOUT, text=True)
    if not version.startswith("javac 21."):
        raise ValueError("JDK 21 is required for reproducible companion bytecode")
    with tempfile.TemporaryDirectory(prefix="companion-") as directory:
        work = Path(directory)
        classes, dex = work / "classes", work / "dex"
        classes.mkdir()
        dex.mkdir()
        android = sdk / "platforms/android-36/android.jar"
        subprocess.run([str(javac), "--release", "8", "-encoding", "UTF-8", "-cp", str(android), "-d", str(classes), *map(str, sorted(HERE.glob("src/**/*.java")))], check=True)
        d8 = sdk / ("build-tools/36.0.0/d8.bat" if os.name == "nt" else "build-tools/36.0.0/d8")
        subprocess.run([str(d8), "--min-api", "21", "--lib", str(android), "--output", str(dex), *map(str, sorted(classes.rglob("*.class")))], check=True)
        # Match jar's manifest and fixed timestamps, independent of filesystem
        # ordering, locale, file modes, compression and the host ZIP writer.
        with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_STORED) as archive:
            for name, data in (("META-INF/", b""), ("META-INF/MANIFEST.MF", b"Manifest-Version: 1.0\r\nCreated-By: 21 (Interop companion)\r\n\r\n"), ("classes.dex", (dex / "classes.dex").read_bytes())):
                info = zipfile.ZipInfo(name, (2026, 10, 16, 0, 0, 0))
                info.create_system = 0
                info.external_attr = 0x10 if name.endswith("/") else 0x20
                archive.writestr(info, data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        if args.check:
            verify_manifest()
        with tempfile.TemporaryDirectory(prefix="companion-output-") as directory:
            candidate = Path(directory) / "companion.jar"
            build(candidate)
            if args.check:
                if candidate.read_bytes() != (HERE / "companion.jar").read_bytes():
                    raise ValueError("Companion JAR is stale; run python3 servers/companion/build.py")
                print("PASS: companion source manifest and deterministic DEX JAR")
            else:
                shutil.copyfile(candidate, HERE / "companion.jar")
                manifest = {"tools": TOOLS, "sources": inputs(), "artifact": {"sha256": digest(candidate), "size": candidate.stat().st_size}}
                (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        return 0
    except (ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
