# 连接健康、单流期限与资源回收

连接、控制流、媒体消费者及远端进程分别拥有失效边界。资源所有权见[架构](architecture.md#状态与资源所有权)，用户恢复规则见[交互规则](../../designs/prod/interaction-rules.md#后台与恢复)。以下机制遵守应用拥有产品策略的边界；生产切换状态见[本轮重构记录](architecture-refactor-validation.md)。2026-10-18 的独立故障样本属于历史实现，不继承为本轮应用验收。

## 连接级检测

| 故障 | 实现边界 | 验证边界 |
| --- | --- | --- |
| TCP链路/ACK丢失 | connect_tcp在TLS包装前设置keepalive；Android/Linux另用TCP_USER_TIMEOUT约束未ACK数据 | 独立API36测试在自有socket的TCP处理前丢包；需要过滤器权限，产品不要求root。不等同仍正常ACK的应用停转 |
| ADB应用失活 | 应用按 `ConnectionPolicy` 检查精确连接的入站活动，无进展时有界 OPEN 标准 sync 服务；连续无进展失败后仅退休原连接 | OPEN接受、拒绝或其他入站流量均说明有响应；本机stream上限不算失活。策略阈值不代表任意设备的绝对恢复期限 |
| 慢但有进展 | 每个非空header/payload读取批次推进活动；完整帧前的进展也有效 | 真实慢header和1MiB分段payload回归排除了首版“完整帧计数”误断；不替代协议校验 |

健康探针只开关服务，不发 sync 命令、不读写文件或启动 shell/JAR。每连接最多一个；近期有入站进展时不创建探针，探测期间的新进展使该次响应超时不能累计为网络失败。应用处理结果前核对精确连接和准入代次，不能按 deviceId 关闭替代连接。移除、替换或业务所有者释放时取消探针；能力库只暴露入站活动与服务机制，Dart 应用拥有探测计时、失效阈值和重连决策。用户主动断开同时关闭该设备自动重连。

入站活动只在同一实际 connectionId 内比较是否改变，不当作时间戳、字节数或已验证帧数。直连在非空底层读取时推进，包含部分头和 payload；官方服务器路径当前统计服务数据读取，不包含 smart socket 的握手状态。两条路径的计数范围不能混为一谈。

`AdbServices.open` 仅交付操作登记，实际 OPEN 随后执行；raw 流的 done 表示执行终态，不表示 OPEN 接纳。`sync:` 接受后不发送文件协议请求可以一直没有数据，因此不能用 raw 超时冒充远端无响应。健康监测使用独立的 `createOpenProbe`／`AdbOpenProbe`：结果区分 `directAdb` 与 `officialServer` 层，并报告实际完整写出、响应结果和不透明入站活动标识。总超时包含本机 writer 容量等待；只有确认 OPEN 实际写出、后续无入站进展的响应超时才用于沉默判定。未写出、本机容量、取消、I/O 或协议错误不累计为对端无响应。

`DeviceHealthCoordinator` 持有计时、精确物理连接标识和探针，读取事实已关闭时直接退休；`DeviceCoordinator.retireUnhealthy` 撤销原连接准入、发布离线并沿原 `ConnectionOwner` 排空，保留自动重连偏好。探针关闭失败保留同一句柄供重试，不创建替代探针，也不关闭共享客户端。SDK 创建已受理但因取消或 facade 关闭而无法交付、且清理失败时，`AdbOpenProbeCleanupFailure.probe` 保留精确重试权。当前验证范围见[重构记录](architecture-refactor-validation.md)。

## 同设备转换与远端进程

应用 Dart 的 `ConnectionOwner` 按设备串行化旧连接清理、连接准入和显式断开，其他设备不被慢清理阻塞。先同步撤销原代次的准入，再等待核验与精确回收；清理成功后才接纳后继连接。`DeviceRecordStore` 的持久提交与实际连接事实分别核验，未知提交不伪装成功。陈旧健康扫描不能覆盖新状态或取消后继连接的会话；清理失败保留未完成阶段，由同一所有者重试。

修改端点在候选核验和持久提交成功后才退休旧连接。候选在交付前被取消或失效时，同设备队列先补偿尚未交付的端点；只比较并恢复本次实际修改的地址、端口和传输，保留并发名称、身份及其他字段。补偿失败保留原责任并阻止后继越过，不能用已递增的业务代次跳过收尾。原连接开始退休后的失败不承诺恢复它；可等待的取消补偿也不构成进程崩溃恢复事务。

显式断开保留原传输的精确关闭权；资源所有者承担活动停止和传输结束责任，页面释放不替代清理。身份更换和显式 TCP 转换遵循同一准入栅栏，不能先更新记录再核验目标。

远端JAR使用共享监督器观察主控输入EOF，终止并等待自己的真实子任务后删除唯一部署路径，保留退出码及READY/RPC契约。不按glob删除、不向保存的裸PID发信号。旧raw exec没有PTY HUP保证；仅删除JAR不能证明进程结束。当前版本范围见[兼容边界](android-target-compatibility.md#服务端与资源回收)。

## 单流期限

- 视频完整单元的首字节之后，header/session/payload有总期限；完整包间允许长期静止，不设置固定出帧频率。
- `run_video`用源PTS与到达时刻的偏移增长识别单向排队，不要求两端时钟同源。连续8帧增长达到约800ms时，经控制优先通道请求`RESET_VIDEO`，进入`awaitingSession`并丢弃旧编码段直到新session；4秒冷却避免重置风暴。
- 本机 packet source 的视频和 PCM 交付在等待消费者容量时有3秒期限，并响应取消；没有附着消费者时另有连接期限。消费者停读不会无限占住上游，失败只结束所属输出，不随意丢弃有参考关系的压缩帧。媒体输入与所有权见[原生媒体组件](../../packages/media_codec/README.md)。
- 普通触摸、按键和文本在进入控制actor的有界队列后即向Dart返回接纳回执；时间戳仍带绝对6秒期限，出队时拒绝过期请求。队列满返回`control_busy`，不建立无界积压。actor在等ADB回执期间只保留每触点最新move，down/up/cancel保序；随后把同一阶段连续的完整控制消息拼成不超过协商max payload的一个WRTE，使用最早消息的期限。classic模式因此不再为每个短触摸消息各等一次ACK。画质重建检查先过滤非安全消息再拼接，不能由批写绕过输入栅栏。
- 启动、刷新及需要结果的发送仍等待实际WRTE；剪贴板另等应用层sequence。任何实际写入失败只取消所属控制会话，保留共享Client及其他活动；晚到OKAY不能复活已撤销route或重放输入。
- Set/Capture的应用层sequence回复超时是独立错误，不把任何无回复都当设备断连。剪贴板读取使用companion带编号RPC及hasText/权限结果，避免无requestId旧回复误配新读取；allowStart门禁继续生效。无helper的自动同步失败进入limited后，手动读取即使启动helper，也不保证协调器立即恢复：相同配置会直接返回，失败路径已取消timer；仍需内容事件、前后台变化或开关重新核对，`clipboard.changed`可重新激活。

应用START_APP仍有独立提交许可和unknown账本，恢复连接不会自动重放，见[应用打开恢复](app-launch-recovery.md)。

## 历史故障验证

| 样本 | 实际结果 | 未覆盖 |
| --- | --- | --- |
| Duplex/Frame与资源准入夹具 | 旧清理曾取消新Client的视频准入，修复后覆盖取消/重连/慢清理/替换交错 | 不冒充真实编码器资源竞态 |
| Runtime真实TLS协议端 | ACK丢失或ADB应用无响应后，offline→同ID新连接；主动断开有真实EOF并不再次accept | 协议端不是实际配对adbd，不证明物理无线 |
| 实际API36 adbd应用黑洞 | 自有旧连接双向discard、TCP仍开且不注入EOF；清理前确认双向实际丢字节、controller先EOF、随后新连接 | 是应用层停转代理，非adbd内部挂起或真实Wi-Fi漫游 |
| 正式RemotePage黑洞恢复 | 两组约19–20秒恢复新session及图案0→1，默认EOF控制约1.6秒；主动停止后不再新建 | 静态源入站零字节的首次样本被严格拒绝；后来增加隔离fixture挑战，没有降低双向drop断言 |
| 单控制route选择性丢OKAY | 输入录取回执不再等待该OKAY；在途输入期限结束后route关闭且排队输入不重放，视频字节继续增加、文件查询仍成功 | 不等于所有网络半开或物理设备MediaCodec故障；实体Wi-Fi时延未由夹具证明 |
| 实际远端进程/EOF | 精确进程、socket和自有JAR回收，包含尚未完成媒体握手的路径 | 上传中断、SIGKILL/断电及跨重连清理账本分别验证，不能据正常收尾推断全部覆盖 |

## 可复现入口

当前健康策略和精确退休回归位于 `app/test/connection/device_health_coordinator_test.dart`、`device_coordinator_test.dart`，连接准入与核验取消位于 `connection_owner_test.dart`。公开探针生命周期位于 `packages/adb/test/open_probe_test.dart`，两套真实 FRB 与本机 smart socket 夹具位于 `packages/scrcpy/test/open_probe_native_test.dart`；ADB 操作清理和 transport 夹具位于 `rust/adb/api/src/cleanup_tests.rs` 与 `rust/adb/tests/`。旧 `interop-core` 设备故障样本属于业务迁移前来源，当前主机回归不能继承其设备运行结论。

以下是旧 Runtime 实际目标用例的历史复现命令，不代表当前生产入口已恢复：

```sh
env INTEROP_ADBD_ADDRESS=<地址> INTEROP_ADBD_PORT=<连接端口> \
  INTEROP_CORE_TEST_ENDPOINT=<地址:连接端口> \
  cargo test -p interop-core --test app_launch_android \
  --test companion_clipboard --test control_stall_android \
  -- --ignored --nocapture --test-threads=1
```

可见视频恢复从 `app/` 用 `../tool/driver/video_recovery.dart` / `integration_test/video_recovery_test.dart`，准备方式同[性能夹具](video-performance.md#重复测量入口)，host设置 `CONNECT_E2E_RECOVERY_FAULT=blackhole`；省略该变量是EOF对照。故障回执在cleanup前收集，cleanup产生的EOF不能满足验收。

物理ARM、Wi-Fi/OEM、小时长稳、捕获/应用任务恢复和原生snapshot崩溃未由这些测试关闭；连接恢复通过也不证明[性能预算](video-performance.md#指标与证据)达标。
