#!/usr/bin/env python3
"""Correlate a lab raw-drain receipt with target CCodec Perfetto events.

No device operations or downloads. Requires the official trace_processor tool.
This diagnoses the target output callback boundary, not pixel presentation or
pure encoding CPU time. Original capture and all matches remain in the output.
"""

import argparse
import csv
import io
import json
from pathlib import Path
import re
import statistics
import subprocess


def correlate(receipt, events, clocks, losses):
    if losses:
        raise ValueError("Trace reports data loss; correlation is incomplete")
    offsets = [(int(c["boot_ns"]) - int(c["mono_ns"])) / 1000 for c in clocks]
    if not offsets or max(offsets) - min(offsets) > 1000:
        raise ValueError("Missing or inconsistent BOOTTIME/MONOTONIC snapshots")
    # A clock snapshot contains successive clock reads, not rigorous brackets.
    # Keep the measured range; do not label it a proven uncertainty interval.
    offset = statistics.median(offsets)
    frames = {}
    for frame in receipt["frames"]:
        pts = int(frame["pts"])
        if pts in frames:
            raise ValueError("Duplicate captured PTS requires segment disambiguation")
        frames[pts] = frame
    if not frames or receipt["offsetLow"] > receipt["offsetHigh"]:
        raise ValueError("Missing frames or invalid host clock brackets")
    matches, outside, seen = [], 0, set()
    for event in events:
        name = re.fullmatch(r"CCodecBufferChannel::onWorkDone\((.+)@ts=(\d+)\)", event["name"])
        if not name or int(event["dur"]) < 0:
            raise ValueError("Malformed or incomplete CCodec event")
        pts = int(name[2])
        if pts in seen:
            raise ValueError("Duplicate CCodec PTS requires segment disambiguation")
        seen.add(pts)
        if pts not in frames:
            if min(frames) <= pts <= max(frames):
                raise ValueError("CCodec event inside capture has no matching received frame")
            outside += 1
            continue
        frame = frames[pts]
        done_us = int(event["ts"]) / 1000
        source_age = done_us - (pts + offset)
        if source_age < -1000:
            raise ValueError("PTS lies after callback; source clock assumption failed")
        matches.append({
            "ptsUs": pts, "codec": name[1], "workDoneBootUs": done_us,
            "sourceToWorkDoneUs": source_age,
            "workDoneToHeaderLowerUs": frame["headerReadUs"] + receipt["offsetLow"] - done_us,
            "workDoneToHeaderUpperUs": frame["headerReadUs"] + receipt["offsetHigh"] - done_us,
        })
    if not matches:
        raise ValueError("No target CCodec events matched received PTS")
    matches.sort(key=lambda row: row["workDoneBootUs"])
    keys = ("sourceToWorkDoneUs", "workDoneToHeaderLowerUs", "workDoneToHeaderUpperUs")

    def summary(rows):
        return {key: statistics.median(row[key] for row in rows) for key in keys}

    later = matches[len(matches) * 2 // 3:]
    return {
        "matched": len(matches), "outsideCapture": outside,
        "bootMinusMonoSamplesUs": {"min": min(offsets), "max": max(offsets), "median": offset},
        "assumptions": [
            "Source PTS shares target MONOTONIC origin and rate; exact PTS matches do not prove this.",
            "Uninterrupted target run; clock snapshots are successive reads, not formal offset bounds.",
            "Receipt host/target offset brackets retain their original continuity assumptions.",
        ],
        "boundary": "CCodec onWorkDone callback processing, including earlier capture, queues and IPC; not pure encoder CPU or presentation",
        "allMedianUs": summary(matches), "lastThirdCount": len(later),
        "lastThirdMedianUs": summary(later), "matches": matches,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace-processor", required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--trace", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    receipt = json.loads(args.receipt.read_text())
    run = receipt["run"]
    if not re.fullmatch(r"[0-9a-f]{12}", run):
        raise ValueError("Expected an isolated raw-drain run ID")

    def query(sql):
        result = subprocess.run(
            [args.trace_processor, "query", str(args.trace), sql],
            capture_output=True, text=True, timeout=30, check=True,
        )
        return list(csv.DictReader(io.StringIO(result.stdout)))

    events = query(f"""SELECT s.ts,s.dur,s.name FROM slice s
        JOIN thread_track tt ON tt.id=s.track_id
        JOIN thread t ON t.utid=tt.utid JOIN process p ON p.upid=t.upid
        WHERE p.name='interop.rawdrain.{run}'
        AND s.name GLOB 'CCodecBufferChannel::onWorkDone(*@ts=*)' ORDER BY s.ts""")
    clocks = query("""SELECT b.clock_value boot_ns,m.clock_value mono_ns FROM clock_snapshot b
        JOIN clock_snapshot m ON m.snapshot_id=b.snapshot_id AND m.machine_id IS b.machine_id
        WHERE b.clock_name='BOOTTIME' AND m.clock_name='MONOTONIC'""")
    losses = query("SELECT name,value FROM stats WHERE severity='data_loss' AND value>0")
    report = correlate(receipt, events, clocks, losses)
    report["inputs"] = {"receipt": str(args.receipt), "trace": str(args.trace)}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "matches"}))


if __name__ == "__main__":
    main()
