#!/usr/bin/env python3
"""Protect existing source/artifact directories from experimental rebuilds."""

import importlib.util
import hashlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile


ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("capture_build", ROOT / "build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class IsolatedBuildTests(unittest.TestCase):
    def reject(self, arguments, marker=None):
        before = marker.read_bytes() if marker is not None else None
        result = subprocess.run([sys.executable, str(ROOT / "build.py"), *arguments],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        if marker is not None:
            self.assertEqual(marker.read_bytes(), before)
        return result.stderr

    def test_candidate_cannot_use_production_output(self):
        error = self.reject(["--candidate", "bounded-input"])
        self.assertIn("requires --output-dir", error)

    def test_existing_external_evidence_is_never_rebuilt(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "interop-scrcpy-server.jar"
            marker.write_bytes(b"existing evidence must survive")
            error = self.reject(["--candidate", "bounded-input", "--output-dir", directory], marker)
            self.assertIn("must not already exist", error)
            self.assertEqual(sorted(p.name for p in Path(directory).iterdir()), [marker.name])

    def test_any_repository_output_is_rejected_before_modification(self):
        for directory in (ROOT, ROOT / ".build", ROOT.parents[1] / "new-candidate-output"):
            with self.subTest(directory=directory):
                error = self.reject(["--candidate", "bounded-input", "--output-dir", str(directory)])
                self.assertIn("outside the repository", error)

    def test_reproducibility_check_has_no_external_override(self):
        with tempfile.TemporaryDirectory() as directory:
            error = self.reject(["--check", "--output-dir", str(Path(directory) / "fresh")])
            self.assertIn("cannot be combined", error)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_new_external_candidate_is_selected_without_creating_it(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "fresh"
            selected = build.select_output(SimpleNamespace(candidate="bounded-input", output_dir=destination, check=False))
            self.assertEqual(selected, (destination, destination))
            self.assertFalse(destination.exists())

    def test_regular_build_preserves_the_existing_layout(self):
        selected = build.select_output(SimpleNamespace(candidate=None, output_dir=None, check=False))
        self.assertEqual(selected, (ROOT / ".build", ROOT))

    def test_fresh_archive_download_keeps_the_external_artifact_destination(self):
        # Exercise the actual download/output control flow without a network,
        # compiler or SDK dependency. This does not validate Java compilation.
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            sdk = base / "sdk"
            for name in ("platforms/android-36/android.jar", "platforms/android-36/framework.aidl",
                         "build-tools/36.0.0/aidl", "build-tools/36.0.0/d8"):
                file = sdk / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.touch()
            destination = base / "fresh"
            archive = b"pinned source download fixture"

            def compiler(*args, **kwargs):
                if str(args[0]).endswith("/d8"):
                    (destination / "dex/classes.dex").write_bytes(b"dex fixture")

            with patch.dict("os.environ", {"ANDROID_HOME": str(sdk)}), \
                    patch.object(sys, "argv", [str(ROOT / "build.py"), "--output-dir", str(destination)]), \
                    patch.object(build, "BUILD", base / "missing-cache"), \
                    patch.object(build, "SOURCE_SHA", hashlib.sha256(archive).hexdigest()), \
                    patch.object(build.urllib.request, "urlopen", return_value=io.BytesIO(archive)), \
                    patch.object(build.tarfile, "open"), patch.object(build, "run", side_effect=compiler), \
                    patch.object(build.subprocess, "check_output", return_value="javac fixture"), \
                    patch("sys.stdout", new_callable=io.StringIO):
                build.main()
            self.assertEqual((destination / "scrcpy-v5.0.1.tar.gz").read_bytes(), archive)
            with zipfile.ZipFile(destination / "interop-scrcpy-server.jar") as artifact:
                self.assertEqual(artifact.read("classes.dex"), b"dex fixture")
            self.assertTrue((destination / "manifest.json").is_file())


if __name__ == "__main__":
    unittest.main()
