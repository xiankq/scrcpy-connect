#!/usr/bin/env python3
"""Offline exact-PTS join of every decoded frame to the original raw receipt.

Run remux_capture_packets first. A later snapshot cannot establish the earliest
new pixel; this analysis requires a complete one-to-one decoded packet ledger.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess


def correlate(capture, timeline, run, frames):
    required = ("complete", "measurementComplete", "readerStopped", "processAbsent",
                "fixtureAbsent", "jarAbsent", "forwardRemoved", "timelineWritten", "packetLedgerWritten")
    if (any(run.get(key) is not True for key in required)
            or run.get("serverShellExit") != 0 or run.get("readerErrors") != []
            or run.get("cleanupErrors") != {}):
        raise ValueError("capture or cleanup did not complete")
    media = [p for p in capture["packets"] if not p["config"]]
    pts = [p["sourcePtsUs"] for p in media]
    if not pts or len(set(pts)) != len(pts) or len(frames) != len(pts):
        raise ValueError("incomplete/ambiguous decoded packet ledger")
    if [f["sourcePtsUs"] for f in frames] != pts:
        raise ValueError("decoded PTS differ from the complete media ledger")
    if any(a["receivedHostUs"] > b["receivedHostUs"] for a, b in zip(media, media[1:])):
        raise ValueError("raw receipts are out of order")
    expected = run["inputs"]
    if [x["sequence"] for x in expected] != list(range(1, 9)):
        raise ValueError("expected eight unique input sequences")
    if [x["counter"] for x in expected] != list(range(1, 9)):
        raise ValueError("counter wrap is not supported by this narrow lab run")
    for kind in ("input", "draw"):
        actual = [e for e in timeline if e["kind"] == kind and e["sequence"] != 0]
        if sorted(e["sequence"] for e in actual) != list(range(1, 9)):
            raise ValueError("missing/duplicate fixture input or first draw")
    initial = [e for e in timeline if e["kind"] == "draw" and e["sequence"] == 0]
    if len(initial) != 1:
        raise ValueError("fixture reset or missing initial draw")
    if any(e["run"] != run["run"] or e["kind"] not in ("input", "draw") for e in timeline):
        raise ValueError("unrelated or unknown timeline event")
    probes = run["clockBefore"] + run["clockAfter"]
    if len(probes) != 6 or any(p["hostAfterUs"] < p["hostBeforeUs"] for p in probes):
        raise ValueError("incomplete clock brackets")
    # /proc/uptime is quantized down to 10ms. This is an interval model under
    # constant offset/no suspend, not a synchronized point clock.
    low = max(p["targetBootUs"] - p["hostAfterUs"] for p in probes)
    high = min(p["targetBootUs"] + 10000 - p["hostBeforeUs"] for p in probes)
    if low > high:
        raise ValueError("inconsistent clock brackets")
    counters = [f["counter"] for f in frames]
    if counters[0] != 0 or counters[-1] != 8 or any(a > b or b > a + 1 for a, b in zip(counters, counters[1:])):
        raise ValueError("skipped, reverted or missing terminal counter")
    draws = {e["sequence"]: e for e in timeline if e["kind"] == "draw"}
    inputs = {e["sequence"]: e for e in timeline if e["kind"] == "input"}
    rows = []
    for key in expected:
        seq = key["sequence"]
        draw, target_input = draws[seq], inputs[seq]
        if draw["counter"] != seq or target_input["counter"] != seq or draw["nanoUs"] < target_input["nanoUs"]:
            raise ValueError("fixture counter/time mismatch")
        if not draw["bootBeforeUs"] <= draw["bootAfterUs"]:
            raise ValueError("inverted target clock observation")
        frame = counters.index(seq)
        packet = media[frame]
        received = packet["receivedHostUs"]
        if not probes[0]["hostBeforeUs"] <= key["hostBeforeSendUs"] <= received <= probes[-1]["hostAfterUs"]:
            raise ValueError("first packet lies outside observed input/calibration")
        rows.append({"sequence": seq, "firstFrameIndex": frame, "sourcePtsUs": packet["sourcePtsUs"],
                     "inputToFirstRawMs": (received - key["hostBeforeSendUs"]) / 1000,
                     "drawEndToFirstRawLowerMs": (received - draw["bootAfterUs"] + low) / 1000,
                     "drawEndToFirstRawUpperMs": (received - draw["bootBeforeUs"] + high) / 1000})
    return {"complete": True, "clockIntervalWidthMs": (high - low) / 1000,
            "assumptions": ["constant host/target boot clock offset during the bracketed run", "no suspend or clock step"],
            "boundary": "earliest decoded new-counter packet at host raw drain; not Flutter latency, encoder CPU or glass-to-glass",
            "packets": len(media), "frames": len(frames), "samples": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--ffmpeg", required=True)
    args = parser.parse_args()
    directory = args.capture
    for name in ("decode.log", "decoded-frames.json", "first-counter.json"):
        if (directory / name).exists():
            raise FileExistsError(f"Refusing to replace existing evidence: {name}")
    capture = json.loads((directory / "packets.json").read_text())
    run = json.loads((directory / "result.json").read_text())
    if not run["complete"]:
        raise ValueError("capture failed")
    media = [p for p in capture["packets"] if not p["config"]]
    origin = media[0]["sourcePtsUs"]
    frames, log = decode_frames(directory / "capture.mkv", args.ffmpeg, origin)
    (directory / "decode.log").write_text(log)
    report = correlate(capture, json.loads((directory / "target-timeline.json").read_text()), run, frames)
    (directory / "decoded-frames.json").write_text(json.dumps(frames, indent=2))
    (directory / "first-counter.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


def decode_frames(path, ffmpeg, origin):
    decoded = subprocess.run([ffmpeg, "-nostdin", "-hide_banner", "-xerror", "-threads", "1",
                              "-i", str(path), "-vf", "scale=64:64,format=rgba,showinfo",
                              "-fps_mode", "passthrough", "-f", "rawvideo", "pipe:1"],
                             capture_output=True, timeout=90, check=True)
    log = decoded.stderr.decode()
    if "config in time_base: 1/1000000" not in log:
        raise ValueError("unexpected decoded timestamp timebase")
    observed = re.findall(r"\bn:\s*(\d+)\s+pts:\s*(-?\d+)\s+pts_time:", log)
    if len(decoded.stdout) != len(observed) * 64 * 64 * 4:
        raise ValueError("decoded pixel/PTS count mismatch")
    frames = []
    for index, (number, pts) in enumerate(observed):
        if int(number) != index:
            raise ValueError("non-contiguous decoded frame numbers")
        rgba = decoded.stdout[index * 16384:(index + 1) * 16384]
        counter = 0
        for bit, x in enumerate((8, 24, 40, 56)):
            red, _, blue, _ = rgba[(32 * 64 + x) * 4:(32 * 64 + x) * 4 + 4]
            if not ((red > 150 and blue < 150) or (red < 150 and blue > 150)):
                raise ValueError("unrecognizable decoded counter")
            if red > 150:
                counter |= 1 << bit
        frames.append({"sourcePtsUs": origin + int(pts), "counter": counter})
    return frames, log


if __name__ == "__main__":
    main()
