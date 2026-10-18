# Android 显式异步解码与系统追踪

2026-10-18。默认高清控制的额外等待主要出现在 CCodec 组件完成之后。本轮以普通
Driver 绑定、实际 Rust ADB／共享播放器／Texture 逐次验证新图案，新增系统追踪标记，
再做 A/B/A 单变量对照。现保留 Android 首选 `AMediaCodec:async=1`，原软件回退和
其他平台优先级不变。**输入延迟改善；完整首帧仍未通过 1000ms 门槛。**

## 固定场景与结果

双 API36 x64 AVD／SwiftShader，Flutter3.47.6 debug，fvp0.39.1／MDK0.39.0，H264、
请求1280／60fps／8Mbps、实际576×1280，ADB burst关闭。各组3个独立会话、30次
实际按键和新图案、36次实际窗口检查、3次暂停恢复及释放／夹具清理，后者全部完成。
不去掉冷输入；截图在计时之外验呈现，输入计时到真实解码像素可读，非面板扫描延迟。
三组都开原生观测及同一60秒Perfetto配置，只有显式async选项变化；不是ARM功耗证明。

| A/B/A | 首帧 ms | 输入 P50/P95 ms | queue→workDone 中位 ms | workDone→onVideo 中位 ms |
| --- | --- | --- | --- | --- |
| AMediaCodec 缺省 | 1150 / 1137 / 1189 | 277 / 392 | 3.600 | 147.174 |
| 显式 async=1 | 1170 / 1107 / 1165 | 153 / 204 | 6.260 | 20.841 |
| 返回缺省 | 1227 / 1150 / 1154 | 273 / 389 | 5.488 | 133.510 |

每组30/30输入有唯一系统标记配对。relay开始write→onVideo中位151.589／34.123／
140.512ms，来自各组同一Rust相对时钟；上表两列分别使用同一Perfetto时钟中的事件
起点差。没有将Rust进程OnceLock起点与Android绝对时间相减，也不把某个slice的dur
误作整个解码耗时。组件段含IPC／调度，后一段仍含SDK输出调度和图像交付，不独断
为fence等待。第一组无标记的早期R1只有28/30输入覆盖，未混入此完整对照。

三组严格命令均exit1：1秒首帧仍失败。async组200/300ms输入组合通过，不能替代
完整门槛。冷启动输出阶段约398–492ms、Core约671–709ms，首帧没有可靠整体收益。

## 生效证据与一次失败

基线同onVideo线程持续调用 `MediaCodec::dequeueOutputBuffer#native`，没有异步
输出事件。显式选项后有3条 `MediaCodec will operate in async mode`，467条
`MediaCodec::onOutputBufferAvailable#native`，且不再持续同步dequeue。候选列表和
文档默认值都不作为生效证据。AImageReader异步acquire已在之前验证，与codec异步
是不同机制；不能据前者推断后者已经启用。

当前[MDK文档](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#amediacodec)称async
默认1，但固定二进制缺省运行与之不同；公开头和本地Changelog不能解释内部选择。
不编造SDK内部根因。固定[MediaCodec源码](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/libstagefright/MediaCodec.cpp#6032)
说明异步模式不允许同步dequeue，并有成功设callback的日志及输出事件。

关闭后 `media.metrics` 的operation-mode仍显示1，不能据此反证运行期同步：同一
固定源码的setState会清异步flag，后续flush再按当时flag更新指标。原始dump保留
`/tmp/connect-decoder-operation-metrics{,-final}.txt`，未当运行期模式门禁。
另查output.delay=8是输出slot分配输入，不能等同reorder深度或实际8帧等待。

新标记首次R2在首个input因snapshot PTS无法唯一匹配已记录回调而被拦截，原始
结果和trace保留，不计成功输入或抹掉失败。清理确认后R3才完成上表首组全量测量。
首个trace配置放在/data/local/tmp被SELinux拒绝，移至perfetto-configs后成功；
不关闭SELinux。trace有48项ftrace setup notice，未把不存在的设备事件当已采集。

## 可复现的边界观测

`53bcf10`在已有optin native trace回调加入Android限定的短ATrace标记，包含不透明
traceToken和四舍五入后的微秒PTS；metrics也返回相同token。不开traceFrames不注册
该回调，系统追踪关闭时先isEnabled再决定格式化。名称用80字节栈缓冲，无堆分配，
begin/end成对、在锁外，不改变原elapsedUs、帧透传或丢失语义；非Android为no-op。
[NDK契约及API23可用性](https://developer.android.com/ndk/reference/group/tracing)。

配置见[decoder_trace.pbtxt](../../tool/e2e/decoder_trace.pbtxt)。普通基准的启动方式沿用
[视频性能记录](video-performance.md#普通调度基准与解码路径对照2026-10-18)，此次每轮
10次，decoder先native、再native-async、最后native。先启动App等待服务ready，
再录制并运行host，确保从首轮开始覆盖。录制命令在独立终端运行：

```sh
rtk proxy /home/xiankq/Android/Sdk/platform-tools/adb -s emulator-5554 push tool/e2e/decoder_trace.pbtxt \
  /data/misc/perfetto-configs/connect-decoder-trace.pbtxt
rtk proxy /home/xiankq/Android/Sdk/platform-tools/adb -s emulator-5554 shell perfetto --txt \
  -c /data/misc/perfetto-configs/connect-decoder-trace.pbtxt \
  -o /data/misc/perfetto-traces/connect-decoder-trace.pftrace
rtk proxy /home/xiankq/Android/Sdk/platform-tools/adb -s emulator-5554 pull /data/misc/perfetto-traces/connect-decoder-trace.pftrace \
  /tmp/connect-decoder-trace.pftrace
```

从对应App启动日志记录真实PID，分析只接收该进程；以下5162仅为本轮候选组：

```sh
rtk proxy python3 -B tool/e2e/analyze_decoder_trace.py \
  --trace-processor /tmp/connect-trace-processor \
  --trace /tmp/connect-decoder-explicit-async.pftrace \
  --benchmark /tmp/connect-e2e/decoder-explicit-async/result.json \
  --pid 5162 --output /tmp/new-decoder-analysis.json --require-markers
```

输出文件必须新建，不覆盖旧证据。按实际PID／codec／PTS唯一配对，不任选最近事件；
容许1µs的FFmpeg转换截断，保留实际PTS。同PTS重复codec组、同pair被多个input请求、
重复decoded、错token／PID或缺标记均不进入完整统计。缺token的历史样本只在明确
PID及唯一PTS下报告组件段，不能生成系统onVideo段。首次独立review发现错误归因，
4项实际失败回归后修复，8项测试通过并再审；日志为
`/tmp/connect-decoder-analyzer-review-{red,green}.log`。require-markers的exit0只表示
覆盖完整，与产品严格性能命令的exit1含义不同。

完整trace／分析／host回执前缀分别为`/tmp/connect-decoder-{boundary-r3,explicit-async,
native-return}`，基准结果在`/tmp/connect-e2e/<同名>/result.json`。临时PNG、trace和
原始失败证据均不进入Git。所有远端本批trace及配置副本已移除，host原件保留。

## 回归与仍开放的范围

Bridge Rust19项、Python9项、Bridge Flutter123项、全workspace严格Dart分析、clippy
和fmt通过。Android arm64 Bridge check通过；Apple／Windows Bridge check在既有
dart-sys／宿主SDK依赖处失败，不宣称四宿主整包通过。共享播放器已MCP热重载成功，
无Dart运行错误。

真实RemotePage五编码24秒完成，H264/H265/AV1/VP8/VP9均rendered，悬浮退出暂停、
逐会话停止及设置恢复通过，`mediaAcceptanceComplete=true`；每种实际PNG留在
`/tmp/connect-e2e/decoder-async-product-five/`。这是功能回归，非五编码延迟验收。
仍缺物理ARM/profile、老API上的实际回退、真实无线切网与小时级长稳；首帧1000ms
门槛继续开放。服务端源码、补丁及两个scrcpy JAR未改、未重建。

最终共享default路径关闭native trace及系统追踪，3轮60次输入的P50/P95=138/295ms，
200/300组合通过；首帧1197/1157/1122ms，1000ms仍失败，整体严格命令exit1。每轮
实际打开AMediaCodec，66次实际窗口检查、3次暂停恢复／停止分离和App／fixture清理
确认。原件`/tmp/connect-e2e/decoder-async-default-60/result.json`，不与30次带trace组
直接相除报告优化百分比。66次窗口确认并非66个输入延迟样本。


更新后的arm64签名release由现有`rtk proxy python3 tool/android.py build`完成，墙钟
47.36秒（Gradle45.9秒），签名、manifest、完整arm64 ELF、ZIP完整性及16KB对齐通过。
原件`/tmp/connect-artifacts/connect-arm64-decoder-async-release.apk`，46920990字节，
SHA-256 `fc6db347d819e42abaa630b452f5a7f32edab8b82b2ed37b6ed39aa951f9d022`，证书身份不变。
首次集成测试后直接`--no-pub`构建因旧测试插件注册而失败，日志
`/tmp/connect-decoder-async-release.log`保留；正确入口日志
`/tmp/connect-decoder-async-release-fixed.log`。不把两次不同准备状态当构建速度对照。
该ARM包未上物理手机，不能用x64 debug的运行结果宣称其已安装验证。


普通main恢复构建16.9秒／安装692ms，MCP热重载119ms成功，无Dart错误，设备首页
空态已目视并detach；截图`/tmp/connect-decoder-async-main-before.png`。启动跳34帧
和SurfaceSync1000ms告警保留，不计冷启动流畅通过。两AVD正常关闭、Gradle停止，
目标捕获JAR／进程／fixture确认无残留；按精确白名单清理394项debug输出
1506.8MiB，空闲50.18GiB，保留release、有效缓存与原始证据。
回执`/tmp/connect-decoder-{session-final-cleanup,remote-trace-cleanup,avd-shutdown,
async-debug-cleanup}.json`。下一步分别查首帧Core约0.7秒（校验约0.24–0.31秒）及
输出约0.4秒；不从持续输入的收益直接推导冷首帧改善。


收尾`0e7198b`补空结果门禁：空rounds的单元先红，修复后9项通过；真实R2缺rounds
失败报告明确exit1，不再KeyError。R3完整30输入重算仍exit0、数值一致，结果
`/tmp/connect-decoder-{empty-coverage-final,coverage-final-positive}.json`，测试日志
`/tmp/connect-decoder-empty-coverage-{test-red,final-tests}.log`。无输入时不允许以
all(empty)通过；该工具修正不改变ARM包字节。
