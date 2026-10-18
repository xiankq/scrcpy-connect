#!/usr/bin/env python3
"""Run the pause gate and control-wire checks without an emulator."""

from pathlib import Path
import argparse
import os
import subprocess

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--build-dir", type=Path, default=ROOT / ".build")
parser.add_argument("--candidate", choices=("bounded-input",))
options = parser.parse_args()
BUILD = options.build_dir.resolve()
TEST_CLASSES = BUILD / "test-classes"
CLASSES = BUILD / "classes"
SDK = Path(os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or Path.home() / "Android/Sdk")
ANDROID = SDK / "platforms/android-36/android.jar"
GATE = BUILD / "scrcpy-5.0.1/server/src/main/java/com/genymobile/scrcpy/video/CaptureControl.java"
if not GATE.exists():
    raise SystemExit("Run build.py first")
if options.candidate:
    import json
    import hashlib
    manifest = json.loads((BUILD / "manifest.json").read_text())
    patch = ROOT / "experiments" / options.candidate / "candidate.patch"
    expected = {"name": options.candidate, "patchSha256": hashlib.sha256(patch.read_bytes()).hexdigest()}
    if manifest.get("candidate") != expected:
        raise SystemExit("Candidate build does not match the current experimental patch")
TEST_CLASSES.mkdir(exist_ok=True)
subprocess.run(["javac", "-cp", f"{CLASSES}:{ANDROID}", "-d", str(TEST_CLASSES), str(GATE),
                *[str(p) for p in sorted((ROOT / "tests").rglob("*.java"))]], check=True)
subprocess.run(["java", "-ea", "-cp", f"{TEST_CLASSES}:{CLASSES}:{ANDROID}", "CapturePauseTest"], check=True, timeout=15)
if options.candidate:
    test = ROOT / "experiments" / options.candidate / "LatestInputWindowTest.java"
    subprocess.run(["javac", "-cp", str(CLASSES), "-d", str(TEST_CLASSES), str(test)], check=True)
    subprocess.run(["java", "-ea", "-cp", f"{TEST_CLASSES}:{CLASSES}", "LatestInputWindowTest"], check=True, timeout=15)
