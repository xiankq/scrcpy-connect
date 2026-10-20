# 高动态窗口取样与目标资源对照

本记录限定2026-10-18、双API36/x64 AVD/SwiftShader、Flutter debug、当时Android异步AMediaCodec与捕获JAR。H.264请求1280/60fps/8Mbps、实际576×1280、经典ADB、普通Driver和持续变色fixture；无逐帧/系统trace。当前依赖见[工具链契约](repository-tooling.md)，旧性能结果不自动继承。

## 原始窗口与严格失败

高动态PNG取样曾在首轮超时，无法取得输入分布。新增host参数 `CONNECT_E2E_SCREEN_CAPTURE=raw`，默认仍PNG；按[AOSP screencap](https://android.googlesource.com/platform/frameworks/base/+/47e1cd5673dc3f95e09456050b81715cb48a7143/cmds/screencap/screencap.cpp)解析四个uint32头及紧密行像素。只接受已验证小端RGBA8888、16字节头、非零且≤8192单边、≤12MiB及精确长度，不猜旧头/其他格式。PNG/raw共用真实Texture矩形和计数核验。

实际样本1080×2400/format1/colorSpace1。raw减少部分空闲取样开销，但冷raw仍近2秒；动态首跑抓取/编码/验证组合约3.4秒，严格失败，不能算视频改善。

显式 `CONNECT_E2E_DIAGNOSTIC_SURFACE_MS=15000`仅允许取回迟到窗口，硬预算仍3000ms，每项保留budgetMet。扩展诊断强制diagnosticOnly、videoPerformanceComplete=false、exit1；measurementLoopComplete只表示全部轮次、窗口、暂停/恢复与停止完成，不表示性能通过。

## 限定资源对照

仅将目标AVD从2→4→2vCPU，实际核验cpu online；保持主控、画面、画质和诊断配置。每组3轮24输入、30次实际窗口，全部计数匹配，暂停/恢复、释放和自有fixture清理确认：

| 目标vCPU | 首像素，ms | 输入P50／P95，ms | 匹配窗口／迟到 | 严格结果 |
| --- | --- | --- | --- | --- |
| 2 | 2229／1978／2549 | 1866／2202 | 30／21 | exit1 |
| 4 | 2583／1971／2221 | 1584／1865 | 30／30 | exit1 |
| 返回2，暖复跑 | 2122／2629／2253 | 1793／2145 | 30／20 | exit1 |

返回2核首次冷运行首帧4243ms、首输入超时，没有分布；该失败保留，不用暖返回组覆盖。增加vCPU的方向支持目标资源会影响等待，但共享宿主负载、冷启动和截图成本也变化，不能唯一归因为编码CPU，更不是物理硬编收益或产品修复。

2核基线每输入19–36次snapshot轮询才见新计数，控制回执中位约10.5ms，不是单个snapshot阻塞1.8秒，也不是目标draw ACK。输入间实际截图有间隔，测量到解码像素可读而非连续手势/稳定60fps/面板延迟；各分段中位数不能相加代替总量。

## 默认路径控制

同工具不设raw/扩展期限，静态PNG控制3轮24输入曾完整通过：首帧921/903/828ms、P50/P95157/210ms，实际窗口均满足硬预算、暂停恢复/清理完整。它确认新工具未破坏该旧环境的默认严格路径，不能覆盖动态失败。

## 复现与边界

按[普通调度入口](video-performance.md#普通调度基准与解码路径对照)准备两个隔离目标，decoder=default、ROUNDS=3、TRANSITIONS=8、1280/60/8000000；host另设：

```sh
CONNECT_E2E_VIDEO_MOTION=true
CONNECT_E2E_SCREEN_CAPTURE=raw
CONNECT_E2E_DIAGNOSTIC_SURFACE_MS=15000
```

每组使用新输出目录，保留失败、原窗口和清理身份。解析器边界测试位于 `tool/benchmark/live_video/android_screencap.dart` 对应工具回归；原始RGBA只可无损转换为PNG用于目视，不生成示意图代替实测。

该实验只改测量工具，未改生产播放策略或重建JAR。当前社区原版的性能复验、真实ARM/无线、热功耗及原生snapshot安全仍未由本样本关闭；版本与崩溃边界见[MDK核查](../research/mdk-sdk-snapshot-followup.md)。
