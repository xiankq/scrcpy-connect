# ADB 性能修复与主机回归（2026-10-19）

对象：基于 `6937bd91e1b26e30d166c88d5ab41f6982b3ef54` 的本次工作区改动。对照依据为 [固定 AOSP、Tango、libadb 源码研究](../research/adb-reference-performance.md)；本机 adb_dart 和播放器不在本轮范围。本记录说明这次实现与证据，不承担现行产品规则。

## 实现与针对性证据

| 问题 | 本次实现 | 主机验证 |
| --- | --- | --- |
| SYNC 每条记录单独发送并等 classic ACK | 仅 push 路径跨 SEND/SND2、DATA、DONE 合并，缓冲上限为协商 payload | 真实 Client/Sync 夹具：1 KiB 文件 3→1 WRTE，1 MiB 文件在 1 MiB payload 下 18→2 WRTE；DATA 仍不超过 64 KiB |
| reader 为 CLSE 等待共享 writer 容量 | 有界控制队列独立入队，已接纳数据先于同流 CLSE，溢出关闭连接 | 饱和出站时无关流仍能读入；关闭唤醒等待容量的 OPEN/WRTE；队列洪泛有界 |
| 现代出站包仍遍历 payload 求和，USB 再序列化 | 协商后现代 checksum 为零；USB 保留原始 wire header/payload | 现代、旧协议、首次 CNXN、RSA AUTH、USB header 保真分别断言 |
| 新目标 ENOENT 也部署元数据 helper | v2 errno 保留结构；不存在等确定错误直接返回，权限/能力拒绝仍回退 | ENOENT/ENOTDIR/ENAMETOOLONG 只有一次 SYNC OPEN；权限/能力错误进入 helper 路径；静默超时不开第二服务 |
| 每个文件状态变化全量编码、重写历史 | 按任务追加 durable journal、阈值压缩；回收仅保存相关批次 | 千条历史中更新一项，检查点字节不变，日志增量小于 8 KiB，重开恢复全部；旧数组迁移、截断、序号、代际、删除与失败写入测试 |
| 电量查询阻塞连接可用 | 必要身份信息保留在准入阶段，电量随后有界查询 | withheld battery 时连接与 Client 已可用；迟到结果不能更新替代连接或离线记录；Runtime 释放清理四个在途及排队查询 |
| 每次连接重新创建 TLS 配置 | 同一 Runtime、同一不变身份缓存成功配置 | TLS 连接策略、AUTH 与加密握手相关既有回归；未改变验证模式及加密要求 |
| 上传提交未沿用任务取消 | 原子 rename helper 接收任务 cancellation | 真实 Client 在 ABI shell 等待时取消提交，及时返回 result_unknown 且保留设备连接；部署取消与文件状态回归 |

新回归主要位于：

- `crates/adb/tests/sync_coalescing.rs`、`control_backpressure.rs`、`checksum_policy.rs`。
- `crates/interop_core/tests/transfer_journal.rs`。
- `crates/interop_core/src/remote_fs.rs`、`device/metadata_tests.rs`、`device_metadata.rs` 的测试模块。

针对性复现先于相应修复：现代出站 checksum 非零；出站饱和时 sibling read 超时；控制洪泛未及时关闭；pending OPEN 在对端关闭后仍等待；确定 errno/静默超时误入 helper；电量 withheld 导致连接超过两秒仍未完成。修复后对应测试通过。部分既有夹具同步改为按现代 CNXN 后的真实规则读取 checksum，握手和旧协议校验保留。整体回归中发现的旧服务顺序/数量假设也按请求类型修正：可选电量不冒充健康探针，TLS 拒绝前零服务请求的断言继续覆盖所有服务。

最终回归还暴露通知缓存既有测试的一次时序超时：手工绑定观察 epoch 与后台 `observation.set` 排队竞争，测试可能误把启动请求当成列表查询。仅调整该夹具，通过真实启动回执建立观察并按 command 匹配列表请求；旧列表回执不能覆盖新观察、事件水位与快照断言保留，通知生产逻辑未改。

持久化仍在提交边界同步文件，不以 debounce 代替恢复保证。检查点格式、所有权与失败规则见 [架构](architecture.md)；协议的队列与合并契约见 [ADB 库](../../crates/adb/README.md)；元数据回退见 [兼容边界](android-target-compatibility.md)；连接就绪语义见 [产品规则](../../designs/prod/device-connection.md)。

存储迁移后，检查点与 journal 共同构成传输记录；单独复制 `transfers.json` 不能代表最新结果。仅支持旧数组格式的旧程序不能直接读取新格式；版本回退需要相应迁移，不能通过删除 journal 恢复运行。

## 验证命令与范围

在 Linux 主控工作区，最终 `cargo test --workspace` 退出 0：390 passed、0 failed、72 ignored（含文档测试）。严格 Clippy、格式、无默认 feature 编译与差异空白检查均退出 0。设备、物理 USB、独立 BoringSSL 和组播环境要求的 ignored 用例不作为本轮通过项；本轮未重新构建 Flutter 或四宿主整包。

最终原始日志：[workspace tests](/tmp/scrcpy-connect-adb-performance-tests-final.log)、[Clippy](/tmp/scrcpy-connect-adb-performance-clippy-final.log)。日志为本机临时验收产物，不参与运行配置。

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --all -- --check
cargo check -p interop-adb --no-default-features
git diff --check
```

本轮没有测量真实设备 MiB/s、连接 P50/P95、CPU/RSS 或小时级稳定性。包数下降证明减少受控 classic 确认次数，不能外推为实机提速倍数。已有研究中的 10 ms 延迟实验属于修复前基线与参考策略对照。

仍需设备证据的取舍包括 burst 窗口、压缩默认值、下载方向吞吐、无线切网与超时策略；默认配置未因此改动。复制仍有 3600 秒绝对时限，恢复仍从头开始，本轮没有引入字节续传。文件 helper 的精确字节授权与打开 inode 校验继续保留；对确需 helper 的提交仍有部署成本。任务调度/目录校验仍扫描内存任务；多个相关分享来源同时等待回收时也会再次编码相关批次。本次改善的是逐文件持久化的全历史序列化和磁盘重写，不声称消除全部批量开销。
