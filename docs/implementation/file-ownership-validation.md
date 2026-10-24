# 文件所有者验收

从 `app/` 运行应用文件所有者测试：

```sh
flutter test --no-pub test/files test/media/cache \
  test/application/transport/file_commands_test.dart \
  test/application/events/application_events_test.dart
```

该入口覆盖浏览与快照、冲突、提交未知、取消、日志恢复与压缩、租约交接、清理失败重试及删除历史保留文件。目录测试位于 `test/files/catalog/`，持久传输入口为 `transfer_coordinator_test.dart`，变更生命周期由 `file_mutation_lifecycle_test.dart` 验证；`file_commands_test.dart` 验证命令字段映射和各所有者关闭隔离，应用事件回归验证目录与传输事件的统一同步序列。`file_transfer_cleanup_test.dart` 验证传输精确执行对象与缓存预算，`media_preview_cleanup_test.dart` 验证预览实际 worker 与缓存 writer 的回收顺序。当前原生文件回归位于 `rust/adb/api/src/` 的 `file_system`、`file_scope_tests`、`file_metadata` 和 `file_publication`；分享来源保留与缓存账本分别由 `app/test/files/` 和 `app/test/media/cache/` 验证。旧 Rust 文件执行、来源及缓存测试已随旧所有者移除，不能继续作为当前复现入口。

技术执行域换代的真实 Rust 回归从工作区顶层运行：

```sh
cargo test --locked -p interop-adb-api --lib file_system::scope_tests
cargo test --locked -p interop-adb-api --lib admission_scope::file_tests
```

这两组回归核验旧操作与暂存描述符排空、关闭失败重试及父准入换代；新 scope 只证明前代本机执行资源释放，不确认远端提交结果。

应用与真实原生执行组合的设备入口从 `app/` 运行：

```sh
INTEROP_FILES_AVD=<已授权端点> INTEROP_ADB_KEY=<测试身份> \
  flutter test --no-pub test/application/native/files_native_test.dart
```

未设置 `INTEROP_FILES_AVD` 时跳过。`INTEROP_ADB_KEY` 选择已授权测试私钥，默认 `~/.android/adbkey`。测试须使用专用已授权目标；它建立唯一远端/本机目录和私有官方 ADB server，仅把测试密钥复制到临时运行目录，并清理自己的资源。验证二进制传输、搜索、冲突、组合活动状态、取消与所有者重启后的日志恢复。

2026-10-23 的包迁移前版本已在 Linux x86_64 与 Android API 36 AVD 通过；本次架构迁移的实际结果见[重构记录](architecture-refactor-validation.md#分享来源交接纳入停止)。其他主控或 OEM 需要独立证据。组合测试调用应用 Dart 文件所有者，原生能力测试不代替应用任务与恢复验收。
