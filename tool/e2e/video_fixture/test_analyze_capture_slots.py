import contextlib
import io
import sqlite3
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from analyze_capture_slots import analyze_slots, main, sql_string


def event(ts, slot, operation, identity=None):
    return {"sliceId": ts if identity is None else identity, "ts": ts, "dur": 1,
            "name": f"GraphicBufferSource: {slot}", "operation": operation,
            "operationSliceId": ts + 1000, "operationTs": ts - 1, "operationDur": 3}


class CaptureSlotsTests(unittest.TestCase):
    def test_first_release_infers_initial_acquisition_without_invented_duration(self):
        report = analyze_slots([
            event(10, 7, "releaseBuffer"),
            event(20, 7, "dequeueBuffer"),
            event(30, 7, "queueBuffer"),
            event(40, 7, "acquireBuffer"),
            event(90, 7, "releaseBuffer"),
        ])
        self.assertEqual(report["initialAcquiredSlotsInferred"], [7])
        self.assertEqual(report["initialPartialReleases"], [
            {"slot": 7, "releaseSliceId": 10, "releasedAtNs": 10},
        ])
        self.assertEqual(report["counts"]["completePairs"], 1)
        self.assertEqual(report["pairs"][0]["holdNs"], 50)
        self.assertEqual(report["finalAcquiredSlots"], [])

    def test_terminal_acquisition_is_saved_but_not_closed_at_window_end(self):
        report = analyze_slots([
            event(10, 4, "acquireBuffer"), event(20, 4, "releaseBuffer"),
            event(30, 4, "acquireBuffer"), event(100, 9, "queueBuffer"),
        ])
        self.assertEqual(report["allHolds"]["count"], 1)
        self.assertEqual(report["allHolds"]["medianMs"], 10 / 1e6)
        self.assertEqual(report["terminalAcquisitions"], [
            {"slot": 4, "acquireSliceId": 30, "acquiredAtNs": 30},
        ])
        self.assertEqual(report["finalAcquiredSlots"], [4])

    def test_occupancy_is_wall_clock_weighted_and_uses_slot_event_starts(self):
        # Window [10,100), final third [70,100): slot 2 held for 15ns,
        # no slot held for the other 15ns. A sample-count third gives a
        # different answer because of the early cluster of producer events.
        rows = [event(10, 2, "acquireBuffer"), event(11, 3, "dequeueBuffer"),
                event(12, 3, "queueBuffer"), event(13, 3, "dequeueBuffer"),
                event(14, 3, "queueBuffer"), event(85, 2, "releaseBuffer"),
                event(100, 3, "dequeueBuffer")]
        rows[-1]["dur"] = 50
        rows[-1]["operationDur"] = 52
        report = analyze_slots(rows)
        self.assertEqual(report["window"]["lastThirdStartNs"], 70)
        self.assertEqual(report["window"]["endExclusiveNs"], 100)
        self.assertEqual(report["lastThirdOccupancy"], [
            {"acquiredSlots": 0, "durationNs": 15, "percent": 50.0},
            {"acquiredSlots": 1, "durationNs": 15, "percent": 50.0},
        ])
        # Lifetime is selected by its release timestamp, without clipping
        # its acquisition to the last-third boundary.
        self.assertEqual(report["lastThirdReleasedHolds"]["medianMs"], 75 / 1e6)
        self.assertEqual(len(report["events"]), len(rows))

    def test_invalid_state_sequences_are_rejected(self):
        cases = [
            ([event(10, 2, "acquireBuffer"), event(20, 2, "acquireBuffer")], "Duplicate acquire"),
            ([event(10, 2, "queueBuffer"), event(20, 2, "releaseBuffer")], "without acquisition"),
            ([event(10, 2, "releaseBuffer"), event(20, 2, "releaseBuffer")], "without acquisition"),
            ([event(10, 2, "acquireBuffer"), event(20, 2, "dequeueBuffer")], "while slot"),
        ]
        for rows, error in cases:
            with self.subTest(rows=rows), self.assertRaisesRegex(ValueError, error):
                analyze_slots(rows)

    def test_missing_or_ambiguous_trace_evidence_is_rejected(self):
        good = [event(10, 1, "acquireBuffer"), event(20, 1, "releaseBuffer")]
        with self.assertRaisesRegex(ValueError, "data loss"):
            analyze_slots(good, [{"name": "ftrace_cpu_overrun", "value": 1}])
        with self.assertRaisesRegex(ValueError, "positive wall-clock"):
            analyze_slots([])
        with self.assertRaisesRegex(ValueError, "timestamp order"):
            analyze_slots(list(reversed(good)))
        with self.assertRaisesRegex(ValueError, "Same-slot timestamps"):
            analyze_slots([event(10, 1, "acquireBuffer", 1), event(10, 1, "releaseBuffer", 2)])
        with self.assertRaisesRegex(ValueError, "Duplicate slot slice"):
            analyze_slots([good[0], event(20, 1, "releaseBuffer", good[0]["sliceId"])])

    def test_malformed_and_unclosed_slot_or_parent_slices_are_rejected(self):
        cases = [
            ("name", "GraphicBufferSource: nope", "Malformed slot"),
            ("operation", None, "Malformed slot"),
            ("ts", "1.5", "Malformed integer"),
            ("dur", -1, "unclosed"),
            ("operationDur", -1, "unclosed"),
            ("operationTs", 11, "outside"),
            ("dur", 10, "outside"),
        ]
        for key, value, error in cases:
            rows = [event(10, 1, "acquireBuffer"), event(20, 1, "releaseBuffer")]
            rows[0][key] = value
            with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, error):
                analyze_slots(rows)

    def test_arbitrary_exact_process_name_remains_a_sql_literal(self):
        names = ["interop.scrcpy:00000001:/data/local/tmp/interop-scrcpy-a-b.jar",
                 "capture'; DROP TABLE process; --"]
        with sqlite3.connect(":memory:") as db:
            db.execute("CREATE TABLE process (name TEXT)")
            db.executemany("INSERT INTO process VALUES (?)", [(name,) for name in names])
            for name in names:
                rows = db.execute("SELECT name FROM process WHERE name=" + sql_string(name)).fetchall()
                self.assertEqual(rows, [(name,)])
            self.assertEqual(db.execute("SELECT count(*) FROM process").fetchone(), (2,))
        for name in ("", "bad\0name"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                sql_string(name)

    def test_cli_rejects_missing_or_ambiguous_exact_process_before_writing(self):
        with tempfile.TemporaryDirectory(prefix="connect-capture-slots-test-") as directory:
            output = Path(directory) / "must-not-exist.json"
            argv = ["analyze_capture_slots.py", "--trace-processor", "unused-processor",
                    "--trace", "unused-trace", "--process-name", "same-name",
                    "--output", str(output)]
            for csv_text in ('"upid","pid","name"\n',
                             '"upid","pid","name"\n1,12,same-name\n2,34,same-name\n'):
                completed = subprocess.CompletedProcess([], 0, csv_text, "")
                with self.subTest(csv_text=csv_text), patch.object(sys, "argv", argv), \
                        patch("analyze_capture_slots.subprocess.run", return_value=completed) as run, \
                        self.assertRaisesRegex(ValueError, "unique exact process"):
                    main()
                self.assertEqual(run.call_count, 1)
                self.assertFalse(output.exists())

    def test_cli_preserves_an_existing_evidence_file(self):
        # Use real pure analysis behind mocked trace queries. A successful
        # analysis must still refuse replacement of an earlier evidence file.
        processes = '"upid","pid","name"\n5,12,chosen\n'
        losses = '"name","value"\n'
        slices = (
            'sliceId,ts,dur,name,operationSliceId,operationTs,operationDur,operation\n'
            '1,10,1,GraphicBufferSource: 2,11,9,3,acquireBuffer\n'
            '2,20,1,GraphicBufferSource: 2,12,19,3,releaseBuffer\n'
        )
        responses = [subprocess.CompletedProcess([], 0, text, "")
                     for text in (processes, losses, slices)]
        with tempfile.TemporaryDirectory(prefix="connect-capture-slots-test-") as directory:
            output = Path(directory) / "existing.json"
            output.write_text("original evidence\n")
            argv = ["analyze_capture_slots.py", "--trace-processor", "unused-processor",
                    "--trace", "unused-trace", "--process-name", "chosen",
                    "--output", str(output)]
            with patch.object(sys, "argv", argv), \
                    patch("analyze_capture_slots.subprocess.run", side_effect=responses), \
                    contextlib.redirect_stdout(io.StringIO()), \
                    self.assertRaises(FileExistsError):
                main()
            self.assertEqual(output.read_text(), "original evidence\n")


if __name__ == "__main__":
    unittest.main()
