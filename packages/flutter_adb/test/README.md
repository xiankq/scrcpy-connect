# ADB service tests

Run from the repository root:

```sh
flutter test --no-pub packages/flutter_adb
cargo test -p interop-adb --lib --tests
cargo test -p interop-bridge --lib adb_api::tests
```

These cover Dart service ownership, bounded duplex I/O/cancellation and Rust framing/transport pinning. Reboot/tcpip/usb are protocol fixtures; routine device tests do not invoke them.

For real typed composition, run in `packages/device_runtime`:

```sh
INTEROP_ADB_SERVICES_AVD=127.0.0.1:15556 \
  flutter test --no-pub test/adb_services_native_test.dart
```

The endpoint must be an explicitly authorized dedicated target. Set `INTEROP_ADB_KEY` to its test key; otherwise the test uses `~/.android/adbkey`. The test creates a private official server and directory, verifies binary shell/SYNC, advertised compression, JDWP/reverse and cancellation, then removes only its temporary file/listener/transport/server. It leaves the target foreground and other ADB servers untouched.

Device/network/pairing/kernel fixtures remain gated; skipped fixtures are not passing device evidence. [Recorded environment and limits](../VALIDATION.md).
