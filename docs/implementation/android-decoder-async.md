# Android 显式异步解码与系统追踪

本记录限定2026-10-18、双API36/x64 AVD/SwiftShader、Flutter3.47.6 debug、当时fvp0.39.1/固定MDK0.39.0及捕获JAR。当前社区原版、服务端及构建来源见[工具链契约](repository-tooling.md)；旧补丁环境的数值不继承为当前性能通过。

## 固定场景与结果

H.264请求1280/60fps/8Mbps、实际576×1280、经典ADB。普通Driver各组3会话30次真实输入，冷操作保留，另核对实际窗口、暂停恢复及释放。三组同开原生观测和Perfetto，唯一变量为codec async选项。

| A/B/A | 首帧 ms | 输入 P50/P95 ms | queue→workDone 中位 ms | workDone→onVideo 中位 ms |
| --- | --- | --- | --- | --- |
| AMediaCodec 缺省 | 1150 / 1137 / 1189 | 277 / 392 | 3.600 | 147.174 |
| 显式 async=1 | 1170 / 1107 / 1165 | 153 / 204 | 6.260 | 20.841 |
| 返回缺省 | 1227 / 1150 / 1154 | 273 / 389 | 5.488 | 133.510 |

每组30/30输入按PTS唯一关联。queue/workDone来自同一Perfetto时钟；relay/onVideo来自同一Rust单调时钟，二者不直接混减。组件段含IPC/调度，workDone之后含SDK输出与图像交付，不能全部叫纯解码或fence等待。

显式async的输入预算通过，但三组首帧仍超过1000ms，严格命令均失败。无诊断的历史default复跑60输入P50/P95=138/295ms，首帧1197/1157/1122ms仍失败；带trace和无trace组不能相除报告优化百分比。五编码功能回归另有真实首帧/退出/停止证据，不是五编码延迟验收。

## 生效证据

基线持续 `MediaCodec::dequeueOutputBuffer#native`；显式选项后实际出现async成功日志及 `onOutputBufferAvailable#native`，不再持续同步dequeue。AImageReader异步acquire与codec异步是不同机制，候选列表或文档默认值也不作生效证据。

[MDK参数说明](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#amediacodec)与固定二进制缺省表现不同，没有据公开头/Changelog编造SDK内部根因。[固定MediaCodec源码](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/libstagefright/MediaCodec.cpp#6032)说明异步下不能同步dequeue。关闭后的operation-mode指标受setState/flush影响，不能反证运行期模式；output.delay=8也不是实际8帧等待。

首次标记组因snapshot PTS无法唯一关联被拒绝，不计成功输入；trace配置放在临时目录被SELinux拒绝后移入允许的perfetto-configs，没有关闭SELinux或把缺少的ftrace事件当已采集。

## 可复现的边界观测

已有native trace在Android以短ATrace标记记录不透明traceToken和微秒PTS，默认关闭；先检查isEnabled、栈缓冲格式化、锁外成对begin/end，非Android为no-op，不改原elapsedUs与帧透传。[NDK tracing契约](https://developer.android.com/ndk/reference/group/tracing)。

配置见[decoder_trace.pbtxt](../../tool/e2e/decoder_trace.pbtxt)。按[普通Driver入口](video-performance.md#普通调度基准与解码路径对照)依次使用native、native-async、native，每轮10输入；先启动App等待ready，再开始trace和host，覆盖首轮。主控路径及PID使用实际值：

```sh
adb -s <主控serial> push tool/e2e/decoder_trace.pbtxt /data/misc/perfetto-configs/connect-decoder-trace.pbtxt
adb -s <主控serial> shell perfetto --txt \
  -c /data/misc/perfetto-configs/connect-decoder-trace.pbtxt \
  -o /data/misc/perfetto-traces/connect-decoder-trace.pftrace
adb -s <主控serial> pull /data/misc/perfetto-traces/connect-decoder-trace.pftrace <本次trace文件>
dart tool/e2e/analyze_decoder_trace.dart \
  --trace-processor <trace_processor路径> --trace <本次trace文件> \
  --benchmark <本次result.json> --pid <实际AppPID> \
  --output <新分析文件> --require-markers
```

分析按PID/codec/PTS/token唯一配对，容许既有1µs转换截断；重复codec、重复decoded、跨会话、错身份、缺标记或空rounds不能生成完整统计。无token旧样本只在明确PID与唯一PTS下报告组件段，不能补造onVideo段。分析器的完整覆盖通过与产品性能失败是不同结论。

## 未完成范围

首帧预算、当前依赖复验、物理ARM/profile、旧API回退、无线漫游与长稳仍开放。原生trace和调用栈只缩小排查范围；ARM包签名/构建通过不替代上机，跨平台cargo check也不替代Flutter整包。系统临时trace及配置按本次身份清理，不改变产品调试或root要求。
