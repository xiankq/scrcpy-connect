import unittest

from analyze_codec_trace import correlate


class CodecTraceTests(unittest.TestCase):
    def setUp(self):
        # Distinct host, target MONOTONIC and target BOOTTIME origins expose
        # accidental cross-clock subtraction even when every PTS matches.
        self.receipt = {
            "offsetLow": 1_000_000, "offsetHigh": 1_000_500,
            "frames": [{"pts": pts, "headerReadUs": pts + 9000} for pts in (1000, 2000, 3000)],
        }
        self.events = [{
            "ts": (1_000_000 + pts + 4000) * 1000, "dur": 100,
            "name": f"CCodecBufferChannel::onWorkDone(c2.android.avc.encoder#1@ts={pts})",
        } for pts in (1000, 2000, 3000)]
        self.clocks = [{"boot_ns": 1_000_000_000, "mono_ns": 0}]

    def test_keeps_three_clock_origins_separate(self):
        report = correlate(self.receipt, self.events, self.clocks, [])
        self.assertEqual(report["matched"], 3)
        self.assertEqual(report["allMedianUs"]["sourceToWorkDoneUs"], 4000)
        self.assertEqual(report["allMedianUs"]["workDoneToHeaderLowerUs"], 5000)
        self.assertEqual(report["allMedianUs"]["workDoneToHeaderUpperUs"], 5500)

    def test_lost_duplicate_and_unreceived_frames_cannot_make_complete_report(self):
        with self.assertRaisesRegex(ValueError, "data loss"):
            correlate(self.receipt, self.events, self.clocks, [{"name": "ftrace_cpu_overrun"}])
        with self.assertRaisesRegex(ValueError, "Duplicate CCodec"):
            correlate(self.receipt, self.events + self.events[:1], self.clocks, [])
        self.receipt["frames"].pop(1)
        with self.assertRaisesRegex(ValueError, "no matching"):
            correlate(self.receipt, self.events, self.clocks, [])

    def test_missing_clock_or_changed_offset_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "snapshots"):
            correlate(self.receipt, self.events, [], [])
        clocks = self.clocks + [{"boot_ns": 1_002_000_000, "mono_ns": 0}]
        with self.assertRaisesRegex(ValueError, "snapshots"):
            correlate(self.receipt, self.events, clocks, [])


if __name__ == "__main__":
    unittest.main()
