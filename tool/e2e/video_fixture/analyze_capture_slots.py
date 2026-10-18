#!/usr/bin/env python3
"""Analyze captured GraphicBufferSource slot lifetimes in one target process.

Offline only: no device operations, downloads, PTS or cross-clock subtraction.
Counts describe acquired BufferQueue slots observed in the event window, not
the exact Codec2 work queue, encoding CPU time, or pixel presentation latency.
"""

import argparse
import csv
import io
import json
from pathlib import Path
import re
import statistics
import subprocess


OPERATIONS = {"acquireBuffer", "releaseBuffer", "queueBuffer", "dequeueBuffer"}


def sql_string(value):
    """Quote an exact SQLite string literal, including shell-style process names."""
    if not isinstance(value, str) or not value or "\0" in value:
        raise ValueError("Expected a nonempty process name without NUL")
    return "'" + value.replace("'", "''") + "'"


def _integer(row, key):
    value = row.get(key)
    if isinstance(value, bool) or not re.fullmatch(r"-?\d+", str(value)):
        raise ValueError(f"Malformed integer {key}: {value!r}")
    return int(value)


def analyze_slots(events, losses=()):
    """Validate already ordered slot slices and reconstruct observed occupancy.

    The first release for a slot may establish acquisition before the window
    only when release is that slot's first observed operation. No duration is
    invented for this initial partial lifetime or for an acquisition still open
    at the end. Slice timestamps share the trace's clock throughout.
    """
    if losses:
        raise ValueError("Trace reports data loss; slot analysis is incomplete")
    normalized, first, ids, last_by_slot = [], {}, set(), {}
    previous_ts = None
    for row in events:
        name = re.fullmatch(r"GraphicBufferSource: (0|[1-9]\d*)", str(row.get("name")))
        if name is None or row.get("operation") not in OPERATIONS:
            raise ValueError("Malformed slot name or operation")
        event = {key: _integer(row, key) for key in (
            "sliceId", "ts", "dur", "operationSliceId", "operationTs", "operationDur",
        )}
        if any(event[key] < 0 for key in event):
            raise ValueError("Negative integer or unclosed slot/operation slice")
        if not (
            event["operationTs"] <= event["ts"]
            and event["ts"] + event["dur"]
            <= event["operationTs"] + event["operationDur"]
        ):
            raise ValueError("Slot slice lies outside its operation slice")
        if event["sliceId"] in ids:
            raise ValueError("Duplicate slot slice ID")
        ids.add(event["sliceId"])
        ts, slot = event["ts"], int(name[1])
        if previous_ts is not None and ts < previous_ts:
            raise ValueError("Slot events are out of timestamp order")
        if slot in last_by_slot and ts <= last_by_slot[slot]:
            raise ValueError("Same-slot timestamps are ambiguous or out of order")
        previous_ts = ts
        last_by_slot[slot] = ts
        event.update(name=row["name"], operation=row["operation"], slot=slot)
        normalized.append(event)
        first.setdefault(slot, event)
    if len(normalized) < 2 or normalized[-1]["ts"] == normalized[0]["ts"]:
        raise ValueError("Expected a positive wall-clock slot event span")

    initial = sorted(slot for slot, event in first.items()
                     if event["operation"] == "releaseBuffer")
    acquired = set(initial)
    starts, pairs, occupancy, initial_releases = {}, [], [], []
    for event in normalized:
        slot, operation = event["slot"], event["operation"]
        if operation == "acquireBuffer":
            if slot in acquired:
                raise ValueError(f"Duplicate acquire for slot {slot}")
            acquired.add(slot)
            starts[slot] = event
        elif operation == "releaseBuffer":
            if slot not in acquired:
                raise ValueError(f"Release without acquisition for slot {slot}")
            acquired.remove(slot)
            if slot in starts:
                start = starts.pop(slot)
                duration = event["ts"] - start["ts"]
                pairs.append({
                    "slot": slot, "acquireSliceId": start["sliceId"],
                    "releaseSliceId": event["sliceId"],
                    "acquiredAtNs": start["ts"], "releasedAtNs": event["ts"],
                    "holdNs": duration, "holdMs": duration / 1e6,
                })
            else:
                initial_releases.append({"slot": slot, "releaseSliceId": event["sliceId"],
                                         "releasedAtNs": event["ts"]})
        elif slot in acquired:
            raise ValueError(f"Producer operation while slot {slot} is acquired")
        occupancy.append((event["ts"], len(acquired)))

    start, end = normalized[0]["ts"], normalized[-1]["ts"]
    cut = start + (end - start) * 2 // 3
    weights = {}
    for (ts, count), (next_ts, _) in zip(occupancy, occupancy[1:]):
        duration = max(0, next_ts - max(ts, cut))
        if duration:
            weights[count] = weights.get(count, 0) + duration
    assert sum(weights.values()) == end - cut
    late = [pair for pair in pairs if pair["releasedAtNs"] >= cut]

    def holds(rows):
        values = [pair["holdMs"] for pair in rows]
        return {"count": len(values),
                "medianMs": statistics.median(values) if values else None,
                "minMs": min(values) if values else None,
                "maxMs": max(values) if values else None}

    return {
        "boundary": (
            "Observed BufferQueue slots from acquireBuffer to releaseBuffer; "
            "not exact Codec2 work queue size, encoding CPU or pixel presentation latency"
        ),
        "clockPolicy": "Only timestamps within this trace; no PTS or cross-clock subtraction",
        "assumptions": [
            "The trace has no reported data loss and captures relevant slot operations in this process.",
            "A slot whose first operation is release was acquired before the event window.",
            "Only observed slots are counted; unseen slots or unreported events cannot be reconstructed.",
        ],
        "window": {"startNs": start, "endExclusiveNs": end, "lastThirdStartNs": cut,
                   "definition": "First through last selected slot event start, not slice ends or sample count",
                   "lastThirdDefinition": "start + floor(2 * (end - start) / 3); occupancy weighted by interval duration",
                   "holdSelection": "Complete lifetimes released at or after the cut; durations are not clipped"},
        "observedSlots": sorted(first), "initialAcquiredSlotsInferred": initial,
        "initialPartialReleases": initial_releases,
        "terminalAcquisitions": [
            {"slot": slot, "acquireSliceId": event["sliceId"], "acquiredAtNs": event["ts"]}
            for slot, event in sorted(starts.items())
        ],
        "finalAcquiredSlots": sorted(acquired),
        "counts": {"events": len(normalized),
                   "acquires": sum(e["operation"] == "acquireBuffer" for e in normalized),
                   "releases": sum(e["operation"] == "releaseBuffer" for e in normalized),
                   "completePairs": len(pairs)},
        "acquiredCountRange": [min(n for _, n in occupancy), max(n for _, n in occupancy)],
        "allHolds": holds(pairs), "lastThirdReleasedHolds": holds(late),
        "lastThirdOccupancy": [
            {"acquiredSlots": count, "durationNs": duration,
             "percent": 100 * duration / (end - cut)}
            for count, duration in sorted(weights.items())
        ],
        "events": normalized, "pairs": pairs,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace-processor", required=True)
    parser.add_argument("--trace", type=Path, required=True)
    parser.add_argument("--process-name", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    def query(sql):
        result = subprocess.run(
            [args.trace_processor, "query", str(args.trace), sql],
            capture_output=True, text=True, timeout=30, check=True,
        )
        return list(csv.DictReader(io.StringIO(result.stdout)))

    processes = query("SELECT upid,pid,name FROM process WHERE name=" + sql_string(args.process_name))
    if len(processes) != 1:
        raise ValueError("Expected one unique exact process name in trace")
    upid = _integer(processes[0], "upid")
    if upid < 0:
        raise ValueError("Malformed process upid")
    losses = query("SELECT name,value FROM stats WHERE severity='data_loss' AND value>0")
    events = query(f"""SELECT s.id sliceId,s.ts,s.dur,s.name,
        par.id operationSliceId,par.ts operationTs,par.dur operationDur,par.name operation
        FROM slice s LEFT JOIN slice par ON par.id=s.parent_id
        JOIN thread_track tt ON tt.id=s.track_id
        JOIN thread t ON t.utid=tt.utid
        WHERE t.upid={upid} AND s.name GLOB 'GraphicBufferSource:*'
        ORDER BY s.ts,s.id""")
    report = analyze_slots(events, losses)
    report["inputs"] = {"trace": str(args.trace), "processName": args.process_name,
                        "process": processes[0]}
    # Evidence files are new artifacts; refuse to overwrite a previous result.
    with args.output.open("x") as output:
        output.write(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key not in ("events", "pairs")}))


if __name__ == "__main__":
    main()
