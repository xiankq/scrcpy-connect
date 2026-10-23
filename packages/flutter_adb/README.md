# flutter_adb

One ADB service API for an owned official desktop adb server and mobile Rust
ADB. Device identity persistence, reconnect policy, file browsing, recursion,
conflicts and durable transfer journals belong to callers.

`FlutterAdb.prepare(dataDirectory: ...)` selects the backend. Desktop loads the
pinned executable from `adb/` beside the app (`Contents/Resources/adb` on macOS).
`binaryDirectory` is an explicit test override; missing binaries and startup
failures never fall back to PATH or direct desktop adbd. Attach the real typed
`NativeAdbApi` adapter with `host.bindNative(adapter)` on **every** platform after
its native library is ready. The adapter contract is independent: this package
does not import device_runtime. That package supplies one generated FRB adapter.
Desktop discovery/pairing/connection control remains in official adb; all deep
services use the official server's fixed transport ID through Rust smart
sockets. A reconnect requires a new connection handle. Existing handles never
silently select a replacement device transport.

`host.client` retains `devices/connect/disconnect/pair`, binary noninteractive
shell events and regular-file `push/pull`. `client.services` also exposes the
public service capabilities already implemented by interop-adb:

| API group | Public methods and semantics |
| --- | --- |
| Connection facts | `connectionFacts`: negotiated features, closed status; direct framing version/payload/burst or official transport ID. Official framing facts are unknown, not invented. |
| Raw services | `open`, `connectSocket` (TCP/JDWP/vsock/local sockets), `exec`, `serviceResponse` with explicit output bounds. Raw services have no generic stdin half-close. |
| Interactive shell/Binder | `shell` with raw/PTY, `abb`, `abb(exec: true)`, `cmd`; separate binary stdout/stderr, exit status, stdin, `closeStdin`, PTY `resize`. shell_v2 is required for interactive sessions; legacy noninteractive shell keeps its actual merged-output/unknown-exit semantics. |
| Device controls | `reboot`, `tcpip`, `usb`. Completion acknowledges the request; it does not promise boot/reconnection. |
| SYNC | `sync(device).stat/lstat/list/push/pull/pushFile/pullFile`, raw byte paths/names, bounded entries/bytes, actual metadata precision, explicit none/Brotli/LZ4/Zstd compression. Unsupported compression fails; no silent algorithm substitution. |
| JDWP | `jdwp`, `trackJdwp`, bounded PID counts, explicit empty snapshots. PIDs are not application identities. |
| Reverse | `reverse`, `reverseList`, `reverseRemove`, `reverseRemoveAll`; TCP/local sockets and connection-owned host relay/listener resources. `reverseRemoveAll` explicitly affects all device listeners. |

Each session has one pull-based event reader, one pending write of at most
64 KiB, and bounded native queues. Reads progress while writes await ADB ACKs.
Pausing the event stream applies backpressure; cancelling it or `close()` stops
that service and drains its worker, without closing the device. `addStream`
chunks input and cancels its producer when the session closes. SYNC streaming
push uses `finish()` for end of file; shell uses `closeStdin()`. Do not send
parallel writes. Explicit `AdbCancellation` interrupts pending service work;
every operation also has a bounded deadline. Abandoned handles expire.
Bytes cross the typed binding seam, never JSON/base64. File-to-file transfers
keep their bytes on the native filesystem.

Push can leave a partial remote file after interruption, as original adb does.
Pull refuses an existing local destination and removes a file it created on
failure. SYNC streaming push can observe remote status only when the underlying
SYNC operation reads that status; cancellation and the deadline remain available
while its producer stalls. No operation elevates Android permissions. Raw byte
paths support Android filenames that are not UTF-8; convenience string paths
are UTF-8, without shell expansion.

`capabilities` records real backend differences. Official adb cannot suppress an
Android authorization prompt: `authorize: false` only reuses an already
authorized server transport. Forced desktop TLS requires an officially
discovered secure mDNS fullname and fails without that evidence. Mobile retains
strict direct TLS/authorization policy and Android's platform-authorized USB
file-descriptor import. `connectUsbFd` stays mobile/Android only. Host transport
construction (`Transport`, pre-negotiated transports, RSA/TLS internals), packet
scheduler priority/read tracing and process-wide daemon management are Rust
integration mechanisms, rather than a Dart device service API.

This API extracts the existing Rust services; it does not claim every official
adb CLI command. In particular it adds no host `forward`, APK install policy,
logcat wrapper, root/remount/verity workflow, server-wide tracking or sideload
stream protocol. Explicit raw services can reach device services but do not
invent unavailable protocol support or bypass official desktop routing.

The host owns one isolated official server and its control subprocesses. Every
CLI call targets numeric `127.0.0.1` and its owned port, preventing automatic
startup of an unowned daemon. Close the host after native device activity
cleanup. `close()` cancels its service connections/commands and waits for its
process; it never sends kill-server to another program's server. Business
identities can use separate official servers with actual RSA key material.

`tool/prepare_adb.dart` verifies pinned artifact hashes and extracts the minimal
runtime with notices. The app installs it without connecting to a device.
Package tests cover typed ownership and fake protocol boundaries; Rust wire
fixtures cover actual framing/ACKs. `device_runtime/test/adb_services_native_test.dart`
requires an explicitly authorized test AVD and exercises the assembled typed
adapter against the owned official server. Device-control commands that reboot
or replace transports are covered by fixtures rather than invoked during that
non-destructive test.
