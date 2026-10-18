#!/usr/bin/env python3
"""Run the offline native dependency gates using CMake or the Android SDK copy."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    executable = shutil.which("cmake")
    suffix = ".exe" if os.name == "nt" else ""
    if executable is None:
        sdk = Path(os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or Path.home() / "Android/Sdk")
        def version(path):
            return tuple(int(part) for part in path.parent.parent.name.split(".") if part.isdigit())
        candidates = sorted(sdk.glob(f"cmake/*/bin/cmake{suffix}"), key=version, reverse=True)
        executable = str(candidates[0]) if candidates else None
    if executable is None:
        print("Install CMake (including CTest), or Android SDK CMake", file=sys.stderr)
        return 1
    ctest = Path(executable).with_name("ctest" + suffix)
    try:
        with tempfile.TemporaryDirectory(prefix="interop-fvp-cmake-") as directory:
            subprocess.run([executable, "-S", str(ROOT / "third_party/fvp/cmake/tests"), "-B", directory], check=True)
            subprocess.run([str(ctest), "--test-dir", directory, "--output-on-failure"], check=True)
        return 0
    except (OSError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
