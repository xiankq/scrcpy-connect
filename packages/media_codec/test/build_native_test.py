import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class AppleNativeBuildTest(unittest.TestCase):
    def test_cocoapods_link_builds_from_the_owned_rust_directory(self):
        repository = Path(__file__).resolve().parents[3]
        script = repository / "packages/media_codec/darwin/build_native.sh"
        for platform, sdk in (("macos", "macosx"), ("ios", "iphoneos")):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory(
                prefix="media codec build "
            ) as temporary:
                fixture = Path(temporary).resolve()
                plugin = fixture / "Flutter/ephemeral/.symlinks/plugins/media_codec"
                plugin.parent.mkdir(parents=True)
                plugin.symlink_to(
                    repository / "packages/media_codec", target_is_directory=True
                )
                binaries = fixture / "bin"
                binaries.mkdir()
                xcrun = binaries / "xcrun"
                xcrun.write_text("#!/bin/sh\nprintf '%s\\n' /test-sdk\n")
                xcrun.chmod(0o755)
                cargo = binaries / "cargo"
                cargo.write_text(
                    '#!/bin/sh\nset -eu\npwd -P > "$MEDIA_CODEC_TEST_WORKDIR"\n'
                )
                cargo.chmod(0o755)
                ffmpeg = fixture / "ffmpeg"
                (ffmpeg / "lib").mkdir(parents=True)
                working_directory = fixture / "cargo-working-directory"
                environment = {
                    **os.environ,
                    "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
                    "CARGO_HOME": str(fixture),
                    "PODS_TARGET_SRCROOT": str(plugin / platform),
                    "PODS_CONFIGURATION_BUILD_DIR": str(fixture / "products"),
                    "PLATFORM_NAME": sdk,
                    "ARCHS": "arm64",
                    "MEDIA_CODEC_FFMPEG_ROOT": str(ffmpeg),
                    "MEDIA_CODEC_TEST_WORKDIR": str(working_directory),
                }
                result = subprocess.run(
                    ["/bin/sh", str(script), platform],
                    env=environment,
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(
                    Path(working_directory.read_text().strip()),
                    repository / "rust/media_codec",
                )


if __name__ == "__main__":
    unittest.main()
