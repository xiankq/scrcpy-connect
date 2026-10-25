# adb

统一使用自有官方桌面 server 或移动 Rust ADB；设备记录、重连与持久文件任务由应用负责。

```dart
final bindings = await createNativeAdbApi();
final host = await AdbHost.prepare(
  bindings: bindings,
  dataDirectory: dataDirectory,
);
final devices = await host.client.devices();
// 先关闭设备活动，再 await host.close()。
```

桌面只使用随包固定的 `adb/`（macOS 为 `Contents/Resources/adb`），不回退 PATH 或直连。`binaryDirectory` 可用于测试。`initializeNativeAdb()` 只初始化绑定；移动连接首次使用时创建持久身份，损坏的已有身份不会被覆盖。

与 scrcpy 组合时注入其配套 ADB bindings。**不同动态库的设备、scope 与操作句柄不能混用**，初始化后不能更换库。`AdbDevice.id` 是操作权限，`connectionFacts.connectionId` 是进程内连接身份；PID、序列号、端点和磁盘配置都不授予关闭权。

## 服务与关闭

`host.client` 提供连接、配对和便捷 shell/push/pull；`client.services` 提供原始服务、双向 shell/exec、SYNC、JDWP、reverse 和 OPEN 探针。类型及参数以公开 Dart 接口为准。

- 每个 session 只允许一个读取者和一个在途写入；暂停产生背压。上传用 `finish()`、shell 用 `closeStdin()` 结束输入，普通 raw stream 不提供通用半关闭。
- 事件缺少真实终态时为 `result_unknown`；旧 shell 的合并输出与未知退出码仍保留。写出、设备执行和重连是不同结果。
- 取消只发通知；`close()` 才等待本次资源释放。关闭失败保留同一对象重试，不关闭共享客户端代偿。`sync.openPush()` 可先保存 session，再并行读事件、写输入，处理迟到创建结果。
- Push 可能留下远端部分文件；pull 拒绝覆盖并仅删除自己的片段。字节路径按原样传输，不作 shell 展开。`reverseRemoveAll` 影响设备上所有 reverse listener。
- `createOpenProbe` 返回单独拥有的探针，最后须关闭；`AdbOpenProbeCleanupFailure.probe` 交回重试权。写出前排队超时不证明对端沉默。

连接错误按 `AdbException.code` 判断。TCP 失败与 `handshake_timeout` 分别报告；`pairing_result_unknown` 不自动重试，取消不撤销对端已建立的信任。`adb_cleanup_unconfirmed` 表示原资源仍须收尾。

**`official_connect_result_unknown` 必须关闭原 server，再准备新宿主。** CLI 退出、定向 disconnect、新客户端或新 isolate 都不能解除未知建连；该 server 暂停新命令，已交付连接仍可释放。`client.close()` 不代替 server 退出确认。

## 接管与本机文件

跨 isolate 恢复通过原生当前 lease/scope 比较并换发权限；先排空旧握手与未交付资源，再认领已交付连接。`claimConnection` 保留底层连接和既有捕获，旧句柄失效。服务器与设备连接分别认领；失败保留原对象重试。`AdbHost.prepare/restore` 必须显式提供同库 bindings。

移动直连、配对和 USB 使用 `AdbCancellation`。需要独立重试 USB 清理时，先以 `beginUsbFdConnection` 保存 attempt；成功交付后连接持有关闭责任。Android 原始 `UsbDeviceConnection` 必须保留到 SDK 断开或未交付 attempt 清理确认。官方握手使用 server 权限，不借移动 admission scope 绕过。

`createNativeLocalFiles()` 无需设备连接；调用方提供授权根、预算和期限。Linux/Android 使用目录 FD、真实片段身份和禁止覆盖提交，其他宿主明确不支持。**提交未知不重放、不删除可能已发布目标**；借入 provider FD 的原租约须保留到复制/关闭确认。`attachFileScope` 的父 scope 接管须先排空旧 worker/FD；清理未确认继续占用容量。

Linux 官方进程监督需要 pidfd、可执行 memfd 和 `/proc/self/fd`；macOS 尚无同等精确监督。Windows 使用原生进程句柄。构建方式见[工具链](../../docs/implementation/repository-tooling.md)，测试入口见[test/README](test/README.md)。
