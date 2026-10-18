#!/usr/bin/env python3
"""Correlate ordinary video benchmark inputs with Android Perfetto slices.

Requires trace_processor, not a Python Perfetto package. Media PTS are keys,
never clocks. Durations use two timestamps from the same clock domain. This
does not turn an instrumented debug/AVD run into a production latency result.
"""

import argparse
import csv
import io
import json
import math
from pathlib import Path
import re
import statistics
import subprocess


CODEC = re.compile(
    r"CCodecBufferChannel::(queue|onWorkDone)\((.+)@ts=(-?\d+)\)"
)
MARKER = re.compile(r"connect\.onVideo\(t=(\d+)@ts=(-?\d+)\)")


def read_slices(processor, trace):
    query = """
        SELECT s.id, s.ts, s.dur, s.name, p.pid
        FROM slice s
        JOIN thread_track tt ON s.track_id = tt.id
        JOIN thread t ON tt.utid = t.utid
        JOIN process p ON t.upid = p.upid
        WHERE s.name GLOB 'CCodecBufferChannel::queue(*'
           OR s.name GLOB 'CCodecBufferChannel::onWorkDone(*'
           OR s.name GLOB 'connect.onVideo(*'
        ORDER BY s.ts
    """
    result = subprocess.run(
        [processor, "query", str(trace), query],
        capture_output=True, text=True, check=True, timeout=120,
    )
    return list(csv.DictReader(io.StringIO(result.stdout)))


def correlate(slices, benchmark, process_id):
    groups = {}
    markers = []
    for row in slices:
        event = {key: int(row[key]) for key in ("id", "ts", "dur", "pid")}
        if event["pid"] != process_id:
            continue
        match = CODEC.fullmatch(row["name"])
        if match:
            kind, codec, pts = match.groups()
            key = (event["pid"], codec, int(pts))
            groups.setdefault(key, {"queue": [], "onWorkDone": []})[kind].append(event)
        elif match := MARKER.fullmatch(row["name"]):
            event.update(token=int(match[1]), ptsUs=int(match[2]))
            markers.append(event)

    # Keep ambiguous/repeated CONFIG or reused codec/PTS groups out of pairing.
    # Never silently choose a nearest event from a different decoder/session.
    pairs = []
    rejected = []
    for (pid, codec, pts), events in groups.items():
        queued, done = events["queue"], events["onWorkDone"]
        if len(queued) != 1 or len(done) != 1 or done[0]["ts"] < queued[0]["ts"]:
            rejected.append({"pid": pid, "codec": codec, "ptsUs": pts,
                             "queueCount": len(queued), "doneCount": len(done)})
            continue
        pairs.append({"pid": pid, "codec": codec, "ptsUs": pts,
                      "queueNs": queued[0]["ts"], "doneNs": done[0]["ts"]})

    rounds = benchmark.get("rounds", [])
    requested_pts = [s["relayFrame"]["ptsUs"] for r in rounds
                     for s in r["inputs"]]
    inputs = []
    for round_ in rounds:
        for index, sample in enumerate(round_["inputs"]):
            frame = sample["relayFrame"]
            pts = frame["ptsUs"]
            native = sample["nativeFrameTrace"]
            record = {"round": round_["round"], "input": index, "ptsUs": pts}
            # FFmpeg may truncate the floating seconds->microseconds conversion
            # by one us. Retain the actual trace PTS and refuse any ambiguity.
            candidates = [p for p in pairs if abs(p["ptsUs"] - pts) <= 1]
            if len(candidates) != 1:
                record["unmatched"] = f"codec_pair_count={len(candidates)}"
                inputs.append(record)
                continue
            pair = candidates[0]
            if sum(abs(pair["ptsUs"] - p) <= 1 for p in requested_pts) != 1:
                record["unmatched"] = "codec_pair_requested_by_multiple_inputs"
                inputs.append(record)
                continue
            decoded = [d for d in native["decoded"]
                       if math.isfinite(d["ptsSeconds"])
                       and abs(d["ptsSeconds"] * 1_000_000 - pts) <= 1.1]
            if len(decoded) != 1:
                record["unmatched"] = f"native_decoded_count={len(decoded)}"
                inputs.append(record)
                continue
            token = native.get("traceToken")
            matching = [m for m in markers
                        if token is not None and m["token"] == token
                        and m["pid"] == pair["pid"]
                        and abs(m["ptsUs"] - pts) <= 1]
            if len(matching) != 1:
                record["markerUnmatched"] = f"marker_count={len(matching)}"
                if token is not None:
                    # Identity is known: missing/wrong player markers must not
                    # leave plausible codec statistics from another session.
                    inputs.append(record)
                    continue
            elif matching[0]["ts"] < pair["doneNs"]:
                record["markerUnmatched"] = "marker_precedes_work_done"
                inputs.append(record)
                continue
            else:
                record.update(traceToken=token, markerPtsUs=matching[0]["ptsUs"],
                              doneToOnVideoMs=(matching[0]["ts"] - pair["doneNs"])
                              / 1_000_000)
            record.update(
                codec=pair["codec"], tracePtsUs=pair["ptsUs"],
                queueToDoneMs=(pair["doneNs"] - pair["queueNs"]) / 1_000_000,
                relayToOnVideoMs=(native["clockOriginUs"] + decoded[0]["elapsedUs"]
                                  - frame["writeStartedUs"]) / 1000,
            )
            inputs.append(record)

    def summary(field):
        values = [r[field] for r in inputs if field in r]
        return {"count": len(values), "min": min(values),
                "median": statistics.median(values), "max": max(values)} if values else None

    return {
        "scope": "instrumented ordinary Driver benchmark; no glass-to-glass claim",
        "clockPolicy": "PTS keys only; each duration uses one clock domain; no cross-clock timestamp subtraction",
        "processId": process_id,
        "codecPairs": len(pairs), "rejectedCodecGroups": rejected,
        "inputCount": len(inputs),
        "queueToDoneMs": summary("queueToDoneMs"),
        "relayToOnVideoMs": summary("relayToOnVideoMs"),
        "doneToOnVideoMs": summary("doneToOnVideoMs"),
        "inputs": inputs,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace-processor", required=True)
    parser.add_argument("--trace", required=True, type=Path)
    parser.add_argument("--benchmark", required=True, type=Path)
    parser.add_argument("--pid", required=True, type=int,
                        help="Actual benchmark process PID recorded with this trace")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--require-markers", action="store_true")
    args = parser.parse_args()
    report = correlate(read_slices(args.trace_processor, args.trace),
                       json.loads(args.benchmark.read_text()), args.pid)
    # Preserve previous evidence; a new invocation requires a new output path.
    with args.output.open("x") as output:
        json.dump(report, output, indent=2)
        output.write("\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("inputs", "rejectedCodecGroups")}, indent=2))
    if not report["inputs"]:
        parser.exit(1, "No benchmark input observations; see output.\n")
    if args.require_markers and any("doneToOnVideoMs" not in r for r in report["inputs"]):
        parser.exit(1, "Incomplete or ambiguous system marker coverage; see output.\n")


if __name__ == "__main__":
    main()
