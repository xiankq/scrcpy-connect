#!/usr/bin/env python3
"""Matched real-device cold server starts; never builds or replaces a server JAR.

This is an official-ADB/source-component experiment, not a Flutter end-to-end
startup benchmark. Each round is baseline/candidate/baseline, sequentially.
The lab fixture must initially be absent; the run installs and removes it.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import signal
import socket
import statistics
import struct
import subprocess
import sys
import time
import uuid


FIXTURE = "dev.scrcpyconnect.videofixture"
ENCODER = "c2.android.avc.encoder"
MAX_PACKET = 16 * 1024 * 1024
MAX_CAPTURE = 48 * 1024 * 1024
REPO = Path(__file__).resolve().parents[2]


def remaining(deadline):
    seconds = deadline - time.monotonic()
    if seconds <= 0:
        raise TimeoutError("absolute server startup deadline expired")
    return seconds


def exact(sock, length, deadline=None):
    data = bytearray()
    while len(data) < length:
        if deadline is not None:
            sock.settimeout(remaining(deadline))
        part = sock.recv(length - len(data))
        if not part:
            raise EOFError(f"video EOF after {len(data)}/{length} bytes")
        data.extend(part)
    return bytes(data)


def first_media(sock, sample, spawned, deadline=None):
    """Read the actual scrcpy wire through the first complete media packet."""
    device = exact(sock, 64, deadline).split(b"\0", 1)[0].decode("utf-8")
    codec = exact(sock, 4, deadline)
    sample["timestampsNs"]["header"] = time.monotonic_ns()
    if codec != b"h264":
        raise ValueError(f"unexpected codec id: {codec!r}")
    sample["deviceName"] = device
    sample["codec"] = codec.decode()
    packets = []
    total = 0
    configured = False
    for _ in range(128):
        header = exact(sock, 12, deadline)
        flags, length = struct.unpack(">QI", header)
        if flags & (1 << 63):
            if "session" in sample:
                raise ValueError("session reset before first media")
            width, height = struct.unpack(">II", header[4:])
            if not 0 < width <= 1280 or not 0 < height <= 1280:
                raise ValueError(f"invalid session dimensions: {width}x{height}")
            sample["session"] = {"width": width, "height": height}
            sample["timestampsNs"]["session"] = time.monotonic_ns()
            continue
        if "session" not in sample:
            raise ValueError("packet before session metadata")
        if not 0 < length <= MAX_PACKET:
            raise ValueError(f"invalid packet length: {length}")
        total += length
        if total > MAX_CAPTURE:
            raise ValueError("first media capture exceeded byte limit")
        payload = exact(sock, length, deadline)
        packets.append(payload)
        if flags & (1 << 62):
            configured = True
            sample["timestampsNs"].setdefault("config", time.monotonic_ns())
            continue
        if not configured:
            raise ValueError("first media arrived without codec configuration")
        sample["timestampsNs"]["firstMedia"] = time.monotonic_ns()
        sample["firstMedia"] = {
            "ptsUs": flags & ((1 << 61) - 1),
            "keyFrame": bool(flags & (1 << 61)),
            "packetBytes": length,
            "encodedBytes": total,
            "configPackets": len(packets) - 1,
        }
        sample["elapsedMs"] = {
            key: (value - spawned) / 1_000_000
            for key, value in sample["timestampsNs"].items()
        }
        return b"".join(packets)
    raise ValueError("too many packets before first media")


def allocation_lines(log):
    return [line for line in log.splitlines()
            if re.search(r"\bCCodec\s*:", line)
            and "allocate(c2.android.avc.encoder)" in line]


def decode_first(ffmpeg, data, directory, expected):
    # showinfo sees the native frame before scale; oracle reads only the first
    # decoded frame, never a later frame which might hide an incorrect startup.
    decoded = subprocess.run(
        [ffmpeg, "-nostdin", "-hide_banner", "-v", "info", "-threads", "1",
         "-f", "h264", "-i", "pipe:0", "-vf", "showinfo,scale=64:64",
         "-frames:v", "1", "-pix_fmt", "rgba", "-f", "rawvideo", "pipe:1"],
        input=data, capture_output=True, timeout=20,
    )
    log = decoded.stderr.decode("utf-8", errors="replace")
    (directory / "ffmpeg.log").write_text(log)
    decoded.check_returncode()
    dimensions = [(int(w), int(h)) for w, h in re.findall(
        r"Parsed_showinfo_0[^\n]*\bs:(\d+)x(\d+)\b", log)]
    wanted = (expected["width"], expected["height"])
    if not dimensions or any(size != wanted for size in dimensions):
        raise ValueError(f"decoded native dimensions {dimensions} != {wanted}")
    rgba = decoded.stdout
    if len(rgba) != 64 * 64 * 4:
        raise ValueError(f"expected one 64x64 RGBA frame, got {len(rgba)} bytes")
    (directory / "first-frame-64.rgba").write_bytes(rgba)
    counter = 0
    colors = []
    for bit, x in enumerate((8, 24, 40, 56)):
        r, g, b, _ = rgba[(32 * 64 + x) * 4:(32 * 64 + x) * 4 + 4]
        colors.append([r, g, b])
        if not ((r > 150 and b < 150) or (r < 150 and b > 150)):
            raise ValueError(f"fixture oracle is not red/blue at ({x},32): {(r,g,b)}")
        if r > 150:
            counter |= 1 << bit
    if counter != 0:
        raise ValueError(f"first decoded fixture counter {counter}, expected 0")
    return {"counter": counter, "centersRgb": colors,
            "nativeWidth": wanted[0], "nativeHeight": wanted[1]}


class Device:
    def __init__(self, executable, target):
        self.prefix = [executable, "-s", target]

    def run(self, *args, check=True, timeout=20):
        result = subprocess.run(self.prefix + list(args), capture_output=True, timeout=timeout)
        if check and result.returncode:
            raise RuntimeError(f"adb {args!r}: {result.stderr.decode(errors='replace').strip()} "
                               f"{result.stdout.decode(errors='replace').strip()}")
        return result

    def text(self, *args, **kwargs):
        return self.run(*args, **kwargs).stdout.decode(errors="replace").strip()

    def fixture_present(self):
        return self.text("shell", "pm", "path", FIXTURE, check=False).startswith("package:")

    def identity(self, name):
        value = self.text("shell", "pidof", name, check=False)
        if not value:
            return None
        if not value.isdigit():
            raise RuntimeError(f"ambiguous PID for {name}: {value!r}")
        actual = self.run("shell", "cat", f"/proc/{value}/cmdline", check=False).stdout
        if actual.split(b"\0", 1)[0] != name.encode():
            raise RuntimeError(f"PID {value} no longer has expected identity {name}")
        return value

    def kill_exact(self, pid, name, sig):
        # Recheck on-device immediately before killing: never kill by broad name,
        # server class, or an unverified remembered PID.
        script = (f"actual=$(tr '\\000' '\\n' </proc/{pid}/cmdline 2>/dev/null | head -n 1); "
                  f"[ \"$actual\" = {shlex.quote(name)} ] && kill -{sig} {pid}")
        self.run("shell", script, check=False)


def server_options(remote, name, scid):
    args = ["app_process", "/", f"--nice-name={name}",
            "com.genymobile.scrcpy.Server", "5.0.1", f"scid={scid:08x}",
            "log_level=info", "video=true", "audio=false", "control=true",
            "video_codec=h264", f"video_encoder={ENCODER}", "max_size=1280",
            "max_fps=60", "video_bit_rate=8000000",
            "video_codec_options=repeat-previous-frame-after:long=33334",
            "tunnel_forward=true", "cleanup=true", "clipboard_autosync=false",
            "power_on=false", "send_dummy_byte=true", "send_device_meta=true",
            "send_stream_meta=true", "send_frame_meta=true"]
    return f"CLASSPATH={shlex.quote(remote)} exec " + " ".join(map(shlex.quote, args))


def sample_start(device, args, label, jar, digest, directory, run_id, index):
    directory.mkdir()
    name = f"connect.startup.{run_id}.{index}"
    remote = f"/data/local/tmp/connect-startup-{digest}-{run_id}-{index}.jar"
    scid = int(uuid.uuid4().hex[:8], 16) & 0x7fffffff
    sample = {"label": label, "jarSha256": digest, "name": name,
              "remoteJar": remote, "scid": f"{scid:08x}", "timestampsNs": {},
              "expectedAllocations": 1 if label == "candidate" else 2}
    video = control = process = log_file = None
    port = None
    cleanup_errors = []
    try:
        # Exactly one fixture start per sample, with a new Activity/counter zero.
        device.run("shell", "am", "start", "-S", "-W", "-n",
                   FIXTURE + "/.VideoPatternActivity", "--ez", "motion", "false")
        time.sleep(args.fixture_settle)
        device.run("push", str(jar), remote)
        port = int(device.text("forward", "tcp:0", f"localabstract:scrcpy_{scid:08x}"))
        sample["forwardPort"] = port
        command = server_options(remote, name, scid)
        sample["serverCommand"] = command
        log_file = (directory / "server.log").open("wb")
        spawned = time.monotonic_ns()
        sample["timestampsNs"]["spawn"] = spawned
        process = subprocess.Popen(device.prefix + ["shell", command], stdin=subprocess.PIPE,
                                   stdout=log_file, stderr=subprocess.STDOUT)
        deadline = spawned / 1_000_000_000 + args.timeout
        while time.monotonic() < deadline:
            trial = None
            try:
                trial = socket.create_connection(("127.0.0.1", port),
                                                 timeout=min(.5, remaining(deadline)))
                connected = time.monotonic_ns()
                if exact(trial, 1, deadline) != b"\0":
                    trial.close()
                    raise ValueError("invalid scrcpy dummy byte")
                video = trial
                sample["timestampsNs"]["connected"] = connected
                sample["timestampsNs"]["dummy"] = time.monotonic_ns()
                break
            except (OSError, EOFError):
                if trial:
                    trial.close()
                if process.poll() is not None:
                    raise RuntimeError(f"server exited before connect ({process.returncode})")
                time.sleep(.01)
        if video is None:
            raise TimeoutError("server video connection timed out")
        control = socket.create_connection(("127.0.0.1", port), timeout=remaining(deadline))
        encoded = first_media(video, sample, spawned, deadline)
        (directory / "first-media.h264").write_bytes(encoded)
        pid = device.identity(name)
        if pid is None:
            raise RuntimeError("server disappeared before allocation evidence")
        sample["pid"] = int(pid)
        # Let already-issued native log writes reach logd; no log clearing and no
        # unscoped logcat dump. Measurement timestamps were all captured above.
        time.sleep(.15)
        log = device.text("logcat", "-b", "main", "-d", f"--pid={pid}",
                          "-v", "threadtime", "-s", "CCodec:V", "*:S")
        (directory / "ccodec.log").write_text(log + "\n")
        lines = allocation_lines(log)
        sample["allocationEvidence"] = {"beforeStop": True, "count": len(lines), "lines": lines}
        if len(lines) != sample["expectedAllocations"]:
            raise ValueError(f"{label}: got {len(lines)} encoder allocations, "
                             f"expected {sample['expectedAllocations']}")
        sample["complete"] = True
    except BaseException as error:
        sample["complete"] = False
        sample["error"] = f"{type(error).__name__}: {error}"
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            sample["terminatedEarly"] = True
    finally:
        for connection in (video, control):
            if connection:
                try:
                    connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                connection.close()

        def clean(label, action):
            try:
                sample.setdefault("cleanup", {})[label] = action()
            except BaseException as error:
                cleanup_errors.append(f"{label}: {type(error).__name__}: {error}")

        def stop_server():
            if process:
                try:
                    process.wait(timeout=7)
                except subprocess.TimeoutExpired:
                    pass
            pid = device.identity(name)
            if pid:
                device.kill_exact(pid, name, 15)
                time.sleep(.3)
                if device.identity(name):
                    device.kill_exact(pid, name, 9)
                    time.sleep(.2)
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
            if process:
                sample["serverShellExit"] = process.returncode
                if process.stdin:
                    process.stdin.close()
            if device.identity(name):
                raise RuntimeError("exact server process still present")
            return True

        clean("processAbsent", stop_server)
        if port is not None:
            clean("forwardRemoved", lambda: device.run("forward", "--remove", f"tcp:{port}").returncode == 0)

        def remove_jar():
            device.run("shell", "rm", "-f", remote)
            if device.run("shell", "test", "!", "-e", remote, check=False).returncode:
                raise RuntimeError("remote temporary JAR remains")
            return True

        clean("jarAbsent", remove_jar)
        if log_file:
            log_file.close()
        if cleanup_errors:
            sample["cleanupErrors"] = cleanup_errors
            sample["complete"] = False
    if sample.get("complete"):
        try:
            sample["oracle"] = decode_first(args.ffmpeg, encoded, directory, sample["session"])
        except BaseException as error:
            sample["complete"] = False
            sample["error"] = f"{type(error).__name__}: {error}"
            if isinstance(error, (KeyboardInterrupt, SystemExit)):
                sample["terminatedEarly"] = True
    (directory / "result.json").write_text(json.dumps(sample, indent=2) + "\n")
    return sample


def summarize(samples):
    pairs = []
    for offset in range(0, len(samples) - 2, 3):
        before, candidate, after = samples[offset:offset + 3]
        if not all(sample.get("complete") for sample in (before, candidate, after)):
            continue
        reference = (before["elapsedMs"]["firstMedia"] + after["elapsedMs"]["firstMedia"]) / 2
        measured = candidate["elapsedMs"]["firstMedia"]
        pairs.append({"round": offset // 3 + 1, "baselineBracketMeanMs": reference,
                      "candidateMs": measured, "candidateMinusBaselineMs": measured - reference})
    summary = {"matchedRounds": pairs}
    if pairs:
        summary["medianCandidateMinusBaselineMs"] = statistics.median(
            row["candidateMinusBaselineMs"] for row in pairs)
    for label in ("baseline-before", "candidate", "baseline-after"):
        values = [sample["elapsedMs"]["firstMedia"] for sample in samples
                  if sample["label"] == label and sample.get("complete")]
        if values:
            summary[label] = {"samples": len(values), "medianFirstMediaMs": statistics.median(values),
                              "minFirstMediaMs": min(values), "maxFirstMediaMs": max(values)}
    return summary


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default=shutil.which("adb") or str(Path.home() / "Android/Sdk/platform-tools/adb"))
    parser.add_argument("--target", default="emulator-5556")
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True,
                        help="new absolute output directory outside this repository")
    parser.add_argument("--rounds", type=int, default=5, help="number of sequential A/B/A triplets")
    parser.add_argument("--fixture-apk", type=Path, default=Path("/tmp/connect-video-fixture/video-fixture.apk"))
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "/tmp/connect-video-tools/imageio_ffmpeg/binaries/ffmpeg-linux-x86_64-v7.0.2")
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("--fixture-settle", type=float, default=.5)
    args = parser.parse_args(argv)
    if args.rounds < 1 or args.timeout <= 0 or args.fixture_settle < 0:
        parser.error("rounds and timeout must be positive; fixture-settle must be nonnegative")
    if not args.output.is_absolute() or args.output.resolve().is_relative_to(REPO):
        parser.error("output must be an absolute directory outside the repository")
    if args.output.exists():
        parser.error("output directory already exists")
    for path in (args.baseline, args.candidate, args.fixture_apk):
        if not path.is_file():
            parser.error(f"input file missing: {path}")
    for executable in (args.adb, args.ffmpeg):
        if not shutil.which(executable):
            parser.error(f"executable missing: {executable}")
    return args


def main(argv=None):
    args = parse_args(argv)
    args.output.mkdir(parents=True)
    run_id = uuid.uuid4().hex
    device = Device(args.adb, args.target)
    artifacts = {name: {"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                 for name, path in (("baseline", args.baseline), ("candidate", args.candidate))}
    result = {"run": run_id, "target": args.target, "artifacts": artifacts, "samples": [],
              "mode": "official adb source-component cold server startup; not Flutter end-to-end",
              "timing": "host monotonic_ns; spawn before adb shell Popen; milestones on full receipt; "
                        "excludes fixture start, JAR deployment, forwarding and offline decoding",
              "order": "sequential baseline-before/candidate/baseline-after per round",
              "roundsRequested": args.rounds, "complete": False}
    settings = {}
    fixture_owned = False
    cleanup_errors = []
    try:
        if device.text("get-state") != "device":
            raise RuntimeError("ADB target is not ready")
        if device.fixture_present():
            raise RuntimeError("fixture already installed; refusing to alter or uninstall a preexisting fixture")
        for key in ("accelerometer_rotation", "user_rotation"):
            settings[key] = device.text("shell", "settings", "get", "system", key)
        for key in settings:
            device.run("shell", "settings", "put", "system", key, "0")
        fixture_owned = True  # Known absent before this install, including partial installation failures.
        device.run("install", "--no-streaming", str(args.fixture_apk), timeout=60)
        for round_index in range(args.rounds):
            for label, kind in (("baseline-before", "baseline"), ("candidate", "candidate"),
                                ("baseline-after", "baseline")):
                index = len(result["samples"]) + 1
                directory = args.output / f"{round_index + 1:02d}-{label}"
                artifact = artifacts[kind]
                sample = sample_start(device, args, label, Path(artifact["path"]), artifact["sha256"],
                                      directory, run_id, index)
                sample["round"] = round_index + 1
                result["samples"].append(sample)
                result["summary"] = summarize(result["samples"])
                (args.output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
                print(f"round {round_index + 1} {label}: " +
                      (f"{sample['elapsedMs']['firstMedia']:.3f} ms; "
                       f"allocations={sample['allocationEvidence']['count']}" if sample["complete"] else
                       f"FAILED {sample.get('error', sample.get('cleanupErrors'))}"), flush=True)
                if not sample["complete"]:
                    raise RuntimeError(f"sample {index} failed; see {directory / 'result.json'}")
        dimensions = {(sample["oracle"]["nativeWidth"], sample["oracle"]["nativeHeight"])
                      for sample in result["samples"]}
        if len(dimensions) != 1:
            raise ValueError(f"full-resolution dimensions differ between samples: {dimensions}")
        result["complete"] = True
    except BaseException as error:
        result["error"] = f"{type(error).__name__}: {error}"
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            result["terminatedEarly"] = True
    finally:
        if fixture_owned:
            try:
                if device.fixture_present():
                    device.run("uninstall", FIXTURE)
                if device.fixture_present():
                    raise RuntimeError("fixture still installed")
                result["fixtureAbsent"] = True
            except BaseException as error:
                cleanup_errors.append(f"fixture: {error}")
        for key, value in settings.items():
            try:
                operation = ("delete", "system", key) if value == "null" else ("put", "system", key, value)
                device.run("shell", "settings", *operation)
                if device.text("shell", "settings", "get", "system", key) != value:
                    raise RuntimeError("restored value differs")
            except BaseException as error:
                cleanup_errors.append(f"setting {key}: {error}")
        result["settingsRestored"] = not any(error.startswith("setting ") for error in cleanup_errors)
        if cleanup_errors:
            result["cleanupErrors"] = cleanup_errors
            result["complete"] = False
        result["summary"] = summarize(result["samples"])
        (args.output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"complete": result["complete"], "output": str(args.output),
                      "summary": result["summary"], "error": result.get("error")}), flush=True)
    return 0 if result["complete"] else 1


def interrupted(signum, _frame):
    raise SystemExit(f"received signal {signum}")


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
