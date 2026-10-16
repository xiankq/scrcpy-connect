#!/usr/bin/env python3
"""Prove CI runs Riverpod's analyzer plugin, not only Flutter's basic lints."""

from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
SOURCE = """import 'package:hooks_riverpod/hooks_riverpod.dart';

class InvalidNotifier extends Notifier<int> {
  @override
  int build() => 0;

  int get outsideState => 1;
}
"""


def main():
    # A system-temp file would not inherit the workspace's plugin or imports.
    with tempfile.TemporaryDirectory(prefix="lint_smoke_", dir=ROOT / "apps/connect/test") as directory:
        fixture = Path(directory) / "lint_smoke.dart"
        fixture.write_text(SOURCE, encoding="utf-8")
        result = subprocess.run(
            ["dart", "analyze", "--fatal-infos", str(fixture)],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if "avoid_public_notifier_properties" not in result.stdout.lower():
            print(result.stdout, file=sys.stderr)
            print(f"Riverpod plugin did not report its intentional violation (exit {result.returncode}).", file=sys.stderr)
            return 1
        print("Riverpod analyzer plugin detected its intentional violation.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
