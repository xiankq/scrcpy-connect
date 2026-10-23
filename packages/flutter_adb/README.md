# flutter_adb

One ADB service API over an owned official desktop server or mobile Rust ADB. Device identity, reconnect policy and durable file tasks belong to callers; see [architecture](../../docs/implementation/architecture.md).

`FlutterAdb.prepare(dataDirectory: ...)` selects the backend. Desktop requires the pinned executable in `adb/` beside the app (`Contents/Resources/adb` on macOS); `binaryDirectory` is a test override. It never falls back to PATH or direct desktop adbd. After the native library is ready, call `host.bindNative(adapter)` on every platform. `device_runtime` supplies the generated `NativeAdbApi` adapter without being a dependency of this package.

`host.client` provides `devices/connect/disconnect/pair`, binary shell events and regular-file push/pull. `client.services` adds:

| Group | API and constraints |
| --- | --- |
| Facts/raw | `connectionFacts`, `open`, `connectSocket`, `exec`, bounded `serviceResponse`; raw services have no generic stdin half-close |
| Shell/Binder | `shell`, `abb`, `abb(exec: true)`, `cmd`; shell_v2 supports separate binary stdout/stderr, exit, stdin, `closeStdin` and PTY `resize`. Legacy shell retains merged output/unknown exit |
| Controls | `reboot`, `tcpip`, `usb` acknowledge requests, not reconnection |
| SYNC | `stat/lstat/list/push/pull/pushFile/pullFile`; raw-byte names, bounded data and explicit none/Brotli/LZ4/Zstd compression |
| JDWP | `jdwp`, `trackJdwp`; bounded PID snapshots, not app identities |
| Reverse | `reverse`, `reverseList`, `reverseRemove`, `reverseRemoveAll`; the last affects all device listeners |

Desktop services pin the official server's transport ID; reconnect requires a new handle. Each session allows one pull-based reader and one pending write of at most 64 KiB. Stream pause applies backpressure; cancellation/`close()` drains the service without closing its device. `addStream` chunks input and cancels its producer on close. Use SYNC `finish()` or shell `closeStdin()` for EOF; do not write concurrently. Cancellation, deadlines and abandoned-handle expiry bound work.

Push may leave a remote partial. Pull refuses an existing destination and removes its own partial on failure. A stalled streaming producer may delay remote SYNC status; cancellation/deadlines still apply. Byte paths are literal; string paths are UTF-8 without shell expansion.

`capabilities` exposes backend differences: desktop `authorize:false` only reuses an authorized transport; forced TLS requires a discovered secure mDNS fullname. Android mobile alone supports `connectUsbFd`. The API does not wrap every adb CLI command or elevate target permissions.

Close the host after device activity cleanup. Its private loopback server and commands are owned resources; closing never kills another program's server. Bundled artifact preparation is in `tool/prepare_adb.dart`. See [test setup](test/README.md) and [validation](VALIDATION.md).
