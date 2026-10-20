# ADB 性能与稳定性：参考实现对照

研究日期：2026-10-19。本项目基线 `6937bd91e1b26e30d166c88d5ab41f6982b3ef54`。本研究实际阅读参考项目源码，复核此前仅根据本地代码与夹具给出的性能判断。以下本项目描述及实验均对应上述修复前基线；随后实施的变更与回归结果见 [ADB 性能修复记录](../implementation/validation.md#协议与持久化回归)。按本轮范围排除本机 adb_dart 与播放器项目。

**结论：不能认定本项目 ADB 整体慢于参考实现。可以确认的改进点是 SYNC 写入合并、部分控制响应与接收循环的耦合、现代协议仍计算发送校验和，以及 Core 的小文件部署和持久化成本。classic ACK、64 KiB SYNC DATA、默认关闭 burst、USB header/payload 分别发送和 TLS 握手生成证书，本身不构成实现落后的证据。**

证据分类：源码事实说明具体机制；本地夹具说明受控条件下的结果；工程推论说明可能影响。本轮没有编译运行参考项目、执行物理设备测速或长时间稳定性测试，也没有用参考项目的声明代替本项目验收。

## 1. 实际核查来源

| 对象 | 固定版本 | 本轮阅读范围 |
| --- | --- | --- |
| AOSP ADB | `9084198a2d4b0f6a0f174260fb42da33485b684d`，沿用既有研究的 Android17 分支快照 | `client/file_sync_client.cpp`、`client/commandline.cpp`、`sockets.cpp`、`transport.cpp`、`transport.h`、`adb.h`、`client/usb_libusb*.cpp`、TLS 与 delayed ACK 文档 |
| Tango / ya-webadb | `7bcec613f3441a7f20bdf3e5e8646bce63fe790d` | daemon transport/dispatcher/socket、SYNC socket/push、stream enqueue |
| Rust libadb | `bc681df985967e083cdd7c02df45f942495393a5` | connection/config/channel/wire、SYNC、split reader/writer |
| dadb | `55cb08849b9b17c1e627156a0de11d91d36034de` | `AdbConnection.kt` 的握手和写入停滞时限，作为超时策略补充 |

来源固定不表示它们等于当前最新发行包。既有兼容性研究及许可边界见 [ADB 开源参照](adb-android-compatibility.md)，协议与产品所有权见 [架构](../implementation/architecture.md)。

## 2. 需要纠正的前序解释

| 原判断中的依据 | 参考源码事实 | 修正 |
| --- | --- | --- |
| 每个 WRTE 等 ACK | AOSP classic、Tango、libadb 都有同一约束 | 协议正常成本；应比较有效包大小、ACK 时点和协商模式 |
| SYNC 只用 64 KiB，原始流可写 1 MiB | AOSP、Tango、libadb 的 SYNC DATA 同样最大 64 KiB | 不能把两种工作负载的包数差当作项目优劣；真正可比的是多条 SYNC 记录如何合并成 ADB WRTE |
| burst 默认关闭 | 官方文档明确其为实验功能，默认关闭 | 当前默认不是偏离官方；Tango 的默认选择不同，也不能直接证明更适合移动主控 |
| 每包 flush、USB header/payload 分别完成 | libadb 每 ADB 包 flush；所查 AOSP libusb 后端也分别同步完成 header 和 payload | 这些行为不是本项目独有；flush 也不等于额外一个网络 RTT |
| 每次 TLS 握手生成证书 | AOSP `FdConnection::DoTlsHandshake` 也这样做 | 不能把生成证书本身当作性能缺陷；本项目明文连接尝试也提前创建 TLS 配置，才是可单独测量的成本 |

来源：[AOSP delayed ACK 说明](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/delayed_ack.md)、[官方 Burst 默认策略](https://developer.android.com/tools/adb#burst_mode)、[libadb 每包 flush](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/base/wire.rs#L196-L217)、[AOSP USB 写入](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/usb_libusb_device.cpp#98)、[AOSP TLS 握手](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp#514)。

## 3. 吞吐：有区分度的差异是 SYNC 写合并

### AOSP 小文件与批量发送

AOSP 对小于 `SYNC_DATA_MAX` 的文件采用 `SendSmallFile`，将 SEND、DATA、DONE 拼成一次本机 socket 写入。大文件仍按 64 KiB DATA 发送。transport 的 `local_socket_flush_outgoing` 可以继续读取本机 socket 中已就绪的数据，直到 EAGAIN 或协商的最大 payload，因此一次 CLI write 不必对应一次 ADB WRTE，实际包数仍取决于调度。[小文件合并](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/file_sync_client.cpp#575)、[文件大小分支](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/file_sync_client.cpp#1083)、[transport 聚合](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/sockets.cpp#177)。

AOSP 还可以积累文件级 SYNC 完成结果，待结果就绪、结束或待确认文件数达到 128 时收集。**这里的文件级 SYNC OKAY 与 transport 的逐包 ADB OKAY 是两层不同的确认**；前者延后收集没有取消 classic 的后者约束。[ReadAcknowledgements](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/file_sync_client.cpp#806)。本项目有逐文件原子提交和持久结果，不能不保留这些语义就照搬 CLI 的批量策略。

### Tango 与 libadb 并非同一种策略

Tango 的 SYNC socket 使用以 `adb.maxPayloadSize` 为大小的 `BufferCombiner`，跨请求头、内容和多条 DATA 记录聚合，读取响应或发送 DONE 后 flush。其 DATA 仍是 64 KiB，缓冲的是外层 ADB 写入。[buffer 大小](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/service/sync/socket-pool.ts#L49)、[写入及读取前 flush](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/service/sync/socket.ts#L128-L167)、[push](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/service/sync/request/push.ts#L153-L173)。

libadb 则合并单条 SYNC 请求的头和内容，随后立即 `channel.write`；大文件同样按 64 KiB 分 DATA，所查路径没有 Tango 式跨记录合并。[write_req](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/sync.rs#L137-L166)、[DATA 循环](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/sync.rs#L454-L458)。

本项目 [Sync::request](../../crates/adb/src/sync.rs) 合并单条头和内容后立即调用 `AdbStream::write_all`；[push](../../crates/adb/src/sync.rs) 对 SEND、各 DATA、DONE 分别调用，并在每次返回前等到对应 classic ACK。因此，**相对 Tango 的跨记录合并，存在可确认的优化缺口；不能说所有参考库都已经解决。**

### 同一 SYNC 工作负载的受控实验

沿用本项目真实 Client 和 Sync::push，内存 transport、debug 库、classic 模式，每个 ADB WRTE 的 ACK 人为延后 10 ms。比较当前 push 与按上述参考策略编码的相同 SEND、64 KiB DATA、DONE 字节序列；后者仅将记录聚合后交给同一 Client。各项运行五次，列中位数，包数有断言。聚合方案不是编译运行 AOSP/Tango，也未执行 Core 的 helper、磁盘或原子提交。

| 文件大小 | 协商 max payload | 当前 WRTE 数 / 中位耗时 | 参考写合并方式 WRTE 数 / 中位耗时 |
| --- | --- | --- | --- |
| 1 KiB | 4 KiB | 3 / 34.2 ms | 1 / 11.5 ms |
| 1 KiB | 1 MiB | 3 / 34.2 ms | 1 / 11.3 ms |
| 1 MiB | 1 MiB | 18 / 205.7 ms | 2 / 26.7 ms |

最后一行仍含 16 条合法的 64 KiB DATA，未改为非法的 1 MiB DATA。结果证明在该夹具中，**相同 SYNC 内容的写合并减少了 classic 往返**；不能换算成“真实设备快 3 倍/8 倍”。原始流一次写入 1 MiB 的前序实验仅展示包大小与等待机制，不再用作参考项目性能排名。

调度和debug成本包含在这些耗时内；release构建与真实设备吞吐尚未由该夹具验证。

## 4. 稳定性：共享发送与接收耦合需按具体实现比较

本项目正常 WRTE 路由使用 `try_send`，不等待应用消费者；ACK/信用由逐流读取端返还。问题路径是 [reader 的 response 入队](../../crates/adb/src/client.rs)：普通 CLSE、未知流等响应需要等待共享 64 帧 writer 队列的容量。已用 67 条 classic 流、256 字节内存 transport 复现：66 条流写满出站，收到一条 CLSE 后，无关流的 hello 不能在 100 ms 内交付；排空出站后恢复。该夹具是条件性阻塞证据，不代表普通单文件会填满队列。

AOSP 的所查 `BlockingConnectionAdapter` 使用独立读写线程，写入仅把 packet 放入 deque 后通知 writer；没有本项目这个有界 channel 的容量等待。因此它避免同一条饱和路径，但其排队内存策略也不同，不能通过改成无界队列来简单模仿。[独立读写](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp#307)、[入队](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp#439)。

Tango 对 WRTE handler 不 await，但 CLSE 分支仍 await `socket.close()` 的控制写；libadb split reader 的部分 ACK 路径也需要获取共享写锁并 await。故不能声称“参考项目都没有收发耦合”。应保留本项目已复现条件，并为有界控制响应调度建立回归。[Tango dispatcher](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/daemon/dispatcher.ts#L142-L164)、[Tango close](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/daemon/socket.ts#L163-L168)、[libadb reader ACK](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/split.rs#L603-L631)。

ACK 时点也不同：本项目 classic 等整包被读取；AOSP 可在本机 socket 缓冲仍有空间时继续确认，Tango enqueue 有空余容量时不必等最终消费者处理完，libadb 使用 watermark。更早 ACK 可能提高吞吐，也可能增加排队和内存，不应单独评价优劣。[AOSP 接收队列](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/sockets.cpp#123)、[Tango enqueue](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/stream-extra/src/push-readable.ts#L160-L201)、[libadb channel](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/base/channel.rs#L308-L325)。

## 5. burst、校验和与压缩：方向和默认值不可混淆

- 本项目已实现 delayed ACK，默认关闭；AOSP 官方也默认关闭。Tango 默认 feature 包含 DelayedAck 并在双方支持时使用，默认接收信用 32 MiB。libadb 的桌面与 embedded 配置分别可取 32 MiB、32 KiB，握手仍由调用者提供 feature 集。不能仅按库名或配置方法断言任何调用都会开启。[Tango 协商](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/daemon/transport.ts#L102-L127)、[libadb 配置](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/base/connection/config.rs#L43-L63)。
- 本项目开启后给予设备 64 KiB 接收信用，限制的是**设备到主控**方向；push 的发送信用由设备返回的 OPEN OKAY 授予。前者不能直接用来解释上传吞吐。调整窗口需同时测方向、ACK 时点、内存与控制延迟。
- [Frame::write](../../crates/adb/src/protocol.rs) 对现代连接仍计算 payload 字节和；AOSP、Tango、libadb 按协商版本省略。多一次 payload 遍历是确定的 CPU 工作差异，影响大小未经 release profile 量化。[AOSP](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp#565)、[Tango](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/daemon/dispatcher.ts#L458-L467)、[libadb](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/base/connection.rs#L269-L270)。
- AOSP CLI 的 push 默认选择 Any 并按共同能力择 Zstd/LZ4/Brotli；pull 默认 None，不能概括为所有方向默认压缩。本项目 Core 调用普通 push/pull，没有使用库内压缩 API。可压缩内容上传值得测试；照片视频等已有压缩内容不保证受益。[CLI 默认值](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/commandline.cpp#2008)、[算法选择](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/file_sync_client.cpp#275)、[Core 调用](../../crates/interop_core/src/files.rs)。

## 6. Core 层额外成本仍然成立，但不是 ADB 协议缺陷

这些结论来自本项目代码，不声称参考项目提供相同的产品语义：

- [device::metadata](../../crates/interop_core/src/device.rs) 在发布连接前等待 getprop 与 dumpsys battery，超时 8 秒。参考传输库通常只提供握手和服务访问，比较连接速度时必须将“ADB CNXN 完成”和“产品设备信息就绪”分别计时。电量等可选字段可评估后置；必要身份核验仍需保留。
- [remote_fs::stat](../../crates/interop_core/src/remote_fs.rs) 对现代 lstat 错误统一使用 helper，包括正常 ENOENT；[原子提交](../../crates/interop_core/src/files.rs) 再调用 helper。每次 [部署](../../crates/interop_core/src/remote_helper.rs) 都上传并回读完整二进制，导致新目标小文件的固定流量明显大于文件内容。此机制是确定的，用户时间影响未做实机测量；优化不能删除精确字节授权和打开 inode 的保证。
- [persist_transfers](../../crates/interop_core/src/files.rs) 每次编码全部任务，调用 [private_write](../../crates/interop_core/src/runtime.rs) 全量写入并 sync_all。批量逐项保存有累计 O(N²) 级记录处理量；应针对千级小文件测持久化占比，保留恢复语义后再合并或增量保存。
- push/pull 的 3600 秒为整个复制的绝对时限，持续进度也会到期，且没有字节续传。dadb 所查写超时采用每次写入进展的停滞期限；这提供了策略对照，不表示它完整操作都没有其他时限，也不意味着应照抄其 10 秒值。[本项目选项](../../crates/interop_core/src/files.rs)、[dadb](https://github.com/mobile-dev-inc/dadb/blob/55cb08849b9b17c1e627156a0de11d91d36034de/dadb/src/main/kotlin/dadb/AdbConnection.kt#L98)。

## 7. 后续决策所需测量

实机比较须固定设备/主控、连接方式、协商版本与 max payload、classic/burst、传输方向、压缩、文件内容与大小，以及完成定义。分别记录 CNXN 和产品就绪 P50/P95、push/pull 有效 MiB/s、CPU/RSS、并发传输中的控制延迟、取消与恢复时长。真实 USB、无线切网、丢包、低速大文件与小时级稳定性仍未由本轮验证。

前序已跑的 ADB 测试与 Core 健康/文件状态测试只证明覆盖的协议与主机边界；本轮没有把它们重命名为参考对照或实机性能测试。
