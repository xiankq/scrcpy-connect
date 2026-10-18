import unittest

from analyze_player_archive import correlate_player


def observation():
    frames = [{"generation": 7, "ptsUs": n * 1000, "sourcePtsUs": 1000000 + n * 1000} for n in range(4)]
    archive = {"generation": 7, "complete": True, "frames": frames}
    decoded = [{"sourcePtsUs": f["sourcePtsUs"], "counter": c} for f, c in zip(frames, (0, 1, 1, 2))]
    samples = []
    timeline = [{"sequence": 0, "kind": "draw", "counter": 0}]
    for seq, first, selected in [(1, 1, 2), (2, 3, 3)]:
        raw = {"sourcePtsUs": frames[first]["sourcePtsUs"], "readCompletedUs": seq * 10000 + 2000, "captureSegment": 1}
        chosen = {"sourcePtsUs": frames[selected]["sourcePtsUs"], "readCompletedUs": seq * 10000 + 3000, "captureSegment": 1}
        if first == selected:
            chosen = raw
        sample = {"fixtureSequence": seq, "expectedCounter": seq, "inputObservedBeforeInvokeUs": seq * 10000,
                  "transportFrame": chosen, "transportWindow": [raw] if first == selected else [raw, chosen],
                  "relayFrame": {"sourcePtsUs": frames[selected]["sourcePtsUs"]},
                  "nativeFrameTrace": {"clockOriginUs": 0,
                    "snapshot": {"elapsedUs": seq * 10000 + 4000},
                    "decoded": [{"ptsSeconds": frames[first]["ptsUs"] / 1000000, "elapsedUs": seq * 10000 + 2500}]}}
        samples.append(sample)
        timeline.extend([{"sequence": seq, "kind": "input", "counter": seq},
                         {"sequence": seq, "kind": "draw", "counter": seq, "nanoUs": seq * 10000 + 3000}])
    run = {k: True for k in ("measurementLoopComplete", "appCleanupConfirmed", "driverCloseConfirmed",
                            "fixtureCleanupConfirmed", "targetTimelineComplete", "packetArchiveRequested", "diagnosticOnly")}
    run.update(rounds=[{"inputs": samples}], targetTimeline=timeline,
               clockBounds={"complete": True, "assumptions": "conditional",
                            "rounds": [{"valid": True, "intervalWidthUs": 204,
                                "offsetLowerUs": 1900, "offsetUpperUs": 2100,
                                "bootMinusMonoLowerUs": 4, "bootMinusMonoUpperUs": 6}]})
    return run, archive, decoded


class PlayerArchiveTests(unittest.TestCase):
    def test_earliest_frame_can_precede_snapshot_selected_frame(self):
        r = correlate_player(*observation())
        self.assertEqual(r["samples"][0]["newCounterFramesBeforeSelected"], 1)
        self.assertEqual(r["samples"][0]["firstRawToSelectedRawMs"], 1)
        self.assertEqual(r["samples"][0]["firstRawToFirstOnVideoMs"], .5)
        self.assertAlmostEqual(r["samples"][0]["drawEndToFirstRawLowerMs"], .893)
        self.assertAlmostEqual(r["samples"][0]["drawEndToFirstRawUpperMs"], 1.097)

    def test_absent_earliest_callback_stays_absent(self):
        run, archive, decoded = observation()
        run["rounds"][0]["inputs"][0]["nativeFrameTrace"]["decoded"] = []
        row = correlate_player(run, archive, decoded)["samples"][0]
        self.assertFalse(row["earliestOnVideoObserved"])
        self.assertNotIn("firstRawToFirstOnVideoMs", row)

    def test_missing_ambiguous_reversed_or_failed_evidence_is_rejected(self):
        mutations = [
            lambda r, a, d: r.update(appCleanupConfirmed=False),
            lambda r, a, d: d.pop(),
            lambda r, a, d: a["frames"][2].update(sourcePtsUs=1001000),
            lambda r, a, d: d[2].update(counter=0),
            lambda r, a, d: r["rounds"][0]["inputs"][0]["transportWindow"].pop(0),
            lambda r, a, d: r["rounds"][0]["inputs"][0]["transportWindow"].append(r["rounds"][0]["inputs"][0]["transportWindow"][0]),
            lambda r, a, d: r["targetTimeline"].append(r["targetTimeline"][1]),
            lambda r, a, d: r["rounds"][0]["inputs"][0]["nativeFrameTrace"]["snapshot"].update(elapsedUs=11000),
            lambda r, a, d: a["frames"][2].update(generation=8),
        ]
        for change in mutations:
            data = observation()
            change(*data)
            with self.assertRaises(ValueError):
                correlate_player(*data)


if __name__ == "__main__":
    unittest.main()
