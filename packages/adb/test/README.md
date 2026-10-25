# ADB 测试

从仓库根运行；Flutter 用例须在包内执行以启用 Native Assets：

```sh
(cd packages/adb && flutter test --no-pub)
cargo test -p interop-adb --lib --tests
cargo test -p interop-adb-api --lib
```

实际私有 server 用例设置 `INTEROP_OFFICIAL_ADB_BINARY=/absolute/path/to/pinned/adb`，不查找 PATH。应用设备入口：

```sh
cd app
INTEROP_ADB_SERVICES_AVD=127.0.0.1:15556 \
  flutter test --no-pub test/application/native/adb_services_native_test.dart
```

使用专用已授权目标；`INTEROP_ADB_KEY` 选择测试私钥，缺省为 `~/.android/adbkey`。用例只清理自有文件、listener、连接与私有 server。缺环境跳过不代表设备通过。
