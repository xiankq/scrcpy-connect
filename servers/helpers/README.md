# Android filesystem helper

独立 Rust 源码位于 `rust/adb/device_fs_helper`，通过已授权 ADB 以 shell UID 执行：

```text
interop-rename rename-no-replace SOURCE DESTINATION
interop-rename publish-replace SOURCE DESTINATION
interop-rename stat PATH UNUSED
interop-rename lstat PATH UNUSED
interop-rename list PATH LIMIT
```

参数保留原始路径字节；stdout 为有界 JSON，不输出路径。rename 使用原子系统调用，无 copy/delete 回退；`lstat/list` 不跟随末端 symlink，列表错误不冒充完整成功，`nameHex` 保留原始名称。

```sh
dart --disable-dart-dev servers/helpers/build.dart
dart --disable-dart-dev servers/helpers/build.dart --check
dart --disable-dart-dev servers/helpers/build.dart --rebuild
cargo +1.99.1 test --locked --manifest-path rust/adb/device_fs_helper/Cargo.toml
```

根目录先 `flutter pub get`。构建使用 Rust 1.99.1、NDK 30.0.16248370 和四个 Android ABI；`ANDROID_NDK_HOME` 可选择该版本安装。`--check` 离线核对，`--rebuild` 比较而不替换；源码变化须更新全部产物和 manifest。

[file_helper.rs](../../rust/adb/api/src/file_helper.rs) 为每次执行独占创建私有目录，核验已打开 executable 的字节后从同一 FD 执行。未知执行结果不自动重放；只清理本次创建租约授权的目录。共享打包见[工具链](../../docs/implementation/repository-tooling.md)。
