# 冷启动往返与首次原生绘制

2026-10-18。持续输入已使用显式异步解码；本批转向冷首帧。正常编码器枚举和临时
JAR 清理合为同一个 shell，减少每个新 ADB 连接的一次串行服务往返。完整首帧
1000ms 门槛仍开放，不能用一次低于门槛的样本替代全组验收。

## 同配置 A/B/A

双 API36 x64 AVD、SwiftShader、Flutter debug，生产 `default` 解码策略，H264
1280／60fps／8Mbps，实际576×1280，burst关闭。普通 Driver 调度，每组3个新连接、
6次输入、12次实际窗口像素检查、3次暂停恢复及释放；App和fixture清理均确认。
三组都开启 native frame trace，没有系统追踪。只有冷枚举清理流程变化。

| 流程 | validated ms | Core启动 ms | 首像素 ms | 输入P50/P95 ms |
| --- | --- | --- | --- | --- |
| 原流程 | 413 / 303 / 354 | 874 / 711 / 793 | 1587 / 1176 / 1222 | 117 / 171 |
| 同shell清理 | 263 / 269 / 276 | 586 / 619 / 698 | 1068 / 988 / 1147 | 174 / 236 |
| 返回原流程 | 365 / 231 / 311 | 760 / 647 / 675 | 1261 / 1088 / 1148 | 163 / 398 |

三组严格命令均exit1；返回组输入P95也失败。validated中位354→269→311ms方向支持
候选，但样本重叠，最初基线含AVD刚启动的冷负载，不能将差值全部归因于一个shell，
更不能承诺固定减少85ms。结构上少一次OPEN／退出往返由真实协议边界测试直接确认。
输入仅6次用于启动对照，不据此宣称持续输入分布稳定。

原始目录为`/tmp/connect-e2e/startup-shell-{baseline,candidate,return}/`，App和host
日志为`/tmp/connect-startup-shell-<组名>-{app,host}.log`。每组result和progress保留
失败数据及逐项像素、暂停、释放、清理回执。启动方式沿用
[普通调度基准](video-performance.md#普通调度基准与解码路径对照2026-10-18)，使用
`CONNECT_PERF_DECODER=default`、ROUNDS=3、TRANSITIONS=2、TRACE_FRAMES=true。
切换源码前结束Flutter；APK启动完成后才恢复候选源码，确保返回组实际运行旧二进制。

最终生产default关闭native trace和系统追踪，扩量为3轮60输入，P50/P95=148/221ms，
输入200/300ms预算通过；首帧1142/1064/1000ms，完整首帧仍失败、严格exit1。
Core670/653/627ms，validated264/316/272ms，输出466/410/372ms；实际decoder每轮
均为AMediaCodec。66次实际窗口、3次暂停恢复／释放及App／fixture清理完成。结果为
`/tmp/connect-e2e/startup-shell-final-60/result.json`，日志为
`/tmp/connect-startup-shell-final-{app,host}.log`。与trace开启的6输入组不是同条件收益
对照，也不是物理ARM或release性能证明。

## 清理与错误边界

冷目录探测仍校验官方JAR摘要、经sync完整上传，再运行原`list_encoders`命令。
包装shell保存`app_process`退出码，尝试删除同UUID路径，最后返回原退出码；删除
成功不能覆盖枚举失败。路径仍经原quote处理。正常shell_v2 EXIT或legacy EOF后
免第二个清理shell；`rm`仍是尽力而为，不将其回执称为远端文件不存在的证明。

上传失败、shell超时、输出超限或协议截断时，独立清理分支保留。持有semaphore的
owned job负责直到清理期限结束，调用方取消不取消它。没有把捕获上传提前并行，
失败sync不证明远端SEND已结束的边界仍保留。暖连接目录缓存、睡眠查询、未知启动
账本和编码器兼容检查保留，未跳过首像素或播放确认。

旧流程真实wire测试5项失败，独立实际shell执行测试因未删除临时文件失败；修复后
Core lib61 passed／2 ignored，clippy all-targets及fmt通过。新增覆盖shell_v2／legacy
正常完成、截断EXIT及caller abort后的fallback、有效目录配非零退出码；Linux／macOS
实际shell测试覆盖含引号路径、真实删除和退出码保留。该host shell测试不作为Android
设备测试；双AVD新连接枚举实际执行Android shell。未直接新增上传失败／超时／输出
超限注入，它们经同一未完成分支清理。只读review未发现新增缺陷。

红日志：`/tmp/connect-startup-shell-{red,script-red}.log`；绿日志：
`/tmp/connect-startup-shell-{core-tests,clippy}.log`。复现单元：

```sh
rtk cargo test -p interop-core --lib cold_screen_
rtk cargo test -p interop-core --lib encoder_probe_shell_removes
rtk cargo clippy -p interop-core --all-targets -- -D warnings
```

## 首个视频输出的原生CPU成本

重新分析[上一批异步输出](android-decoder-async.md)的同一Perfetto trace，PID5162。
分别绑定token的onVideo(PTS=0)与同进程的对应`JNISurfaceTextu`线程，所有时间
都来自系统trace；没有把Rust相对时钟减系统绝对时钟。

| token / renderer tid | onVideo→之后首swap开始 ms | 该窗口CPU Running ms | swap本身 ms |
| --- | --- | --- | --- |
| 1 / 5275 | 246.613 | 130.915 | 55.467 |
| 64 / 5407 | 136.841 | 131.681 | 70.703 |
| 128 / 5530 | 143.112 | 135.117 | 105.887 |

这里“首swap”是该视频输出之后的第一笔；线程此前已有空画面swap，不能称线程生命
周期的第一次swap。首轮窗口另有77.6ms runnable等待和35.3ms睡眠，不能全部归为
绘制CPU。后两轮acquireBuffer在onVideo后约0.3／0.7ms已成功，随后仍有大量CPU，
不支持把主要等待归因于挂载Texture、等待后续解码帧或Dart轮询。

改用同线程`MediaCodec::renderOutputBufferAndRelease#native`至下一笔swap的相同
窗口比较，三个renderer第一个输出CPU为130.862／131.647／135.078ms；紧邻后两次
各为0.993／0.914、2.734／0.965、1.136／1.180ms。首输出有可重复的专属原生成本。
当前trace的perf_sample和cpu_profile_stack_sample均为0，尚不能断言具体是shader
编译、管线创建还是其他初始化。新增调用栈采样是下一步证据，不继续盲猜decoder参数。

固定trace为`/tmp/connect-decoder-explicit-async.pftrace`。重查时按PID、上述tid和
token精确限定，`slice`经`thread_track`连到`thread`，取marker之后同renderer最早
`eglSwapBuffers`；在该utid的`thread_state`中，对窗口相交的`state='Running'`
区间求交集长度总和。不要直接累加slice嵌套dur，不把后续不同PTS的onVideo随意配帧。

### 新原生栈采样

旧流程返回组APK热重启后另录30秒诊断；它使用相同播放器，不参与A/B/A收益统计。
Perfetto配置沿用`tool/e2e/decoder_trace.pbtxt`并仅将duration改为30000；同时使用：

```sh
rtk proxy /home/xiankq/Android/Sdk/platform-tools/adb -s emulator-5554 shell simpleperf record \
  --app dev.scrcpyconnect.scrcpy_connect -e task-clock -f 400 \
  --call-graph dwarf,16384 --no-callchain-joiner --include-thread-name JNISurface \
  --duration 30 --size-limit 32M --clockid monotonic \
  -o /data/local/tmp/connect-startup-cpu.data
```

719样本、无丢样；内核符号访问受限告警保留，未改系统sysctl。本批只关心用户态
renderer。按PID4445的renderer tid4705／4752／4798第一个
`renderOutputBufferAndRelease#native`至下一笔swap开始过滤；窗口为trace纳秒：

| tid | release开始 | 下一笔swap开始 | 过滤后样本 |
| --- | --- | --- | --- |
| 4705 | 698725116610 | 698840832287 | 7 |
| 4752 | 702727244489 | 702973233204 | 13 |
| 4798 | 706487573146 | 706635184200 | 7 |

simpleperf为MONOTONIC，trace为BOOTTIME；使用最近`clock_snapshot`加偏移94／94／96ns
转换后才生成THREAD_BEGIN／END过滤文件。8个snapshot的偏移范围49–124ns，最近
样本距边界431934ns，大于该校正不确定度。格式遵循
[AOSP Sample Filter](https://android.googlesource.com/platform/system/extras/+/refs/tags/android-15.0.0_r36/simpleperf/doc/sample_filter.md)。
原始记录在`/tmp/connect-startup-cpu.{data,pftrace}`，窗口、过滤器、摘要分别为
`/tmp/connect-startup-cpu-first-{windows.json,summary.json}`及
`/tmp/connect-startup-cpu-first.filter`；首窗报告／调用栈／逐样本在
`/tmp/connect-startup-cpu-first-{report,callgraph,samples}.txt`。可用相同data重报：

```sh
rtk proxy /home/xiankq/Android/Sdk/platform-tools/adb -s emulator-5554 shell simpleperf report \
  -i /data/local/tmp/connect-startup-cpu.data \
  --filter-file /data/local/tmp/connect-startup-cpu-first.filter \
  --sort dso,symbol -n --children -g --max-stack 18 --percent-limit 2
```

27个首窗样本中，9个栈含`GL2Encoder::updateProgramInfoAfterLink`，7个含
`safe_glGetIntegerv`，另观察到shader创建／状态及uniform查询，经QemuPipe同步读写。
整体719样本与首窗27样本不能混用百分比；样本有限且部分MDK符号仅有地址，不能把
这些代理调用称为宿主shader编译耗时，也不能给各GL调用分配可靠耗时百分比。
Perfetto的Running是虚拟机记载的调度区间，不是物理CPU或真机功耗证明。证据把
下一步缩至renderer／模拟器图形代理首次初始化成本，尚未交付对应播放优化。

## JAR构建边界

本批只改主控Rust编排，服务端源码、补丁、固定版本和工具链均未改；两个JAR不重建。
重新核对SHA-256仍为：

- 官方5.0.1：`764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`
- 捕获扩展：`b46cd074600c33802dc764df8a9e056271725cb9b51daf4a3494dfffadbbac89`

Flutter／Rust正常编译直接嵌入已提交产物。仅服务端输入变更或明确做可复现性校验时
重建；`tool/check.sh`中的重建校验与APK组装是两条路径，见
[服务端构建说明](../../servers/scrcpy/README.md)。这与每次会话仍可能上传已有JAR是
两回事。未因调试重编服务端，也未把JAR重建视为首帧修复。

## 构建回执

Core的iOS／macOS／Windows MSVC交叉check分别1.34／1.32／1.24秒通过；不是四宿主
Flutter整包。Android x64实际基准与arm64 release分别构建。现有签名arm64 release
经`tool/android.py build`60.40秒完成，签名、manifest、ZIP完整性／16KB对齐和完整
arm64 ELF检查通过。原件`/tmp/connect-artifacts/connect-arm64-cold-start-release.apk`，
46920990字节，SHA-256为`d7b15c2e31dcb4d8526e2385e11368332e6bcf152f23a636c0ddbba580b040f6`。
证书身份不变；未冒称在物理ARM安装或运行。回执
`/tmp/connect-startup-shell-release-receipt.json`，构建日志同前缀`-release.log`。

普通main构建8.4秒／安装599ms，MCP热重载123ms成功、无Dart运行错误，设备列表
空态已目视后detach，图为`/tmp/connect-startup-shell-main.png`。Skipped39frames和
SurfaceSync1000ms告警保留，不称应用冷启动流畅通过。

目标本批15个精确会话JAR、捕获进程和fixture均无残留。额外扫描发现一个官方枚举
JAR，其mtime为2026-10-17T21:29:50Z，早于本批首次实验2026-10-18T03:17:40Z，
摘要与固定官方产物相同。首次清理扫描因此失败，回执保留；确认无scrcpy进程后，
仅删除该精确旧路径并复扫为空。这不是本批新正常清理遗漏的证据。回执分别为
`/tmp/connect-startup-shell-target-cleanup{,-final}.json`。本批远端采样、trace和配置
副本删除，host原件保留。核对AVD名称后正常关闭两台，停止Gradle，按既有精确白名单
移除394项debug输出、1486.0MiB，空闲49.67GiB；保留release和有效Flutter／Rust／
Gradle／CMake／SDK缓存。收尾记录为`/tmp/connect-startup-shell-{avd-shutdown,debug-cleanup}.json`。

## 下一步候选：默认主屏直接捕获

只读审查发现，固定scrcpy的[默认设置](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/options.c)
为H264、无named encoder、list=0；[客户端](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/server.c#L426)
只在显式list标志下请求枚举，普通捕获直接由
[SurfaceEncoder](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L254)
选择默认编码器并真正configure。本项目当前冷目录强制枚举不是用户指定的所有路径
硬要求；研究文档“启动前拒绝不兼容组合”位于既有实施验收段，不能伪装成不可调整的ADR。

候选仅覆盖合并偏好和覆盖之后仍为默认主屏／H264／videoEncoder:null，且目录未知
的情况。保持质量选项中的unknown，不填伪造available；同一精确连接已有明确目录
缺H264仍拒绝。非默认codec、named encoder、任何packageName继续严格枚举，避免
已知错误配置导致真实任务迁移。睡眠检查、资源和账本门禁、实际wire／尺寸／关键帧
及本机解码验证均保留；`session.quality.options`及保存质量设置仍实际枚举。

该候选尚未实施或实测，不能承诺减少250–350ms。需补默认直启和strict路径真实协议
测试、已知不支持／未知不伪造、取消／错误清理及独立应用unknown回归，再跑新连接
首像素。主屏失败仍会分配进程／编码器等资源，不能称完全没有副作用；独立应用
START_APP提交后的unknown与禁止重放规则不改。
