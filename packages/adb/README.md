# adb

给应用提供 ADB 能力的 Flutter 包。

- 桌面（Windows、macOS、Linux）：使用随应用打包的官方 ADB，并由应用启动和管理自己的 ADB server。
- 移动端（Android、iOS）：使用 Rust 实现的 ADB（[rust/adb](../../rust/adb/README.md)）直接连接手机。
- 本包不负责：设备记录、断线重连、需要持久保存的文件任务。这些由应用负责。

```dart
final bindings = await createNativeAdbApi();
final host = await AdbHost.prepare(
  bindings: bindings,
  dataDirectory: dataDirectory,
);
final devices = await host.client.devices();
// 退出前：先关闭所有设备上的活动，再 await host.close()。
```

## 打包与加载

- ADB 可执行文件的位置：Windows 和 Linux 在应用可执行文件旁的 `platform-tools/` 目录；macOS 在应用包的 `Contents/Helpers/`。用 `binaryDirectory` 参数可以指定其他目录。
- 桌面构建按[锁文件](third_party/platform-tools.lock.json)下载、校验并打包 ADB 和许可声明。Windows、macOS、Linux x64 使用 Google Platform-Tools；Linux ARM64 使用 Ubuntu 24.04 的原生 ADB 和配套库，组装时需要 `dpkg-deb` 和 `patchelf`。
- `initializeNativeAdb()` 只初始化 Dart 与原生库的绑定。移动端第一次连接时才创建持久的 ADB 身份（密钥）；已有身份文件损坏时不会被覆盖。
- 启用 Dart 原生资产链接时，独立的 ADB 动态库由链接钩子（`hook/link.dart`）按应用实际调用的接口构建；调试构建等未启用链接的情况由构建钩子（`hook/build.dart`）提供完整库。Cargo 产物统一放在仓库根的 `target/`，清理方法见[脚本说明](../../scripts/README.md#清理构建缓存)。

## 和 scrcpy 一起用

与 scrcpy 包一起使用时，注入 scrcpy 包提供的配套 ADB bindings（见 [scrcpy](../scrcpy/README.md)）。

**不同动态库创建的设备、scope 和操作句柄不能混用；初始化后不能更换动态库。**

## 谁有权关闭什么

- `AdbDevice.id` 是操作该设备的凭证：持有它才能操作和关闭设备连接。
- `connectionFacts.connectionId` 只在当前进程内标识一条连接。
- PID、序列号、地址端口、磁盘上的配置都不能当作关闭凭证。

## 服务与关闭

`host.client` 提供连接、配对和常用的 shell/push/pull。`client.services` 提供更底层的能力：原始服务、双向 shell/exec、SYNC、JDWP、reverse 和 OPEN 探针。参数和类型以公开 Dart 接口为准。

- 每个 session 同时只能有一个读取者和一个进行中的写入。暂停读取会让对端停止发送（背压）。
- 结束输入：上传调用 `finish()`，shell 调用 `closeStdin()`。普通的原始流不支持只关闭写入方向。
- 事件流结束时如果没有收到真正的终止结果，结果为 `result_unknown`。旧版 shell 的 stdout/stderr 合并输出，退出码未知，这些仍按原样保留。"已写出"、"设备已执行"和"需要重连"是三种不同结果，不要合并。
- 取消只是发出通知；`close()` 才会等到这次占用的资源释放完。`close()` 失败时保留同一个对象再次调用，不要关闭共享的客户端来代替。
- `sync.openPush()` 可以先拿到 session，再同时读事件和写输入；创建结果晚到时也能处理。
- Push 中断可能在手机上留下写了一半的文件。Pull 不覆盖本地已有文件，失败时只删除它自己写的部分。
- 路径按字节原样传输，不经过 shell 展开。
- `reverseRemoveAll` 会删除手机上所有 reverse 监听，包括其他程序建立的。
- `createOpenProbe` 返回的探针要单独关闭。关闭失败时 `AdbOpenProbeCleanupFailure.probe` 里是原探针，用它重试。探针在写出数据前超时，记为排队超时。

## 连接错误

按 `AdbException.code` 判断错误类型：

| code | 含义与处理 |
| --- | --- |
| TCP 连接失败 / `handshake_timeout` | 两种错误分开报告：前者连不上地址，后者连上了但握手超时。 |
| `pairing_result_unknown` | 不知道配对是否成功。不要自动重试。取消配对不会撤销手机上已建立的信任。 |
| `adb_cleanup_unconfirmed` | 资源释放未确认，原资源还需要继续清理。 |
| `official_connect_result_unknown` | 见下文。 |

**收到 `official_connect_result_unknown` 后，必须关闭原 ADB server，再准备一个新的宿主。** 这时不知道 server 是否已经建立了连接。CLI 退出、定向 `disconnect`、新建客户端或新 isolate 都无法消除这种不确定。原 server 不再接受新命令，但已经交给调用方的连接仍可以正常释放。`client.close()` 不等于 server 已确认退出。

## isolate 重启后接管

isolate 重启后，用原生层保存的当前 lease（本包的授权凭证）和 scope 比对后换发新的操作权限：

1. 用 `AdbHost.prepare` 或 `AdbHost.restore` 恢复宿主，必须显式传入同一个动态库的 bindings。
2. 先等旧的握手和还没交付的资源处理完。
3. 再用 `claimConnection` 认领已交付的连接。底层连接和已有的捕获保持不变，旧句柄作废。
4. server 和设备连接分别认领。认领失败时保留原对象重试。

## 移动端直连、配对和 USB

- 移动端直连、配对和 USB 连接用 `AdbCancellation` 取消。
- 需要单独重试 USB 清理时，先用 `beginUsbFdConnection` 拿到并保存这次 attempt。连接成功交付后，由连接负责关闭。
- Android 的 `UsbDeviceConnection` 对象必须一直保留，直到 SDK 断开，或未交付的 attempt 确认已清理。
- 官方 server 的握手使用 server 的权限，不借用移动端的连接准入 scope。

## 本机文件

`createNativeLocalFiles()` 不需要设备连接。调用方提供允许访问的根目录、容量预算和截止时间。

- 只支持 Linux 和 Android：使用目录文件描述符、核对每个临时片段的真实身份、提交时不覆盖已有文件。其他系统明确返回不支持。
- **提交结果未知时，不重放提交，也不删除可能已经发布的目标文件。**
- 从其他 provider 借来的文件描述符，其原有占用要保留到复制或关闭确认完成。
- `attachFileScope` 接管父 scope 前，必须先等旧的 worker 和文件描述符处理完。清理未确认的部分继续计入容量。

## 进程监督

- Linux：监督官方 ADB 进程需要 pidfd、可执行 memfd 和 `/proc/self/fd`。
- Windows：使用原生进程句柄。
- macOS：目前没有同样精确的监督方式。

构建方式见[脚本说明](../../scripts/README.md)。
