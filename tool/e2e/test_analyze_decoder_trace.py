"""Guard correlation against false latency attribution across sessions/clocks."""

import copy
import unittest

from analyze_decoder_trace import correlate


def event(name, timestamp, pid=42):
    return {"id": "1", "ts": str(timestamp), "dur": "100", "name": name,
            "pid": str(pid)}


class DecoderCorrelationTest(unittest.TestCase):
    def setUp(self):
        # Deliberately unrelated system ns and Rust-relative us origins.
        self.slices = [
            event("CCodecBufferChannel::queue(decoder#1@ts=999999)", 90_000_000_000),
            event("CCodecBufferChannel::onWorkDone(decoder#1@ts=999999)", 90_002_000_000),
            event("connect.onVideo(t=7@ts=1000000)", 90_102_000_000),
        ]
        self.benchmark = {"rounds": [{"round": 0, "inputs": [{
            "relayFrame": {"ptsUs": 1_000_000, "writeStartedUs": 997_000},
            "nativeFrameTrace": {
                "traceToken": 7, "clockOriginUs": 900_000,
                "decoded": [{"ptsSeconds": 1.0, "elapsedUs": 200_000}],
            },
        }]}]}

    def sample(self):
        return correlate(self.slices, self.benchmark, 42)["inputs"][0]

    def test_separate_clock_durations_and_one_microsecond_pts_truncation(self):
        result = self.sample()
        self.assertEqual(result["queueToDoneMs"], 2)
        self.assertEqual(result["doneToOnVideoMs"], 100)
        self.assertEqual(result["relayToOnVideoMs"], 103)
        self.assertEqual(result["tracePtsUs"], 999_999)

    def test_other_player_token_cannot_supply_the_marker(self):
        self.slices[2]["name"] = "connect.onVideo(t=8@ts=1000000)"
        result = self.sample()
        self.assertNotIn("doneToOnVideoMs", result)
        self.assertNotIn("queueToDoneMs", result)

    def test_other_process_cannot_supply_the_marker(self):
        self.slices[2]["pid"] = "43"
        result = self.sample()
        self.assertNotIn("doneToOnVideoMs", result)
        self.assertNotIn("queueToDoneMs", result)

    def test_repeated_decoded_observations_are_not_silently_chosen(self):
        self.benchmark["rounds"][0]["inputs"][0]["nativeFrameTrace"]["decoded"].append(
            {"ptsSeconds": 1.0, "elapsedUs": 100_000}
        )
        self.assertNotIn("relayToOnVideoMs", self.sample())

    def test_missing_repeated_codec_events_cannot_reuse_another_sessions_pair(self):
        second = copy.deepcopy(self.benchmark["rounds"][0])
        second["round"] = 1
        second["inputs"][0]["nativeFrameTrace"]["traceToken"] = 8
        self.benchmark["rounds"].append(second)
        self.slices.append(event("connect.onVideo(t=8@ts=1000000)", 95_102_000_000))
        results = correlate(self.slices, self.benchmark, 42)["inputs"]
        for result in results:
            self.assertNotIn("queueToDoneMs", result)
            self.assertNotIn("doneToOnVideoMs", result)

    def test_reused_pts_across_codec_instances_is_ambiguous(self):
        self.slices += [
            event("CCodecBufferChannel::queue(decoder#2@ts=999999)", 80_000_000_000),
            event("CCodecBufferChannel::onWorkDone(decoder#2@ts=999999)", 80_002_000_000),
        ]
        result = self.sample()
        self.assertEqual(result["unmatched"], "codec_pair_count=2")
        self.assertNotIn("queueToDoneMs", result)

    def test_repeated_queue_or_callback_cannot_be_silently_chosen(self):
        self.slices.append(self.slices[0].copy())
        self.assertIn("unmatched", self.sample())
        self.slices.pop()
        self.slices.append(self.slices[2].copy())
        self.assertNotIn("doneToOnVideoMs", self.sample())

    def test_marker_before_work_done_cannot_produce_negative_latency(self):
        self.slices[2]["ts"] = str(90_001_000_000)
        self.assertEqual(self.sample()["markerUnmatched"], "marker_precedes_work_done")


if __name__ == "__main__":
    unittest.main()
