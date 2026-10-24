# ADB service tests

Run from the repository root:

```sh
(cd packages/adb && flutter test --no-pub)
cargo test -p interop-adb --lib --tests
cargo test -p interop-adb-api --lib
```

These cover Dart service ownership, bounded duplex I/O/cancellation, file scopes, real local metadata and RSA identity receipts, and Rust framing/transport pinning. Run the native tests from the package directory so Flutter includes its Native Assets hook; the repository tooling workspace has no direct SDK dependency. Reboot/tcpip/usb are protocol fixtures; routine device tests do not invoke them.

真实私有服务器用例需显式指定仓库准备的受控二进制，不查找 PATH 中的 adb：

```sh
(cd packages/adb && INTEROP_OFFICIAL_ADB_BINARY=/absolute/path/to/pinned/adb \
  flutter test --no-pub test/owned_server_close_test.dart \
    test/owned_server_isolate_test.dart test/owned_server_lifecycle_test.dart \
    test/owned_server_process_interop_test.dart)
```

这些用例核验实际服务器和本机协议，包括 isolate 退出后的认领，以及持续存活的 Dart 子进程与原生 CLI 并存时的真实退出回执；没有已授权 Android 目标时，不构成设备连接验收。

应用组合仍在迁移，旧业务桥生成引用已移除，下面的应用设备用例暂不能作为当前可运行入口或本轮通过证据。完成生产接线后从 `app` 显式启用：

```sh
INTEROP_ADB_SERVICES_AVD=127.0.0.1:15556 \
  flutter test --no-pub test/application/native/adb_services_native_test.dart
```

The endpoint must be an explicitly authorized dedicated target. Set `INTEROP_ADB_KEY` to its test key; otherwise the test uses `~/.android/adbkey`. The test creates a private official server and directory, verifies binary shell/SYNC, advertised compression, JDWP/reverse and cancellation, then removes only its temporary file/listener/transport/server. It leaves the target foreground and other ADB servers untouched.

Device/network/pairing/kernel fixtures remain gated; skipped fixtures are not passing device evidence. [Recorded environment and limits](../VALIDATION.md).
