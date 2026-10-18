#!/usr/bin/env python3
"""Lab-only raw H264 drain to locate first new-counter packets offline.

Uses a dedicated authorized target and official host adb for deployment only.
No product/Flutter performance qualification; no server rebuild or changes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import socket
import struct
import subprocess
import threading
import time
import uuid


def exact(stream, size):
    data = bytearray()
    while len(data) < size:
        chunk = stream.recv(size - len(data))
        if not chunk:
            raise EOFError("incomplete scrcpy packet")
        data.extend(chunk)
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--jar", required=True, type=Path)
    parser.add_argument("--fixture", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    args.out.mkdir(exist_ok=False)
    package = "dev.scrcpyconnect.videofixture"
    run = uuid.uuid4().hex
    name = "interop.firstcounter." + run
    remote = "/data/local/tmp/interop-firstcounter-" + run + ".jar"
    scid = int(run[:7], 16)
    port = process = video = control = reader = None
    installed = False
    closing = threading.Event()
    packets, errors = [], []
    result = {"run": run, "jarSha256": hashlib.sha256(args.jar.read_bytes()).hexdigest(),
              "scope": "host raw drain, not Flutter or real wireless latency acceptance",
              "quality": {"maxSize": 1280, "maxFps": 60, "bitRate": 8000000},
              "inputs": [], "measurementComplete": False, "complete": False, "cleanupErrors": {}}

    def adb(*command, check=True):
        p = subprocess.run([args.adb, "-s", args.target, *command],
                           capture_output=True, timeout=20)
        if check:
            p.check_returncode()
        return p.stdout.decode().strip()

    def succeeds(*command):
        return subprocess.run([args.adb, "-s", args.target, *command],
                              capture_output=True, timeout=20).returncode == 0

    def clocks():
        values = []
        for _ in range(3):
            before = time.monotonic_ns() // 1000
            uptime = adb("exec-out", "cat", "/proc/uptime").split()[0]
            after = time.monotonic_ns() // 1000
            seconds, fraction = uptime.split(".")
            assert len(fraction) == 2
            values.append({"hostBeforeUs": before, "hostAfterUs": after,
                           "targetBootUs": int(seconds) * 1000000 + int(fraction) * 10000})
        return values

    def read():
        try:
            result["deviceName"] = exact(video, 64).split(b"\0")[0].decode()
            assert exact(video, 4) == b"h264"
            offset = 0
            with (args.out / "capture.h264").open("xb") as output:
                while not closing.is_set():
                    flags, size = struct.unpack(">QI", exact(video, 12))
                    if flags >> 63:
                        assert not packets and "width" not in result, "capture generation changed"
                        result["width"], result["height"] = struct.unpack(">II", struct.pack(">QI", flags, size)[4:])
                        continue
                    assert 0 < size <= 16 * 1024 * 1024
                    data = exact(video, size)
                    received = time.monotonic_ns() // 1000
                    assert offset + size <= 128 * 1024 * 1024
                    output.write(data)
                    packets.append({"offset": offset, "size": size,
                                    "config": bool(flags & (1 << 62)),
                                    "keyframe": bool(flags & (1 << 61)),
                                    "sourcePtsUs": flags & ((1 << 61) - 1),
                                    "receivedHostUs": received})
                    offset += size
        except Exception as error:
            if not closing.is_set():
                errors.append(repr(error))

    def wait(seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if errors:
                raise RuntimeError(errors)
            if process is not None and process.poll() is not None:
                raise RuntimeError("server exited before drain completed")
            time.sleep(.025)

    try:
        assert not adb("shell", "pm", "path", package, check=False), "fixture already installed"
        adb("install", "--no-streaming", str(args.fixture))
        installed = True
        adb("shell", "am", "start", "-W", "-n", package + "/.VideoPatternActivity",
            "--ez", "motion", "true", "--es", "timelineRun", run)
        adb("push", str(args.jar), remote)
        port = int(adb("forward", "tcp:0", f"localabstract:scrcpy_{scid:08x}"))
        options = ["app_process", "/", "--nice-name=" + name, "com.genymobile.scrcpy.Server", "5.0.1",
                   f"scid={scid:08x}", "log_level=info", "video=true", "audio=false", "control=true",
                   "video_codec=h264", "video_encoder=c2.android.avc.encoder", "max_size=1280", "max_fps=60",
                   "video_bit_rate=8000000", "video_codec_options=repeat-previous-frame-after:long=33334",
                   "tunnel_forward=true", "cleanup=true", "clipboard_autosync=false", "power_on=false",
                   "send_dummy_byte=true", "send_device_meta=true", "send_stream_meta=true", "send_frame_meta=true"]
        command = "CLASSPATH=" + shlex.quote(remote) + " exec " + " ".join(map(shlex.quote, options))
        with (args.out / "server.log").open("xb") as log:
            process = subprocess.Popen([args.adb, "-s", args.target, "shell", command],
                                       stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT)
        end = time.monotonic() + 10
        while time.monotonic() < end:
            attempt = None
            try:
                attempt = socket.create_connection(("127.0.0.1", port), 1)
                attempt.settimeout(3)
                assert exact(attempt, 1) == b"\0"
                video = attempt
                break
            except (OSError, EOFError):
                if attempt:
                    attempt.close()
                time.sleep(.05)
        assert video is not None
        control = socket.create_connection(("127.0.0.1", port), 3)
        video.settimeout(8)
        reader = threading.Thread(target=read, daemon=True)
        reader.start()
        wait(2)
        result["clockBefore"] = clocks()
        for sequence in range(1, 9):
            before = time.monotonic_ns() // 1000
            for action in (0, 1):
                control.sendall(struct.pack(">BBIII", 0, action, 20, 0, 0))
            result["inputs"].append({"sequence": sequence, "counter": sequence,
                                     "hostBeforeSendUs": before,
                                     "hostAfterSendUs": time.monotonic_ns() // 1000})
            wait(1.5)
        result["clockAfter"] = clocks()
        wait(.5)
        result["measurementComplete"] = True
    except Exception as error:
        result["error"] = repr(error)
    finally:
        def cleanup(label, operation):
            try:
                result[label] = operation()
            except Exception as error:
                result["cleanupErrors"][label] = repr(error)
                result[label] = False

        closing.set()
        for stream in (video, control):
            if stream:
                try:
                    stream.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                try:
                    stream.close()
                except OSError as error:
                    result["cleanupErrors"]["socketClose"] = repr(error)
        if reader:
            reader.join(10)
            result["readerStopped"] = not reader.is_alive()
        def stop_shell():
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
            return process.returncode
        if process:
            cleanup("serverShellExit", stop_shell)

        def save_timeline():
            timeline = []
            log = adb("logcat", "-d", "-v", "brief", "ConnectVideoClock:I", "*:S")
            (args.out / "target-logcat.txt").write_text(log)
            for line in log.splitlines():
                start = line.find('{"run":')
                if start >= 0:
                    event = json.loads(line[start:])
                    if event.get("run") == run:
                        timeline.append(event)
            (args.out / "target-timeline.json").write_text(json.dumps(timeline, indent=2))
            return True
        cleanup("timelineWritten", save_timeline)
        def save_packets():
            (args.out / "packets.json").write_text(json.dumps(
                {"width": result.get("width"), "height": result.get("height"), "packets": packets}, indent=2))
            return True
        cleanup("packetLedgerWritten", save_packets)
        if port:
            cleanup("forwardRemoved", lambda: succeeds("forward", "--remove", "tcp:" + str(port)))
        cleanup("remoteRemoveAttempted", lambda: succeeds("shell", "rm", "-f", remote))
        cleanup("processAbsent", lambda: not adb("shell", "pidof", name, check=False))
        cleanup("jarAbsent", lambda: succeeds("shell", "test", "!", "-e", remote))
        if installed:
            cleanup("uninstall", lambda: adb("uninstall", package))
        cleanup("fixtureAbsent", lambda: not adb("shell", "pm", "path", package, check=False))
        cleanup("settingsRestored", lambda: succeeds("shell", "am", "start", "-W", "-a", "android.settings.SETTINGS"))
        result["readerErrors"] = errors
        required = ("measurementComplete", "readerStopped", "processAbsent", "fixtureAbsent",
                    "jarAbsent", "forwardRemoved", "timelineWritten", "packetLedgerWritten")
        result["complete"] = (all(result.get(key) is True for key in required)
                              and result.get("serverShellExit") == 0 and not errors and not result["cleanupErrors"])
        (args.out / "result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0 if result["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
