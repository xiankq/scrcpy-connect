import copy
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from analyze_first_counter import correlate


def observation():
    packets = [{"config": False, "sourcePtsUs": 100 + n, "receivedHostUs": 10000 + n * 1000}
               for n in range(10)]
    # Two distinct frames contain counter 1. The first, not the later frame,
    # must supply its receipt even if a live snapshot would choose the latter.
    frames = [{"sourcePtsUs": 100 + n, "counter": max(0, n - 1) if n > 1 else n}
              for n in range(10)]
    run = {"run": "test", "inputs": [{"sequence": n, "counter": n, "hostBeforeSendUs": 10000 + n * 1000 - 500}
                                      for n in range(1, 9)],
           "clockBefore": [{"hostBeforeUs": 1000, "hostAfterUs": 1020, "targetBootUs": 10000}] * 3,
           "clockAfter": [{"hostBeforeUs": 30000, "hostAfterUs": 30020, "targetBootUs": 40000}] * 3}
    timeline = [{"run": "test", "kind": "draw", "sequence": 0, "counter": 0, "nanoUs": 10000}]
    for n in range(1, 9):
        timeline.extend([
            {"run": "test", "kind": "input", "sequence": n, "counter": n, "nanoUs": 20000 + n * 1000},
            {"run": "test", "kind": "draw", "sequence": n, "counter": n, "nanoUs": 20001 + n * 1000,
             "bootBeforeUs": 20001 + n * 1000, "bootAfterUs": 20002 + n * 1000},
        ])
    run.update({key: True for key in ("complete", "measurementComplete", "readerStopped", "processAbsent",
                                     "fixtureAbsent", "jarAbsent", "forwardRemoved", "timelineWritten", "packetLedgerWritten")})
    run.update(serverShellExit=0, readerErrors=[], cleanupErrors={})
    return {"packets": packets}, timeline, run, frames


class FirstCounterTests(unittest.TestCase):
    def test_cli_refuses_replacing_an_existing_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "first-counter.json"
            path.write_text("original observation")
            result = subprocess.run([sys.executable, "-B", str(Path(__file__).with_name("analyze_first_counter.py")),
                                     "--capture", directory, "--ffmpeg", "unused"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Refusing to replace", result.stderr)
            self.assertEqual(path.read_text(), "original observation")

    def test_first_pixel_uses_first_packet_instead_of_later_same_counter(self):
        result = correlate(*observation())
        self.assertEqual(result["samples"][0]["sourcePtsUs"], 101)
        self.assertEqual(result["samples"][0]["inputToFirstRawMs"], .5)
        self.assertEqual(len(result["samples"]), 8)

    def test_incomplete_and_ambiguous_media_are_rejected(self):
        for modify in (lambda c, t, r, f: f.pop(),
                       lambda c, t, r, f: f[2].update(sourcePtsUs=101),
                       lambda c, t, r, f: c["packets"][2].update(sourcePtsUs=101),
                       lambda c, t, r, f: f[-1].update(counter=7),
                       lambda c, t, r, f: f[3].update(counter=0),
                       lambda c, t, r, f: c["packets"][1].update(receivedHostUs=50000)):
            data = observation()
            modify(*data)
            with self.assertRaises(ValueError):
                correlate(*data)

    def test_fixture_and_calibration_failure_is_not_a_latency_sample(self):
        for modify in (lambda c, t, r, f: t.append(copy.deepcopy(t[0])),
                       lambda c, t, r, f: t.pop(),
                       lambda c, t, r, f: t[1].update(run="other"),
                       lambda c, t, r, f: t[2].update(counter=9),
                       lambda c, t, r, f: r["clockAfter"][0].update(targetBootUs=90000),
                       lambda c, t, r, f: r["inputs"][1].update(sequence=1)):
            data = observation()
            modify(*data)
            with self.assertRaises(ValueError):
                correlate(*data)

    def test_failed_cleanup_cannot_be_accepted_from_early_complete_flag(self):
        for key in ("measurementComplete", "readerStopped", "processAbsent", "fixtureAbsent", "jarAbsent",
                    "forwardRemoved", "timelineWritten", "packetLedgerWritten"):
            capture, timeline, run, frames = observation()
            run[key] = False
            with self.assertRaisesRegex(ValueError, "cleanup"):
                correlate(capture, timeline, run, frames)
        for key, value in (("readerErrors", ["incomplete packet"]), ("serverShellExit", 1),
                           ("cleanupErrors", {"uninstall": "timeout"})):
            capture, timeline, run, frames = observation()
            run[key] = value
            with self.assertRaisesRegex(ValueError, "cleanup"):
                correlate(capture, timeline, run, frames)


if __name__ == "__main__":
    unittest.main()
