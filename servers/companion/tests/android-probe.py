#!/usr/bin/env python3
"""Official adb is a test harness only; product traffic uses the Rust host library.

Runs temporary shell JARs, synthetic notifications and virtual-modem calls on the
explicit target AVD. No APK/root/permission grant or AppOp changes are performed.
"""
import argparse
import json
import selectors
import socket
import subprocess
import time
import uuid
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--adb", required=True)
parser.add_argument("--serial", required=True)
parser.add_argument("--calls", action="store_true", help="simulate and control virtual-modem calls")
parser.add_argument("--skip-receiver", action="store_true", help="do not assert standalone receiver delivery; PI submission is still tested")
options = parser.parse_args()
if not options.serial.startswith("emulator-"):
    raise SystemExit("This harness only creates calls on an explicit Android emulator")
root = Path(__file__).resolve().parents[1]
base = [options.adb, "-s", options.serial]


def adb(*args):
    return subprocess.run(base + list(args), check=True, capture_output=True, text=True)


def line(process, timeout=15):
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    if not selector.select(timeout):
        raise AssertionError("temporary JAR output timed out")
    value = process.stdout.readline()
    if not value:
        raise AssertionError("temporary JAR exited: " + process.stderr.read()[-2048:])
    return value.strip()


name = "interop-companion-" + uuid.uuid4().hex
secret = uuid.uuid4().hex + uuid.uuid4().hex
port = 15561
process = fixture = connection = transport = None
events = []
counter = 0
try:
    adb("push", str(root / "companion.jar"), "/data/local/tmp/interop-companion-probe.jar")
    adb("push", "/tmp/interop-companion-fixture.jar", "/data/local/tmp/interop-companion-fixture.jar")
    process = subprocess.Popen(base + ["shell", "CLASSPATH=/data/local/tmp/interop-companion-probe.jar app_process / com.interop.companion.Main " + name + " " + secret], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert line(process).startswith("INTEROP_COMPANION_READY ")
    adb("forward", "tcp:" + str(port), "localabstract:" + name)
    connection = socket.create_connection(("127.0.0.1", port), 10)
    connection.settimeout(15)
    transport = connection.makefile("rwb", buffering=0)
    transport.write((json.dumps({"token": secret}) + "\n").encode())
    while True:
        ready = json.loads(transport.readline())
        if ready.get("event") == "ready":
            break
        events.append(ready)
    assert ready["uid"] == 2000 and ready["protocol"] == 1
    assert ready["notifications"]["status"] == "available", ready["notifications"].get("reason")

    def request(command, **params):
        global counter
        counter += 1
        request_id = str(counter)
        transport.write((json.dumps(dict(requestId=request_id, command=command, **params)) + "\n").encode())
        while True:
            result = json.loads(transport.readline())
            if result.get("requestId") == request_id:
                return result
            events.append(result)

    def success(command, **params):
        result = request(command, **params)
        assert "error" not in result, result.get("error")
        return result["result"]

    fixture = subprocess.Popen(base + ["shell", "CLASSPATH=/data/local/tmp/interop-companion-fixture.jar app_process / com.interop.companion.Fixture"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    fixture_ready = json.loads(line(fixture))
    assert fixture_ready["event"] == "fixture.ready"
    tag = fixture_ready["tag"]
    deadline = time.monotonic() + 10
    while True:
        notifications = success("notifications.list")["notifications"]
        own = {int(item["title"].rsplit("-", 1)[1]): item for item in notifications if item["title"].startswith(tag)}
        if len(own) == 4:
            break
        assert time.monotonic() < deadline, "all fixture notifications visible"
        time.sleep(.05)
    assert own[0]["canReply"] and not own[1]["canReply"]
    assert any(item.get("event") == "notifications.changed" for item in events), "real Binder callback"
    reply = success("notifications.reply", notificationId=own[0]["id"], text="真实 RemoteInput interoperability")
    assert reply["acceptedBySystem"] and reply["delivered"] is None
    if not options.skip_receiver:
        received = json.loads(line(fixture))
        assert received == {"event": "reply.received", "text": "真实 RemoteInput interoperability"}
    assert request("notifications.reply", notificationId=own[1]["id"], text="must not send")["error"]["code"] == "reply_unavailable"
    assert request("notifications.reply", notificationId=own[2]["id"], text="must not bypass auth")["error"]["code"] == "authentication_required"
    assert request("notifications.open", notificationId=own[3]["id"])["error"]["code"] == "notification_expired"
    opened = success("notifications.open", notificationId=own[0]["id"])
    assert opened["acceptedBySystem"] and opened["located"] and not opened["applicationConfirmed"]
    foreground = adb("shell", "dumpsys activity activities").stdout
    assert "com.android.settings/.Settings" in foreground or "com.android.settings.Settings" in foreground
    success("notifications.dismiss", notificationId=own[0]["id"])
    deadline = time.monotonic() + 5
    while own[0]["id"] in [n["id"] for n in success("notifications.list")["notifications"]]:
        assert time.monotonic() < deadline, "remote notification actually cleared"
        time.sleep(.05)
    assert request("notifications.open", notificationId=own[0]["id"])["error"]["code"] == "notification_expired"
    print("PASS: UID2000 live Binder notifications, original PendingIntent, RemoteInput submitted"+ (" (standalone receiver delivery NOT verified)" if options.skip_receiver else " and received")+", immutable/auth/cancelled/stale rejection, actual remote dismissal")

    if options.calls:
        def modem_state(wanted):
            deadline = time.monotonic() + 10
            while True:
                dump = adb("shell", "dumpsys", "telephony.registry").stdout
                modem_matches = any(line.strip() == "mCallState=" + str(wanted) for line in dump.splitlines())
                telecom_idle = wanted != 0 or not adb("shell", "dumpsys", "telecom").stdout.split("  mCalls:", 1)[1].split("  mCallAudioManager:", 1)[0].strip()
                if modem_matches and telecom_idle:
                    return
                assert time.monotonic() < deadline, "actual virtual modem state"
                time.sleep(.025)

        def call_state(wanted):
            deadline = time.monotonic() + 20
            while True:
                value = success("calls.list")
                calls = value["calls"]
                if (not calls and wanted == "idle") or (calls and calls[0]["state"] == wanted):
                    return calls[0] if calls else None
                assert time.monotonic() < deadline, ("call state", wanted, value)
                time.sleep(.1)

        assert not success("calls.list")["calls"], "harness does not disturb an existing call"
        adb("emu", "gsm", "call", "5550101234")
        ringing = call_state("ringing")
        for action in ["answer", "reject", "hangup"]:
            assert request("calls.action", callId=ringing["id"], action=action)["error"]["code"] == "call_targeting_unavailable"
        assert call_state("ringing")["id"] == ringing["id"]
        adb("emu", "gsm", "cancel", "5550101234")
        modem_state(0)
        adb("emu", "gsm", "call", "5550101235")
        modem_state(1)
        call_state("ringing")
        assert request("calls.action", callId=ringing["id"], action="reject")["error"]["code"] == "call_targeting_unavailable"
        call_state("ringing")
        adb("emu", "gsm", "cancel", "5550101235")
        adb("emu", "gsm", "cancel", "5550101234")
        adb("shell", "input", "keyevent", "KEYCODE_ENDCALL")
        call_state("idle")
        assert any(item.get("event") == "calls.incoming" for item in events), "real TelephonyRegistry callback"
        print("PASS: real virtual-modem callbacks, rapid replacement remains ringing after old action; all unsafe aggregate controls refused; no call-audio claim")

finally:
    if options.calls:
        subprocess.run(base + ["emu", "gsm", "cancel", "5550101234"], capture_output=True)
        subprocess.run(base + ["emu", "gsm", "cancel", "5550101235"], capture_output=True)
        subprocess.run(base + ["shell", "input", "keyevent", "KEYCODE_ENDCALL"], capture_output=True)
    if fixture is not None and fixture.poll() is None:
        try:
            fixture.stdin.write("quit\n"); fixture.stdin.flush(); fixture.wait(timeout=10)
        except Exception:
            fixture.terminate()
    if transport is not None:
        transport.close()
    if connection is not None:
        connection.close()
    if process is not None:
        try:
            process.wait(timeout=10)
            assert process.returncode == 0, "socket EOF unregisters listeners and exits: "+process.stderr.read()[-2048:]
        except subprocess.TimeoutExpired:
            process.terminate()
    subprocess.run(base + ["forward", "--remove", "tcp:" + str(port)], capture_output=True)
    subprocess.run(base + ["shell", "rm -f /data/local/tmp/interop-companion-probe.jar /data/local/tmp/interop-companion-fixture.jar"], capture_output=True)
