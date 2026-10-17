# Cooperative capture pause for persistent scrcpy sessions

Research and implementation: 2026-10-17. Scope: controlled-device Java server;
the controller keeps its existing Rust transport and Flutter/MDK renderer.

The existing device reproduction distinguishes main-screen capture that keeps
streaming (Settings can open) from whole-process SIGSTOP (Settings reliably
fails encoder startup). That observation rules out whole-process suspension as
a useful persistent-session pause. It does not by itself prove which Android
Binder transaction causes the failure. The replacement must keep the server's
Binder threads, controller, and main Looper scheduled.

## Chosen seam

The fixed upstream is scrcpy v5.0.1, commit
`a60891aea193d92e7e5c3942700eca63f9d19a5f`. Its encoder already has a narrow
session boundary: capture reset signals EOS, the video thread leaves its encode
loop, stops capture and codec, releases its input surface, then starts another
session. The patch parks that thread at this boundary. It preserves the
upstream codec selection, capture implementation, constraints, retries, stream
framing, and session/configuration emission. See upstream
[SurfaceEncoder](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java)
and [CaptureControl](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/CaptureControl.java).

`NewDisplayCapture.stop()` originally stops GL work while final `release()`
destroys the display. The patch adds `setSurface(null)` to stop the producer
without destroying that display/task, then uses the original `start()` path to
attach the next surface. Android explicitly permits this detach and describes
its effect as similar to screen-off; app lifecycle changes are therefore
expected, and preserving a task does not promise its Activity stays resumed.
For main-screen capture, `ScreenCapture.stop()` releases the temporary mirror,
which leaves the physical source display in place. Sources:
[NewDisplayCapture](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/NewDisplayCapture.java),
[ScreenCapture](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/ScreenCapture.java),
[VirtualDisplay.setSurface](https://developer.android.com/reference/android/hardware/display/VirtualDisplay#setSurface(android.view.Surface)).

The patch **releases each MediaCodec instance**, including the initial
capability-probe instance, before parking. Resume creates an encoder again;
the preserved resource is the real virtual display/task, not an encoder slot.
This does not release the product's resource-admission slot for the persistent
application session. Keeping that reservation while paused is correct: the
display/task and resumable session remain alive until explicitly closed.
Android warns that stopping a codec leaves its instance active and recommends
release to make it available to other clients. Keeping a configured codec and
using `PARAMETER_KEY_SUSPEND` would discard input frames while retaining that
instance, so it does not provide the chosen resource-release contract. Source:
[MediaCodec](https://developer.android.com/reference/android/media/MediaCodec#stop()).

## Wire contract and failure boundaries

Control message 128 carries a nonzero u64 big-endian sequence and a strict
paused byte (1 pause, 0 resume). Its response is the existing device-message
`ACK_CLIPBOARD(sequence)`; host correlation must distinguish capture requests
from clipboard requests in a shared sequence namespace. Parsing/dispatch are
small additions to `ControlMessage`, `ControlMessageReader`, and `Controller`.
The official unpatched reader rejects unknown messages:
[ControlMessageReader](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/control/ControlMessageReader.java).

The controller queues requests without waiting for capture cleanup. A pause
ACK is queued by the encoder at its gate after detach, GL stop, codec stop and
release, and input-surface release. A resume ACK means that gate is open; it
does not claim successful codec startup or decoded pixels. The host must still
wait for the new video session/configuration and real decoded-frame evidence.
No ACK is generated if cleanup throws before reaching the gate. Shutdown wakes
a parked encoder and suppresses pending acknowledgements. Display reset
reasons that arrive during pause remain available for the resumed session.

The upstream device-message sender has a bounded queue and may drop a response
under saturation. A host timeout must therefore remain unconfirmed, not be
translated into capturePaused=true. This also means the transport must keep
draining video during EOS/cleanup; stopping the remote source after blocking
all readers can prevent the encode loop from reaching its gate. Source:
[DeviceMessageSender](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/control/DeviceMessageSender.java).

## Build and validation

Implementation and reproducible build entrypoint: `servers/scrcpy/`.
`manifest.json` records the source archive URL/SHA, patch SHA, output SHA, and
JDK/SDK versions. The official vendor JAR remains unchanged. Two consecutive
local builds produced the same artifact SHA:
`91606a603a49bbea2be37ec500cde44a588483ac3162bc466d23b2f9d840deab`.
The JVM gate/wire checks passed. They cover delayed ACK, EOS request, resume,
ordered requests, display-reset retention, malformed packets, and waking a
paused gate on stop. These checks use a codec stand-in and do not establish
Android runtime behavior.

The main agent subsequently ran the real controlled-device Rust reproduction:
paused main screen followed by Settings startup passed in 5.71 seconds with
this cooperative-pause artifact. The preceding SIGSTOP implementation had
failed that scenario consistently in 11.89 seconds. This is evidence for the
specific regression; it does not establish all multi-window/background flows.

Device acceptance must exercise: paused main screen then Settings startup;
paused application A then application B startup; returning to A with the same
display/task ID; decoded pixels from each resumed encoder session; repeated
pause/resume and display rotation while paused; closing B without stopping A;
EOF/disconnect while parked; and failed resume remaining unconfirmed. Verify
released encoder allocations using device codec diagnostics and confirm that
the server PID remains runnable (not process state T) while paused. The main
agent owns this device verification; this implementation task did not operate
an emulator or assert those tests passed.
