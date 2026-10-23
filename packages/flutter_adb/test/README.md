# Typed ADB extraction verification

Verified on 2026-10-23 in the Linux workspace. The controlled Android target was
`emulator-5556`, configured with the Android 36 Google APIs x86_64 image and
explicitly authorized TCP endpoint `127.0.0.1:15556`. The packaged official
platform-tools version was 37.0.1. This is Linux-host/Android-AVD evidence; it
does not establish USB/OEM or Android/iOS host acceptance of every service.

## Host and protocol checks

- `CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=4 cargo test -p interop-adb --lib --tests -- --test-threads=4`:
  96 tests passed; 13 explicitly gated device, network, pairing or kernel-permission
  fixtures were ignored. This includes the new classic ADB duplex/interactive
  shell fixtures and official smart-socket duplex/stale-transport fixtures.
- The subsequent `binder_argv_command_quoting_and_reboot_ack_keep_protocol_boundaries`
  fixture separately verifies NUL-separated Binder argv, quoted `cmd` arguments,
  binary/exit output and reboot OPEN acknowledgement, without rebooting a device.
- `cargo test -p interop-bridge --lib adb_api::tests -- --test-threads=4`:
  both tests passed, covering worker cleanup before cancellation returns and one
  pending 64 KiB writer with a blocked acknowledgement.
- `cargo clippy -p interop-adb -p interop-bridge --all-targets -- -D warnings`:
  passed. Scoped Dart static analysis passed without issues.
- `flutter test --no-pub` in `packages/flutter_adb`: 16 passed, one explicitly
  configured official-daemon device test skipped. Tests include pull backpressure,
  simultaneous read/write, input chunking, source-failure identity, stalled-source
  cancellation, PTY controls, non-UTF8 names/large signed metadata, reverse
  cancellation, client-local close and a late connect released during close.

## Real typed service composition

```
INTEROP_ADB_SERVICES_AVD=127.0.0.1:15556 flutter test --no-pub test/adb_services_native_test.dart
```

Run in `packages/device_runtime`, using its generated adapter and native asset.
The test passed. It started a new private official server with the authorized
fixture key and used its fixed transport ID through smart sockets. It verified:

- Official transport facts and consistent connection handles from discovery.
- Binary stdin/stdout/stderr and exit code 7 in an interactive shell, plus exec.
- A 4096-byte SYNC stream round trip, stat/lstat/list, each advertised compression
  algorithm, regular-file pull and refusal to overwrite an existing destination.
- An explicit JDWP snapshot, allocated reverse listener creation/list/removal.
- Cancellation of a blocked service while the owning device connection remains
  usable, and an explicit denied remote path.
- Removal of its own remote temporary file, connection disconnect, private server
  termination and temporary local directory cleanup.

The device foreground and other ADB servers were left untouched. The test did
not invoke reboot, tcpip or usb; their protocol acknowledgement/response paths
are covered by host fixtures. No new capture or performance claim is made here.
The final Dart-only close-scoping refinement was verified by the client ownership
unit tests; it does not change the Rust wire service contract.
