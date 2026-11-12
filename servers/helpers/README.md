# Android filesystem helper

独立 Rust 源码位于 `rust/adb/device_fs_helper`，通过已授权 ADB 以 shell UID 执行：

```text
interop-rename rename-no-replace SOURCE DESTINATION
interop-rename rename-expected:IDENTITY SOURCE DESTINATION
interop-rename delete-expected:IDENTITY SOURCE UNUSED
interop-rename publish-replace SOURCE DESTINATION
interop-rename stat PATH UNUSED
interop-rename lstat PATH UNUSED
interop-rename list PATH LIMIT
```

参数保留原始路径字节；stdout 为有界 JSON；通常不输出路径，无法恢复隔离对象时以 `recoveryPathHex` 返回其原始路径字节。rename 使用原子系统调用，无 copy/delete 回退；`lstat/list` 不跟随末端 symlink，列表错误不冒充完整成功，`nameHex` 保留原始名称。元数据的 `identity` 是设备、inode 与 ctime（秒及纳秒）组成的不透明对象身份；删除和重命名必须传入选择时的身份，在助手执行变更时以 `O_PATH | O_NOFOLLOW` 固定并核验对象，再原子移入本次独占的同目录隔离目录；只有隔离对象的 dev/inode 与固定 FD 一致，才能删除或发布到目标名称。rename 自身改变 ctime，隔离后的核验因此比较被固定的 dev/inode。同名替换返回 `ESTALE`，缺少身份的旧 SYNC 数据不能授权变更。

源与目标父目录均固定为 FD。递归删除相对于已打开目录进行，子项 symlink 不会导向外部树；删除作用于选中根目录执行时的内容，不提供子树快照。原名称后来出现的新目录不参与删除。失败时仅以 noreplace 恢复源名称，绝不覆盖新对象；恢复失败保留隔离对象并返回 `recoveryPathHex`，宿主显示恢复位置，不自动重试。目录递归中断可能已删除部分选中目录的内容，应刷新核对。设备中断可能留下同目录 `.interop-mutation-*` 隔离目录，不能按名称批量清理。

```sh
dart --disable-dart-dev servers/build.dart --update helpers assets
dart --disable-dart-dev servers/build.dart --check helpers
dart --disable-dart-dev servers/build.dart --rebuild helpers
cargo +1.99.1 test --locked --manifest-path rust/adb/device_fs_helper/Cargo.toml
```

根目录先 `flutter pub get`。构建使用 Rust 1.99.1、NDK 30.0.16248370 和四个 Android ABI；`ANDROID_NDK_HOME` 可选择该版本安装。`--check` 离线核对，`--rebuild` 比较而不替换；源码变化须更新全部产物和 manifest。

[file_helper.rs](../../rust/adb/api/src/file_helper.rs) 为每次执行独占创建私有目录，核验已打开 executable 的字节后从同一 FD 执行。未知执行结果不自动重放；只清理本次创建租约授权的目录。共享打包见[脚本入口](../../scripts/README.md)。
