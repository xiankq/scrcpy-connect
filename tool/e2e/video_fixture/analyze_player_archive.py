#!/usr/bin/env python3
"""Join an actual player archive's earliest counter frames to raw/snapshot clocks.

No point subtraction of target media PTS and controller clocks. Decoder callback
absence is reported as absence, not invented as a dropped or presented frame.
"""
import argparse
import json
from pathlib import Path

from analyze_first_counter import decode_frames


def correlate_player(run, archive, decoded):
    if any(run.get(k) is not True for k in ("measurementLoopComplete", "appCleanupConfirmed",
            "driverCloseConfirmed", "fixtureCleanupConfirmed", "targetTimelineComplete")):
        raise ValueError("measurement or cleanup is incomplete")
    if run.get("packetArchiveRequested") is not True or run.get("diagnosticOnly") is not True:
        raise ValueError("expected explicit archive diagnostic")
    rounds = run["rounds"]
    if len(rounds) != 1 or not run["clockBounds"]["complete"] or not run["clockBounds"]["rounds"][0]["valid"]:
        raise ValueError("expected one valid clock-calibrated round")
    frames = archive["frames"]
    if archive["complete"] is not True or not frames or len(frames) != len(decoded):
        raise ValueError("incomplete decoded archive")
    pts = [f["sourcePtsUs"] for f in frames]
    if pts != [f["sourcePtsUs"] for f in decoded] or len(set(pts)) != len(pts):
        raise ValueError("ambiguous or incomplete exact-PTS join")
    origins = {f["sourcePtsUs"] - f["ptsUs"] for f in frames}
    if len(origins) != 1 or any(f["generation"] != archive["generation"] for f in frames):
        raise ValueError("archive origin or generation changed")
    inputs = rounds[0]["inputs"]
    counters = [f["counter"] for f in decoded]
    if [s["fixtureSequence"] for s in inputs] != list(range(1, len(inputs) + 1)):
        raise ValueError("input sequences reset or duplicated")
    if [s["expectedCounter"] for s in inputs] != list(range(1, len(inputs) + 1)) or len(inputs) > 15:
        raise ValueError("this narrow diagnostic does not accept counter wrap")
    if counters[0] != 0 or counters[-1] != len(inputs) or any(a > b or b > a + 1 for a, b in zip(counters, counters[1:])):
        raise ValueError("counter skipped, reverted or missing terminal update")
    bounds = run["clockBounds"]["rounds"][0]
    initial = [e for e in run["targetTimeline"] if e["kind"] == "draw" and e["sequence"] == 0]
    if len(initial) != 1:
        raise ValueError("fixture reset or missing initial draw")
    rows = []
    for sample in inputs:
        seq = sample["fixtureSequence"]
        first = counters.index(seq)
        selected = pts.index(sample["relayFrame"]["sourcePtsUs"])
        if selected < first or counters[selected] != seq:
            raise ValueError("snapshot frame does not belong to the new counter")
        matching = [f for f in sample["transportWindow"] if f["sourcePtsUs"] == pts[first]]
        if len(matching) != 1:
            raise ValueError("earliest frame lacks one exact raw receipt")
        raw = matching[0]
        if raw["captureSegment"] != sample["transportFrame"]["captureSegment"]:
            raise ValueError("raw generation changed during input")
        trace = sample["nativeFrameTrace"]
        snap = trace["snapshot"]
        snapshot_us = trace["clockOriginUs"] + snap["elapsedUs"]
        selected_raw = sample["transportFrame"]
        observed = sample["inputObservedBeforeInvokeUs"]
        if not observed <= raw["readCompletedUs"] <= selected_raw["readCompletedUs"] <= snapshot_us:
            raise ValueError("controller event order is inconsistent")
        matches = [d for d in trace["decoded"] if abs(d["ptsSeconds"] * 1000000 - frames[first]["ptsUs"]) <= 1.1]
        if len(matches) > 1:
            raise ValueError("ambiguous earliest onVideo callback")
        events = [e for e in run["targetTimeline"] if e["sequence"] == seq]
        if len(events) != 2 or sorted(e["kind"] for e in events) != ["draw", "input"] or any(e["counter"] != seq for e in events):
            raise ValueError("missing or ambiguous target events")
        draw = next(e for e in events if e["kind"] == "draw")
        row = {"sequence": seq, "firstFrameIndex": first, "selectedFrameIndex": selected,
               "firstSourcePtsUs": pts[first], "selectedSourcePtsUs": pts[selected],
               "newCounterFramesBeforeSelected": selected - first,
               "inputToFirstRawMs": (raw["readCompletedUs"] - observed) / 1000,
               "firstRawToSelectedRawMs": (selected_raw["readCompletedUs"] - raw["readCompletedUs"]) / 1000,
               "firstRawToSnapshotMs": (snapshot_us - raw["readCompletedUs"]) / 1000,
               "drawEndToFirstRawLowerMs": (raw["readCompletedUs"] - draw["nanoUs"] + bounds["offsetLowerUs"] - bounds["bootMinusMonoUpperUs"] - 1) / 1000,
               "drawEndToFirstRawUpperMs": (raw["readCompletedUs"] - draw["nanoUs"] + bounds["offsetUpperUs"] - bounds["bootMinusMonoLowerUs"] + 1) / 1000,
               "earliestOnVideoObserved": len(matches) == 1}
        if matches:
            on_video = trace["clockOriginUs"] + matches[0]["elapsedUs"]
            if not raw["readCompletedUs"] <= on_video <= snapshot_us:
                raise ValueError("earliest onVideo precedes raw receipt or follows snapshot")
            row["firstRawToFirstOnVideoMs"] = (on_video - raw["readCompletedUs"]) / 1000
            row["firstOnVideoToSnapshotMs"] = (snapshot_us - on_video) / 1000
        rows.append(row)
    return {"complete": True, "diagnosticOnly": True, "frames": len(frames),
            "clockIntervalWidthMs": bounds["intervalWidthUs"] / 1000,
            "boundary": "same player HTTP body and raw receipts; snapshot callback, not physical scan-out",
            "assumptions": run["clockBounds"]["assumptions"], "samples": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--ffmpeg", required=True)
    args = parser.parse_args()
    for name in ("player-decode.log", "player-frames.json", "player-first-counter.json"):
        if (args.run / name).exists():
            raise FileExistsError("Refusing to replace existing evidence: " + name)
    run = json.loads((args.run / "result.json").read_text())
    if len(run.get("packetArchives", [])) != 1:
        raise ValueError("expected one exported player archive")
    directory = run["packetArchives"][0]["directory"]
    if Path(directory).name != directory:
        raise ValueError("archive must be an immediate evidence child")
    directory = args.run / directory
    archive = json.loads((directory / "archive.json").read_text())
    origin = archive["frames"][0]["sourcePtsUs"] - archive["frames"][0]["ptsUs"]
    frames, log = decode_frames(directory / "capture.mkv", args.ffmpeg, origin)
    report = correlate_player(run, archive, frames)
    (args.run / "player-decode.log").write_text(log)
    (args.run / "player-frames.json").write_text(json.dumps(frames, indent=2))
    (args.run / "player-first-counter.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
