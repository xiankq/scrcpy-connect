#!/usr/bin/env python3
"""Run the pause gate and control-wire checks without an emulator."""

from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / ".build"
TEST_CLASSES = BUILD / "test-classes"
TEST_CLASSES.mkdir(exist_ok=True)
CLASSES = BUILD / "classes"
GATE = BUILD / "scrcpy-5.0.1/server/src/main/java/com/genymobile/scrcpy/video/CaptureControl.java"
if not GATE.exists():
    raise SystemExit("Run build.py first")
subprocess.run(["javac", "-cp", str(CLASSES), "-d", str(TEST_CLASSES), str(GATE),
                *[str(p) for p in sorted((ROOT / "tests").rglob("*.java"))]], check=True)
subprocess.run(["java", "-ea", "-cp", f"{TEST_CLASSES}:{CLASSES}", "CapturePauseTest"], check=True, timeout=15)
