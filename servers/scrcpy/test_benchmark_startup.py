"""Host-only checks: no ADB calls, builds, installation or emulator state changes."""

import importlib.util
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location("benchmark_startup", Path(__file__).with_name("benchmark_startup.py"))
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class FragmentedSocket:
    def __init__(self, data):
        self.data = data
        self.timeout = None

    def settimeout(self, timeout):
        self.timeout = timeout

    def recv(self, count):
        chunk, self.data = self.data[:min(count, 3)], self.data[min(count, 3):]
        return chunk


def packet(flags, payload):
    return struct.pack(">QI", flags, len(payload)) + payload


class StartupTests(unittest.TestCase):
    def wire(self, tail):
        return FragmentedSocket(b"fixture\0".ljust(64, b"\0") + b"h264" + tail)

    def session(self, width=576, height=1280):
        return struct.pack(">III", 1 << 31, width, height)

    def sample(self):
        return {"timestampsNs": {"spawn": 0}}

    def test_fragmented_wire_stops_at_first_media(self):
        wire = self.wire(self.session() + packet(1 << 62, b"config") +
                         packet((1 << 61) | 123, b"first") + packet(124, b"later"))
        sample = self.sample()
        encoded = benchmark.first_media(wire, sample, 0)
        self.assertEqual(encoded, b"configfirst")
        self.assertEqual(sample["session"], {"width": 576, "height": 1280})
        self.assertEqual(sample["firstMedia"]["ptsUs"], 123)
        self.assertTrue(sample["firstMedia"]["keyFrame"])
        self.assertEqual(wire.data, packet(124, b"later"))
        times = sample["timestampsNs"]
        self.assertLessEqual(times["header"], times["session"])
        self.assertLessEqual(times["session"], times["config"])
        self.assertLessEqual(times["config"], times["firstMedia"])

    def test_rejects_media_without_config(self):
        with self.assertRaisesRegex(ValueError, "without codec configuration"):
            benchmark.first_media(self.wire(self.session() + packet(0, b"x")), self.sample(), 0)

    def test_rejects_session_reset_before_first_media(self):
        with self.assertRaisesRegex(ValueError, "session reset"):
            benchmark.first_media(self.wire(self.session() * 2), self.sample(), 0)

    def test_rejects_oversize_payload_without_reading_it(self):
        header = struct.pack(">QI", 1 << 62, benchmark.MAX_PACKET + 1)
        with self.assertRaisesRegex(ValueError, "invalid packet length"):
            benchmark.first_media(self.wire(self.session() + header), self.sample(), 0)

    def test_absolute_deadline_bounds_slow_trickle_across_protocol_reads(self):
        now = [0.0]
        data = (b"fixture\0".ljust(64, b"\0") + b"h264" + self.session() +
                packet(1 << 62, b"config") + packet(1 << 61, b"first-media"))

        class TrickleSocket(FragmentedSocket):
            def recv(self, count):
                # Every byte arrives before the previous idle timeout, but the
                # complete stream exceeds the single startup deadline.
                now[0] += .01
                chunk, self.data = self.data[:1], self.data[1:]
                return chunk

        wire = TrickleSocket(data)
        sample = self.sample()
        with mock.patch.object(benchmark.time, "monotonic", side_effect=lambda: now[0]):
            with self.assertRaisesRegex(TimeoutError, "absolute server startup deadline"):
                benchmark.first_media(wire, sample, 0, deadline=1.0)
        self.assertIn("session", sample)
        self.assertNotIn("firstMedia", sample["timestampsNs"])
        self.assertTrue(wire.data)
        self.assertLess(now[0], 1.02)
        self.assertLess(wire.timeout, .02)

    def test_counts_native_allocations_only(self):
        logs = "\n".join([
            "10-18 09:00:00 1 2 D CCodec  : allocate(c2.android.avc.encoder)",
            "10-18 09:00:01 1 3 D CCodec  : allocate(c2.android.avc.encoder)",
            "10-18 09:00:02 1 4 D Other   : allocate(c2.android.avc.encoder)",
            "10-18 09:00:03 1 5 D CCodec  : allocate(c2.android.hevc.encoder)",
        ])
        self.assertEqual(len(benchmark.allocation_lines(logs)), 2)

    def test_matched_summary_uses_two_bracketing_baselines(self):
        samples = [{"complete": True, "label": label, "elapsedMs": {"firstMedia": value}}
                   for label, value in (("baseline-before", 100), ("candidate", 75), ("baseline-after", 120))]
        self.assertEqual(benchmark.summarize(samples)["medianCandidateMinusBaselineMs"], -35)

    def test_native_resolution_and_counter_oracle(self):
        ffmpeg = shutil.which("ffmpeg")
        fallback = Path("/tmp/connect-video-tools/imageio_ffmpeg/binaries/ffmpeg-linux-x86_64-v7.0.2")
        if not ffmpeg and fallback.is_file():
            ffmpeg = str(fallback)
        if not ffmpeg:
            self.skipTest("host ffmpeg unavailable")
        for color, matches in (("0x40c0ff", True), ("0xff4040", False)):
            with self.subTest(color=color), tempfile.TemporaryDirectory() as folder:
                encoded = subprocess.run(
                    [ffmpeg, "-nostdin", "-v", "error", "-f", "lavfi", "-i",
                     f"color=c={color}:s=64x128", "-frames:v", "1", "-c:v", "libx264",
                     "-threads", "1", "-f", "h264", "pipe:1"],
                    capture_output=True, check=True, timeout=20,
                ).stdout
                dimensions = {"width": 64, "height": 128}
                if matches:
                    oracle = benchmark.decode_first(ffmpeg, encoded, Path(folder), dimensions)
                    self.assertEqual(oracle["counter"], 0)
                    self.assertEqual(oracle["nativeHeight"], 128)
                    with self.assertRaisesRegex(ValueError, "native dimensions"):
                        benchmark.decode_first(ffmpeg, encoded, Path(folder), {"width": 128, "height": 64})
                else:
                    with self.assertRaisesRegex(ValueError, "counter 15"):
                        benchmark.decode_first(ffmpeg, encoded, Path(folder), dimensions)


if __name__ == "__main__":
    unittest.main()
