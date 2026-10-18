#!/usr/bin/env python3
"""Generate FRB and Dart outputs; --check regenerates FRB in an isolated tree."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
FRB_VERSION = "2.13.0"
OUTPUTS = (
    "crates/interop_bridge/src/frb_generated.rs",
    "packages/interop_bridge/lib/src/rust/api.dart",
    "packages/interop_bridge/lib/src/rust/frb_generated.dart",
    "packages/interop_bridge/lib/src/rust/frb_generated.io.dart",
)


def compare_outputs(root, generated):
    changed = [name for name in OUTPUTS
               if not (generated / name).is_file()
               or (root / name).read_bytes() != (generated / name).read_bytes()]
    if changed:
        raise ValueError("FRB generated files are stale; run python3 tool/generate.py:\n" + "\n".join(changed))


def format_frb_rust(root):
    # FRB 2.13 formats with the older Rust style. Normalize only its Rust
    # output to the workspace's edition so freshness and cargo fmt agree.
    formatter = shutil.which("rustfmt") or str(Path.home() / ".cargo/bin/rustfmt")
    output = root / OUTPUTS[0]
    formatted = subprocess.run(
        [formatter, "--edition", "2024", "--emit", "stdout"],
        input=output.read_bytes(), cwd=root, capture_output=True, check=True,
    ).stdout
    output.write_bytes(formatted)


def generate_frb(check):
    executable = shutil.which("flutter_rust_bridge_codegen")
    if executable is None:
        raise ValueError(f"Install flutter_rust_bridge_codegen {FRB_VERSION}: cargo install flutter_rust_bridge_codegen --version ={FRB_VERSION} --locked")
    version = subprocess.check_output([executable, "--version"], text=True).strip()
    if version != f"flutter_rust_bridge_codegen {FRB_VERSION}":
        raise ValueError(f"Expected flutter_rust_bridge_codegen {FRB_VERSION}, got {version}")
    command = [executable, "generate", "--config-file", "flutter_rust_bridge.yaml"]
    if not check:
        subprocess.run(command, cwd=ROOT, check=True)
        format_frb_rust(ROOT)
        return
    with tempfile.TemporaryDirectory(prefix="interop-frb-") as directory:
        isolated = Path(directory)
        # Copy input sources, never symlink them: codegen may add modules or
        # format sources. Cargo and Dart may also update local metadata.
        for name in ("Cargo.toml", "Cargo.lock", "rust-toolchain.toml",
                     "flutter_rust_bridge.yaml", "pubspec.yaml", "pubspec.lock"):
            shutil.copy2(ROOT / name, isolated / name)
        for name in ("crates", "packages", "apps", "servers", "protocol"):
            if not (ROOT / name).exists():
                continue
            shutil.copytree(ROOT / name, isolated / name,
                            ignore=shutil.ignore_patterns("target", "build", ".git", ".gradle", "ephemeral", "Pods", ".dart_tool"))
        (isolated / ".dart_tool").mkdir()
        for name in ("package_config.json", "package_graph.json"):
            source = ROOT / ".dart_tool" / name
            if source.exists():
                shutil.copy2(source, isolated / ".dart_tool" / name)
        environment = {**os.environ, "CARGO_TARGET_DIR": str(isolated / "target")}
        subprocess.run(command, cwd=isolated, env=environment, check=True)
        format_frb_rust(isolated)
        compare_outputs(ROOT, isolated)
    print("PASS: FRB 2.13.0 Rust/Dart generated outputs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        generate_frb(args.check)
        command = ["dart", "run", "build_runner", "build", "--workspace"]
        if args.check:
            command.append("--only-check")
        return subprocess.run(command, cwd=ROOT / "apps/connect").returncode
    except (ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
