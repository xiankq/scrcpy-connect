# 高动态窗口取样与目标资源对照

2026-10-18。生产默认仍为 Android 显式异步 AMediaCodec，H264 1280／60fps／8Mbps，
实际 576×1280。双 API36 x64 AVD、SwiftShader、Flutter debug、经典 ADB，持续变色
fixture；普通 Driver 调度，不使用 integration binding，也没有逐帧／系统追踪。
`6547f2c`修改仅为性能工具，不改变生产播放策略或两个 scrcpy JAR。

## 原始窗口与严格失败

原 PNG 路径在高动态首轮窗口取样超时，无法得到当前持续输入分布。新增可选
`CONNECT_E2E_SCREEN_CAPTURE=raw`，默认仍为 `png`。原始格式按
[AOSP screencap](https://android.googlesource.com/platform/frameworks/base/+/47e1cd5673dc3f95e09456050b81715cb48a7143/cmds/screencap/screencap.cpp)
的四个 uint32 头字段和逐行紧密像素解析。仅支持已验证的小端 RGBA8888；16 字节头、
非零且不大于8192的单边、12MiB总量、精确长度均校验，拒绝猜测旧头／其他格式。
返回原像素 view，PNG/raw 共用实际 Texture 矩形及四块颜色的精确计数检查。

主控实际头为1080×2400／format1／colorSpace1，完整10368016字节。独立 Dart 协议
回归覆盖缓冲区偏移、通道与行布局、截断／尾随、旧头、格式／尺寸／字节上限拒绝，
`/tmp/connect-raw-window-parser-root.log`。该回归只证明解析边界，实际窗口另由 AVD 验证。

暖空闲窗口一次交叉观察：raw224／177ms，PNG666／678ms；最早冷raw1997ms也保留。
不将此当视频收益。实际持续动态raw首跑依然超时：抓取和落盘1961ms、载荷编码118ms、
验证请求1256ms，组合3411ms；只得到首窗口，没有输入分布，严格exit1。原件为
`/tmp/connect-e2e/dynamic-raw-window/`。

新增显式 `CONNECT_E2E_DIAGNOSTIC_SURFACE_MS=15000` 允许继续取得迟到的真实窗口，
但硬预算始终3000ms，每项记录 `budgetMet`。扩展诊断无论输入和首帧结果如何，均强制
`diagnosticOnly=true`、`videoPerformanceComplete=false`、exit1；默认收集期限仍为
3000ms。`measurementLoopComplete` 只在全部轮次、实际窗口、暂停恢复与停止完成后
标为true，与性能门槛分开。完整原始窗口、抓取／载荷／请求耗时及失败阶段均落盘。

## 当前目标2vCPU动态数据

三轮24次输入，首像素2229／1978／2549ms，输入到解码像素可读P50／P95为1866／2202ms。
30次真实窗口计数全部匹配，其中21次超过硬3秒预算。窗口抓取和落盘中位1576.5ms，
载荷编码100.5ms，验证请求1515ms；这些分段中位数不能相加代替总量分布。
三次暂停276／313／258ms，恢复到新像素613／654／588ms；释放、设备移除、driver关闭、
fixture卸载及缺席均确认。原始结果 `/tmp/connect-e2e/dynamic-raw-diagnostic/`，日志
`/tmp/connect-raw-window-{dynamic-app,diagnostic-host}.log`。

这取得了当前慢场景分布，没有通过1000／200／300ms门槛。输入之间有实际窗口抓取的
间隔，含snapshot读回和轮询，不能当连续手势、稳定60fps、物理面板或真机数据。
原始第三轮暂停窗口已仅无损重新封装为PNG并逐字节核对像素，目视为VIDEO11／5850；
`/tmp/connect-raw-window-diagnostic-round3.png` 与
`/tmp/connect-raw-window-png-receipt.json` 保留源摘要及容器转换回执。不是生成的示意图。

## 限定资源归因实验

只改变被控AVD的vCPU数，保持同一画面、画质、主控和诊断配置，做2→4→2对照。
4vCPU通过 `/sys/devices/system/cpu/online=0-3` 实际核验；重新启动目标并等待boot完成、
恢复同一tcpip端口和forward，所有原始进程与启动参数单独保留。增加模拟器资源不算
产品优化，也不据此推导物理硬件编码器表现。返回组核验cpu online为0-1。

| 目标vCPU | 首像素，ms | 输入P50／P95，ms | 匹配窗口／迟到 | 严格结果 |
| --- | --- | --- | --- | --- |
| 2 | 2229／1978／2549 | 1866／2202 | 30／21 | exit1 |
| 4 | 2583／1971／2221 | 1584／1865 | 30／30 | exit1 |
| 返回2，暖复跑 | 2122／2629／2253 | 1793／2145 | 30／20 | exit1 |

每组3轮24输入，共72输入、90次实际窗口，暂停恢复、停止、App／fixture清理全部确认。
`nativeDeleteConfirmed`仍为false，不把Texture撤下等同底层资源已全部确认删除。
4核与返回组原件分别为`/tmp/connect-e2e/dynamic-raw-4cpu/`和
`/tmp/connect-e2e/dynamic-raw-return2cpu-r2/`。返回组暂停277／370／282ms，恢复至
新像素512／494／439ms；窗口抓取／载荷编码／验证请求中位1460／103.5／1435ms。
4核对应分段中位1726／110／1914ms，没有一并改善窗口采样成本。

返回2核首跑首像素4243ms、第一次输入未在3秒内读到新计数，未完成分布，独立保留
`/tmp/connect-e2e/dynamic-raw-return2cpu/`且清理确认。随后只同配置复跑一次取得
上述暖分布，没有删除冷失败。另一次直接启动qemu因缺动态库路径退出，改用相同
参数的官方emulator启动器后启动成功；它不是视频数据，不纳入对照。

结果方向支持目标资源会影响积压，但共享宿主负载、冷启动和窗口抓取也有变化，
不能将差值唯一归因为编码CPU或当成物理手机收益。所有组继续失败，不修改生产
画质、解码优先级或门槛。后续应取得实际ARM硬编／无线证据并按源采集／编码、
relay和呈现边界定位，不继续用增加AVD资源当产品修复。

2核基线每次输入需19–36次snapshot读取才见到新计数（含最终成功读取），控制回执
中位10.5ms。这不是一个阻塞1.8秒的snapshot，也不是目标应用收到输入／绘制完成
的ACK；当前关闭trace的结果不能唯一定位队列。输入计时仍含snapshot轮询成本。

复现入口为 `benchmark/live_video_performance.dart` 与
`test_driver/live_video_performance.dart`，沿用[普通调度启动](video-performance.md#普通调度基准与解码路径对照2026-10-18)，
设置decoder=default、ROUNDS=3、TRANSITIONS=8、1280／60／8000000；host额外设置
`CONNECT_E2E_VIDEO_MOTION=true`、`CONNECT_E2E_SCREEN_CAPTURE=raw`、
`CONNECT_E2E_DIAGNOSTIC_SURFACE_MS=15000`。每次使用新capture目录，不覆盖失败。

## 默认路径回归与验证

不设置raw／扩展期限，静态fixture的默认PNG路径3轮24输入完整exit0；首像素
921／903／828ms、输入P50／P95=157／210ms，30个PNG窗口全部匹配且满足3秒硬预算，
暂停恢复、停止、App／fixture清理确认，errors为空。原件
`/tmp/connect-e2e/raw-window-default-png-control/`，日志
`/tmp/connect-raw-window-default-png-host.log`。这确认新工具没有破坏默认严格路径，
不能将静态通过覆盖前述动态失败。

四个Dart文件的严格分析、格式无变更、独立协议回归通过，只读review未发现可证
缺陷。没有Rust／生产Dart／JAR变化，不因工具改变重复编译相同release。官方SDK
后续版本与snapshot问题另见[版本核查](../research/mdk-sdk-snapshot-followup.md)，
没有可直接升级的后续正式版本，也不宣称历史native崩溃已解决。

普通main构建8.4秒、安装1133ms，MCP热重载137ms成功且无Dart运行错误；设备列表
空态实际截图`/tmp/connect-raw-window-main-reloaded.png`已目视。启动Skipped35frames、
SurfaceSync1000ms及1445ms长帧仍保留。目标捕获／枚举JAR和捕获进程扫描为空、
fixture缺席；结束本轮CLI／停止Gradle，自有双AVD核验名称后关闭且PID消失，forward
缺席确认（未指定serial的remove尝试exit1不计成功）。清理394项明确debug输出
1486MiB，余量40.87GiB，release、有效构建缓存和原始证据保留。回执为
`/tmp/connect-raw-window-{target-cleanup,avd-stop,forward-cleanup,debug-cleanup}.json`。
两份JAR摘要与既有清单再次相符、未改未重建；原有五项未跟踪用户文件未改，未push。
