# 连接健康、单流期限与资源回收

连接、控制流、媒体消费者及远端进程分别拥有失效边界。当前资源所有权见[架构](architecture.md#状态与资源所有权)，用户恢复规则见[交互规则](../../designs/prod/interaction-rules.md#后台与恢复)。本文件保留实现机制及2026-10-18独立故障样本，历史播放器/协作JAR结果不继承为当前依赖通过。

## 连接级检测

| 故障 | 实现边界 | 验证边界 |
| --- | --- | --- |
| TCP链路/ACK丢失 | connect_tcp在TLS包装前设置keepalive；Android/Linux另用TCP_USER_TIMEOUT约束未ACK数据 | 独立API36测试在自有socket的TCP处理前丢包；需要过滤器权限，产品不要求root。不等同仍正常ACK的应用停转 |
| ADB应用失活 | Core每2秒检查精确Client，约10秒无入站读取进展后异步OPEN标准sync服务，单次3秒，两次无进展超时才关闭旧Client | OPEN接受、拒绝或其他入站流量均说明有响应；本机stream上限不算失活。阈值不是任意设备的绝对恢复期限 |
| 慢但有进展 | 每个非空header/payload读取批次推进活动；完整帧前的进展也有效 | 真实慢header和1MiB分段payload回归排除了首版“完整帧计数”误断；不替代协议校验 |

健康探针只开关服务，不发sync命令、不读写文件或启动shell/JAR。每连接最多一个，繁忙流量取消探针；旧结果应用前在连接锁下核对精确Client，不能按deviceId关闭替代连接。移除/替换/Runtime释放取消任务；库只暴露入站活动，Core拥有产品策略。用户主动断开继续关闭自动重连。

## 同设备转换与远端进程

ConnectionOwner按每设备串行化旧连接清理、连接准入和显式断开，其他设备不被慢清理阻塞。store→connections锁序原子撤下旧Client并发布离线；attach完成旧活动清理后才接纳新Client。陈旧monitor扫描不能覆盖新状态或取消替代连接的新会话；丢弃调用者留下的cleanup标志由后续monitor继续收束。

显式断开的精确旧传输由guard保留，活动停止后关闭；资源owner而不是UI页面承担结束责任。身份更换和显式TCP转换仍遵循同一准入栅栏，不能先更新记录再核验目标。

远端JAR使用共享监督器观察主控输入EOF，终止并等待自己的真实子任务后删除唯一部署路径，保留退出码及READY/RPC契约。不按glob删除、不向保存的裸PID发信号。旧raw exec没有PTY HUP保证；仅删除JAR不能证明进程结束。当前版本范围见[兼容边界](android-target-compatibility.md#服务端与资源回收)。

## 单流期限

- 视频完整单元的首字节之后，header/session/payload有总期限；完整包间允许长期静止，不设置固定出帧频率。
- `run_video`用源PTS与到达时刻的偏移增长识别单向排队，不要求两端时钟同源。连续8帧增长达到约800ms时，经控制优先通道请求`RESET_VIDEO`，进入`awaitingSession`并丢弃旧编码段直到新session；4秒冷却避免重置风暴。
- 认证本机媒体输出的首帧前缀、session尺寸和完整视频单元写入有3秒停滞期限；HTTP响应头及实际待交付chunk另有写入期限。消费者停读不会无限占住上游，失败只结束所属输出，不随意丢弃有参考关系的压缩帧。
- 普通触摸、按键和文本在进入控制actor的有界队列后即向Dart返回接纳回执；时间戳仍带绝对6秒期限，出队时拒绝过期请求。队列满返回`control_busy`，不建立无界积压。actor在等ADB回执期间只保留每触点最新move，down/up/cancel保序；随后把同一阶段连续的完整控制消息拼成不超过协商max payload的一个WRTE，使用最早消息的期限。classic模式因此不再为每个短触摸消息各等一次ACK。画质重建检查先过滤非安全消息再拼接，不能由批写绕过输入栅栏。
- 启动、刷新及需要结果的发送仍等待实际WRTE；剪贴板另等应用层sequence。任何实际写入失败只取消所属控制会话，保留共享Client及其他活动；晚到OKAY不能复活已撤销route或重放输入。
- Set/Capture的应用层sequence回复超时是独立错误，不把任何无回复都当设备断连。剪贴板读取使用companion带编号RPC及hasText/权限结果，避免无requestId旧回复误配新读取；allowStart门禁继续生效。无helper的自动同步失败进入limited后，手动读取即使启动helper，也不保证协调器立即恢复：相同配置会直接返回，失败路径已取消timer；仍需内容事件、前后台变化或开关重新核对，`clipboard.changed`可重新激活。

应用START_APP仍有独立提交许可和unknown账本，恢复连接不会自动重放，见[应用打开恢复](app-launch-recovery.md)。

## 已执行故障验证

| 样本 | 实际结果 | 未覆盖 |
| --- | --- | --- |
| Duplex/Frame与资源准入夹具 | 旧清理曾取消新Client的视频准入，修复后覆盖取消/重连/慢清理/替换交错 | 不冒充真实编码器资源竞态 |
| Runtime真实TLS协议端 | ACK丢失或ADB应用无响应后，offline→同ID新连接；主动断开有真实EOF并不再次accept | 协议端不是实际配对adbd，不证明物理无线 |
| 实际API36 adbd应用黑洞 | 自有旧连接双向discard、TCP仍开且不注入EOF；清理前确认双向实际丢字节、controller先EOF、随后新连接 | 是应用层停转代理，非adbd内部挂起或真实Wi-Fi漫游 |
| 正式RemotePage黑洞恢复 | 两组约19–20秒恢复新session及图案0→1，默认EOF控制约1.6秒；主动停止后不再新建 | 静态源入站零字节的首次样本被严格拒绝；后来增加隔离fixture挑战，没有降低双向drop断言 |
| 单控制route选择性丢OKAY | 输入录取回执不再等待该OKAY；在途输入期限结束后route关闭且排队输入不重放，视频字节继续增加、文件查询仍成功 | 不等于所有网络半开或物理设备MediaCodec故障；实体Wi-Fi时延未由夹具证明 |
| 实际远端进程/EOF | 精确进程、socket和自有JAR回收，包含尚未完成媒体握手的路径 | 上传中断、SIGKILL/断电及跨重连清理账本分别验证，不能据正常收尾推断全部覆盖 |

## 可复现入口

主机边界运行 `cargo test -p interop-core --lib connection_health`、`cargo test -p interop-core --lib control_` 及 `device::connection_cleanup_tests`。TCP故障见ADB/Core各自的 `tests/tcp_liveness.rs`，权限和Android执行条件按声明显式启用，不把ignored算通过。

实际目标用例：

```sh
env INTEROP_ADBD_ADDRESS=<地址> INTEROP_ADBD_PORT=<连接端口> \
  INTEROP_CORE_TEST_ENDPOINT=<地址:连接端口> \
  cargo test -p interop-core --test app_launch_android \
  --test companion_clipboard --test control_stall_android \
  -- --ignored --nocapture --test-threads=1
```

可见视频恢复从 `app/` 用 `tool/driver/video_recovery.dart` / `integration_test/video_recovery_test.dart`，准备方式同[性能夹具](video-performance.md#普通调度基准与解码路径对照)，host设置 `CONNECT_E2E_RECOVERY_FAULT=blackhole`；省略该变量是EOF对照。故障回执在cleanup前收集，cleanup产生的EOF不能满足验收。

物理ARM、Wi-Fi/OEM、小时长稳、捕获/应用任务恢复和原生snapshot崩溃未由这些测试关闭；连接恢复通过也不证明[性能预算](video-performance.md#未完成边界)达标。
