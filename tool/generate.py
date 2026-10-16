#!/usr/bin/env python3
"""Generate the Dart workspace; --check verifies outputs without changing them."""

import argparse
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    command = ["dart", "run", "build_runner", "build", "--workspace"]
    if args.check:
        command.append("--only-check")
    return subprocess.run(command, cwd=ROOT / "apps/connect").returncode


if __name__ == "__main__":
    sys.exit(main())
