"""Regressions for generated-source and embedded/native-artifact delivery gates."""
import importlib.util
import json
from pathlib import Path
import re
import shutil
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


generate = load("generate", ROOT / "tool/generate.py")
companion = load("companion_build", ROOT / "servers/companion/build.py")
host = load("build_host", ROOT / "tool/build_host.py")


class DeliveryTests(unittest.TestCase):
    def test_each_frb_output_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            before, after = root / "before", root / "after"
            for name in generate.OUTPUTS:
                for tree in (before, after):
                    path = tree / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("generated")
            generate.compare_outputs(before, after)
            for name in generate.OUTPUTS:
                path = after / name
                path.write_text("stale")
                with self.assertRaisesRegex(ValueError, re.escape(name)):
                    generate.compare_outputs(before, after)
                path.unlink()
                with self.assertRaises(ValueError):
                    generate.compare_outputs(before, after)
                path.write_text("generated")

    def test_frb_rust_format_uses_workspace_edition_without_touching_other_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / generate.OUTPUTS[0]
            output.parent.mkdir(parents=True)
            output.write_text("use example::{transform_result_dco, Lifetimeable, Lockable};\n")
            sibling = output.with_name("lib.rs")
            sibling.write_text("pub fn unrelated( ) { }\n")
            original = sibling.read_bytes()
            generate.format_frb_rust(root)
            self.assertEqual(output.read_text(),
                             "use example::{Lifetimeable, Lockable, transform_result_dco};\n")
            self.assertEqual(sibling.read_bytes(), original)
            first = output.read_bytes()
            generate.format_frb_rust(root)
            self.assertEqual(output.read_bytes(), first)

    def test_companion_source_and_artifact_drift_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "companion"
            shutil.copytree(companion.HERE, root)
            companion.verify_manifest(root)
            source = next(root.glob("src/**/*.java"))
            original = source.read_bytes()
            source.write_bytes(original + b"\n// changed")
            with self.assertRaisesRegex(ValueError, "sources"):
                companion.verify_manifest(root)
            source.write_bytes(original)
            jar = root / "companion.jar"
            jar.write_bytes(jar.read_bytes() + b"corrupt")
            with self.assertRaisesRegex(ValueError, "JAR"):
                companion.verify_manifest(root)

    def test_mdk_pins_match_official_release_receipt_and_apple(self):
        base = ROOT / "third_party/fvp"
        receipt = json.loads((base / "cmake/mdk-release.json").read_text())
        cmake = (base / "cmake/mdk-release.cmake").read_text()
        for name, digest in receipt["archives"].items():
            key = name.replace(".", "_").replace("-", "_")
            self.assertIn(f'set(FVP_MDK_SHA256_{key} "{digest}")', cmake)
            self.assertRegex(digest, r"^[a-f0-9]{64}$")
        swift = (base / "darwin/fvp/Package.swift").read_text()
        self.assertIn(receipt["archives"]["mdk-sdk-apple.zip"], swift)
        for podspec in base.glob("*/fvp.podspec"):
            self.assertIn("'mdk', '= 0.39.0'", podspec.read_text())

    def test_windows_bundle_requires_valid_packaged_rust_library(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory)
            header = bytearray(72)
            header[:2] = b"MZ"
            struct.pack_into("<I", header, 60, 64)
            header[64:68] = b"PE\0\0"
            struct.pack_into("<H", header, 68, 0x8664)
            for name in ("scrcpy_connect.exe", "flutter_windows.dll", "interop_bridge.dll", "mdk.dll", "ffmpeg-9.dll"):
                (bundle / name).write_bytes(header)
            assets = bundle / "data/flutter_assets/AssetManifest.bin"
            assets.parent.mkdir(parents=True)
            assets.write_bytes(b"assets")
            host.verify_windows(bundle)
            (bundle / "interop_bridge.dll").unlink()
            with self.assertRaisesRegex(ValueError, "interop_bridge"):
                host.verify_windows(bundle)
            struct.pack_into("<H", header, 68, 0x14c)
            (bundle / "interop_bridge.dll").write_bytes(header)
            with self.assertRaisesRegex(ValueError, "interop_bridge"):
                host.verify_windows(bundle)
