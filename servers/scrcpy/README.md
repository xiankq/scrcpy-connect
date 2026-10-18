# Cooperative scrcpy capture pause

This is a minimal source patch against scrcpy **v5.0.1**, commit
`a60891aea193d92e7e5c3942700eca63f9d19a5f` (Apache-2.0; upstream license is
retained in `../vendor/LICENSE-scrcpy`). The official JAR in `../vendor/` is
unchanged. This Java code runs only as a temporary service on the **controlled
Android device**. It does not implement native video on the controller; the
existing Rust transport and Flutter/MDK presentation remain the media path.

Normal Flutter/Rust builds embed the committed JAR; they do not rebuild it.
Changes to controller transport, buffering, decoder settings, or UI do not
require a server rebuild. Rebuild when changing the pinned server source,
patch, or build toolchain, or when explicitly verifying reproducibility.
`tool/check.sh` deliberately runs the latter check; it is separate from APK
assembly. Keep the pause extension when using this artifact: the unmodified
official JAR does not implement its control type 128.

Rebuild from the repository root:

```sh
rtk proxy python3 servers/scrcpy/build.py
rtk proxy python3 servers/scrcpy/build.py --check
rtk proxy python3 servers/scrcpy/test.py
```

Requires Python 3.12+, JDK 21 (`javac` on PATH), `patch`, and Android platform 36
with build-tools 36.0.0. Set `ANDROID_HOME` or `ANDROID_SDK_ROOT`, or use the
default `~/Android/Sdk`. The script downloads a SHA-256-pinned source archive,
applies the patch without fuzz, builds with `javac`/`aidl`/`d8`, and emits
`interop-scrcpy-server.jar`, its plain SHA-256 file, and `manifest.json`.
Downloads and intermediates live under ignored `.build/`. The manifest records
source, patch, artifact, and toolchain identity. JAR ZIP metadata is fixed.
`--check` rebuilds into that ignored directory and compares the artifact and
source/patch manifest without replacing tracked files. The default repository
check runs this comparison and the JVM checks; CI installs the pinned SDK and
build tools with JDK 21 before running them.

## Protocol and acknowledgements

Control type **128** is followed by a nonzero sequence (`u64`, big endian) and
one byte (`1` pause, `0` resume). Other boolean bytes and sequence zero are
protocol errors. The response reuses the existing device-message type
`ACK_CLIPBOARD`, carrying the same sequence. The host must share a sequence
namespace with clipboard requests and correlate outstanding capture requests
separately. Official, unpatched servers do not accept this extension.

The controller enqueues a capture request without waiting. The video encoder
signals EOS through its existing reset mechanism. It also bounds each output
wait to 100ms and checks pending capture requests after releasing the current
complete output packet, so delayed or absent output EOS cannot keep it in the
encode loop indefinitely. Ordinary capture without a pending request continues
waiting across output timeouts. A pause may discard the encoder's remaining
unread output; resume starts a new session/configuration and keyframe, rather
than continuing those old references. The 100ms limit applies to the codec read
wait, not socket writes, cleanup, or the complete pause acknowledgement.
It detaches the
capture surface, stops GL work and the codec, releases the **MediaCodec
instance** and input surface, then processes requests at its pause gate. Only
then does it enqueue a pause ACK. A resume ACK means the gate is open, not that
decoded pixels exist; the host must still require the resumed session/config
and a newly decoded frame before enabling input. Failures before the gate do
not produce ACKs. The official sender's bounded queue may drop an ACK, in which
case the host must treat timeout as unconfirmed rather than successful.

Pending capture requests also count as a reset even after `consumeReset()`.
A pause can arrive after the gate opens, while a replacement codec is being
created and no running codec exists to receive EOS. Consuming reset reasons
must not let the encoder enter `encode()` with that request still queued.
The encoder instead completes cleanup and returns to the gate to acknowledge
it. This race is covered by the JVM test before any real-device stress run.

Releasing the encoder is distinct from closing the persistent application
session. The session's resource-admission slot remains reserved while paused;
retaining that slot is intentional because its virtual display/task and
recoverable session still exist.

ScreenCapture releases its mirror, leaving the physical source display intact.
NewDisplayCapture detaches its surface with `setSurface(null)` but retains the
virtual display, its ID, and the real app task; final stop/EOF destroys it using
the upstream cleanup path. Android treats a detached virtual display similarly
to screen-off, so apps may receive normal lifecycle changes. Resume reattaches
a newly created encoder surface to the retained display. Controller, Binder,
display monitoring and the main Looper stay alive throughout. Termination wakes
the gate and never acknowledges uncompleted requests.

This artifact is intended only for screen/application sessions. Encoder listing
and device audio can continue to use the official JAR.

The JVM tests cover the control wire, ACK ordering, pause/resume gating,
display-property reset retention, and termination wakeup using a small codec
stand-in, including a pause during codec recreation after the gate opens.
They do not validate Android Binder, virtual-display lifecycle,
hardware encoder release, or decoded frame delivery; those require device
integration tests.


## Isolated candidate builds

Experimental patches never replace the committed capture JAR. Build into a new
absolute directory outside the repository; an existing directory is rejected
so previous evidence cannot be overwritten:

```sh
rtk proxy python3 servers/scrcpy/build.py --candidate bounded-input \
  --output-dir /tmp/connect-bounded-input-build
rtk proxy python3 servers/scrcpy/test.py --candidate bounded-input \
  --build-dir /tmp/connect-bounded-input-build
rtk proxy python3 -B servers/scrcpy/test_build.py -v
```

The external directory contains extracted pinned sources, classes, DEX, JAR,
SHA-256 and manifest including the candidate patch digest. Omitting
`--candidate` with a new `--output-dir` builds the unchanged baseline through
the same isolated path. Neither form changes `.build/` sources or production
artifacts. `--check` remains a separate production reproducibility operation.
Candidate state tests and real device results are separate gates: compiling a
patch does not establish video latency or lifecycle correctness.
