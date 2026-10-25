"""Exercise dependency build ownership without compiling third-party sources."""
from argparse import Namespace
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stderr
from io import StringIO
import os
from pathlib import Path
import platform
import tempfile
import threading
import unittest
from unittest.mock import patch

import build_ffmpeg


class BuildOwnershipTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.cache = self.root / "cache"
        self.cache.mkdir()
        self.sources = {}
        self.rendezvous = None
        self.lock_work = False
        for name, licenses in {
            "FFmpeg": ["COPYING.LGPLv2.1", "LICENSE.md"],
            "dav1d": ["COPYING"],
            "nv-codec-headers": [],
        }.items():
            source = self.root / name
            source.mkdir()
            for license in licenses:
                (source / license).write_text("fixture license")
            self.sources[name] = source
        (self.sources["nv-codec-headers"] / "include/ffnvcodec").mkdir(parents=True)
        for replacement in [
            patch.object(build_ffmpeg, "source_archive", side_effect=lambda name, *_: self.sources[name]),
            patch.object(build_ffmpeg, "patched_ffmpeg_source", side_effect=lambda _, source: source),
            patch.object(build_ffmpeg, "meson_command", return_value=["meson"]),
            patch.object(build_ffmpeg, "run", side_effect=self.run_build_step),
        ]:
            replacement.start()
            self.addCleanup(replacement.stop)

    def run_build_step(self, command, cwd, environment, log):
        if command[0] == "meson" and command[1] == "setup" and self.rendezvous:
            prefix = next(str(arg) for arg in command if str(arg).startswith("--prefix="))
            marker = cwd / Path(prefix.removeprefix("--prefix=")).name
            marker.write_text("in-flight build")
            self.rendezvous.wait()
            self.assertTrue(marker.exists(), "another prefix deleted active build work")
        if len(command) > 1 and str(command[1]).endswith("/configure"):
            (cwd / "config.h").write_text("fixture configuration")
            (cwd / "config_components.h").write_text("fixture components")
        if command == ["make", "install"]:
            prefix = Path(environment["MC_FFMPEG_PREFIX"])
            (prefix / "include/libavcodec").mkdir(parents=True)
            (prefix / "include/libavcodec/avcodec.h").write_text("fixture header")
            (prefix / "lib").mkdir()
            for library in ["avcodec", "avutil", "swscale", "dav1d"]:
                (prefix / f"lib/lib{library}.a").write_bytes(b"fixture library")
            if self.lock_work:
                work = cwd.parent
                work.chmod(0o500)
                self.addCleanup(lambda: work.chmod(0o700) if work.exists() else None)

    def build(self, prefix):
        args = Namespace(
            platform="linux", arch="arm64" if platform.machine().lower() in
            {"aarch64", "arm64"} else "x64", api=24, sdk="", jobs=1,
        )
        with build_ffmpeg.prefix_lock(prefix):
            build_ffmpeg.build(args, self.cache, prefix)

    def test_separate_install_prefixes_cannot_delete_each_others_work(self):
        self.rendezvous = threading.Barrier(2, timeout=5)
        with ThreadPoolExecutor(max_workers=2) as workers:
            futures = [workers.submit(self.build, self.root / name)
                       for name in ["device", "simulator"]]
            for future in futures:
                future.result(timeout=15)
        for name in ["device", "simulator"]:
            self.assertTrue((self.root / name / "media-codec-build.json").is_file())
        self.assertEqual(list((self.cache / "work").iterdir()), [])
        self.assertEqual(len(list((self.cache / "logs").glob("*.log"))), 2)

    @unittest.skipUnless(os.name == "posix" and os.geteuid() != 0,
                         "requires an unprivileged process with directory permissions")
    def test_real_cleanup_permission_error_preserves_success_and_cache_hit_retries_only_its_work(self):
        self.lock_work = True
        prefix = self.root / "installed"
        warnings = StringIO()
        with redirect_stderr(warnings):
            self.build(prefix)
        self.assertIn("Warning: keeping build work", warnings.getvalue())
        receipt = (prefix / "media-codec-build.json").read_bytes()
        work = next((self.cache / "work").iterdir())
        other_work = self.cache / "work/another-prefix-in-flight"
        other_work.mkdir()
        (other_work / "owned").write_text("another build")
        with patch.object(build_ffmpeg, "run", side_effect=AssertionError("unexpected rebuild")):
            with redirect_stderr(warnings):
                self.build(prefix)
            self.assertEqual(warnings.getvalue().count("Warning: keeping build work"), 2)
            work.chmod(0o700)
            self.build(prefix)
        self.assertFalse(work.exists())
        self.assertEqual((prefix / "media-codec-build.json").read_bytes(), receipt)
        self.assertEqual((other_work / "owned").read_text(), "another build")

    def test_original_build_failure_keeps_its_error_and_work_without_a_success_receipt(self):
        failure = OSError(5, "fixture compiler I/O failed")
        prefix = self.root / "failed-install"
        with patch.object(build_ffmpeg, "run", side_effect=failure):
            with self.assertRaises(OSError) as caught:
                self.build(prefix)
        self.assertIs(caught.exception, failure)
        self.assertFalse((prefix / "media-codec-build.json").exists())
        self.assertEqual(len(list((self.cache / "work").iterdir())), 1)


if __name__ == "__main__":
    unittest.main()
