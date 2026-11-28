# Android 文件助手

`interop-rename` 是一个在被控手机上以 shell 用户身份运行的 Rust 小程序，用来做 ADB 自身做不到的安全文件操作。源码在 `rust/adb/device_fs_helper`。

## 命令

```text
interop-rename rename-no-replace SOURCE DESTINATION
interop-rename rename-expected:IDENTITY SOURCE DESTINATION
interop-rename delete-expected:IDENTITY SOURCE UNUSED
interop-rename publish-replace SOURCE DESTINATION
interop-rename stat PATH UNUSED
interop-rename lstat PATH UNUSED
interop-rename list PATH LIMIT
```

- 路径参数按原始字节传递，不做编码转换。
- 输出是限定大小的 JSON，写到 stdout。输出里一般不含路径；文件名放在 `nameHex`（原始字节的十六进制）。
- `lstat` 和 `list` 不跟随路径末尾的符号链接。`list` 读取出错时报告错误，不返回一个看起来完整的列表。

## 对象身份

`stat`/`lstat`/`list` 返回的 `identity` 由设备号、inode 和 ctime（秒和纳秒）组成，调用方当作不透明值使用。

- 删除和重命名必须带上用户选中对象时拿到的 `identity`。缺少身份的旧 SYNC 数据不能用来授权修改。
- 执行时助手先用 `O_PATH | O_NOFOLLOW` 打开并固定该对象，核对身份，再把它原子移进本次独占创建的同目录隔离目录 `.interop-mutation-*`。
- 移入后再比较隔离对象的设备号和 inode 是否与固定的文件描述符一致，一致才删除或发布到目标名。这里不比较 ctime，因为重命名本身会改 ctime。
- 原路径已被换成同名的其他对象时返回 `ESTALE`。

## 重命名和删除

- 重命名只用原子系统调用，失败时不会退回"复制后删除"。
- 源和目标的父目录都先打开并固定。递归删除基于已打开的目录进行，子项是符号链接时不会删到目录树外面。
- 删除的是执行时选中目录里的内容，没有快照：执行期间在原名称处新建的目录不会被删。
- 失败时助手只用"不覆盖"方式把对象改回原名，绝不覆盖新出现的对象。改回也失败时，对象留在隔离目录，助手在 `recoveryPathHex` 里返回它的原始路径字节；主控向用户显示这个位置，不自动重试。
- 递归删除中途中断时，选中目录可能已被删掉一部分。主控应刷新目录让用户核对。
- 手机断开可能留下 `.interop-mutation-*` 隔离目录。不要按名称批量清理它们，里面可能是用户还没恢复的文件。

## 主控如何执行

[file_helper.rs](../../rust/adb/api/src/file_helper.rs) 每次执行都新建一个私有目录，核对已打开的可执行文件的字节后，从同一个文件描述符执行它。执行结果未知时不自动重放；清理时只删本次创建的目录。

## 构建

先在仓库根目录运行 `flutter pub get`。需要 Rust 1.99.1 和 NDK 30.0.16248370；NDK 默认找 `~/Android/Sdk/ndk/30.0.16248370`，可用 `ANDROID_NDK_HOME` 指定。一次构建四个 Android ABI。

```sh
# 源码变化后：更新全部产物、manifest 和共享资源
dart --disable-dart-dev servers/build.dart --update helpers assets
# 离线核对
dart --disable-dart-dev servers/build.dart --check helpers
# 临时重建并比较，不替换产物
dart --disable-dart-dev servers/build.dart --rebuild helpers
# 单元测试
cargo +1.99.1 test --locked --manifest-path rust/adb/device_fs_helper/Cargo.toml
```

打包进应用的方式见[构建说明](../README.md)。
