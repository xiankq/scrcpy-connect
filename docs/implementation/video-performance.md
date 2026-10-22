# 视频性能测量与实验结论

本文保留 2026-10-18 视频实验的方法、采用情况与限制。当前播放器和服务端来源分别见[工具链契约](repository-tooling.md#社区原版-fvp-0391)与[vendor](../../servers/vendor/README.md)。当时的本地 fvp snapshot 补丁、固定 MDK 和协作捕获 JAR 已移除；其数值不能登记为当前社区原版与官方 JAR 的性能通过。

当前源码仍有实时 Matroska 的小探测窗口、Android 显式异步 AMediaCodec 优先和 FFmpeg slice 回退；实际配置以 `packages/interop_bridge/lib/src/media/fvp_video_player.dart` 为准。编码目录、首帧与原生呈现是不同阶段，不能通过放弃身份、关键帧或像素核验换取启动数字。

## 测量方法

历史主场景为两台 API36 x86_64 AVD、SwiftShader、Flutter3.47.6 debug、Dart3.13.5、fvp0.39.1；多数高清实验请求 H.264 1280/60fps/8Mbps，实际576×1280，经典 ADB。它不是实体 ARM、Wi-Fi、发布构建、热功耗或稳定60fps证据。

- Core 启动累计时间来自同一 Rust `Instant`；设备核验、上传、metadata、关键帧和启动完成分别记录。
- output 启动从本代输出创建开始；prepare/texture 的局部 Stopwatch 不能与累计时间逐项相加。
- 完整首像素从 `session.start` 前计时，到真实首像素验证结束；不含 Flutter 进程启动或先前 `devices.connect`。
- 输入通过真实 `session.key` 改变独立目标 fixture 的4bit计数，直到 snapshot 可读到新计数。该指标包含派发、目标绘制、编码/传输/解码、读回和轮询，是输入到可读像素上界，不是面板扫描延迟。
- 普通 Driver 基准使用实际 `_DriverBinding`，不调用 WidgetTester pump 或 `RepaintBoundary.toImage` 强制重画 Texture；实际主控窗口另由 adb 截图，并按 Texture 矩形核对计数。窗口检查在输入计时外，但仍有系统开销。
- 历史严格预算为首帧1000ms、输入P50≤200ms/P95≤300ms、窗口确认3000ms；冷样本保留，清理失败不能洗成成功。

早期 fullyLive/integration binding、普通 Driver、静态/动态图案、trace 开关与 AVD 资源各改变测量条件，不能混为同一 A/B。`decoder.video` 成功事件说明实际解码后端；候选列表或 AVD 的 hardwareAccelerated 标志不证明物理硬解。

## 独立实验的结果

下表只保留会影响后续判断的结论；来源机制见[固定源码研究](../research/scrcpy-first-frame-performance.md)。采用的历史优化仍需在当前依赖重新测量。

| 实验 | 方法与结果 | 采用情况及限制 |
| --- | --- | --- |
| Matroska 探测 | 同静止 Settings、640/30、小样本对照；`probesize=32` 缩短 prepare，输出中位1036→411ms | 保留在实时视频适配器；`analyzeduration`单改无可靠收益并撤回；没有采用会丢首包的`+nobuffer` |
| 软件回退线程 | 对照默认 FFmpeg 与 slice，80次新像素；slice P50/P95约149/242ms，对照243/302ms | 保留slice回退，不全局强制软件解码或单线程；非高分辨率功耗证明 |
| 播放器参数 | 单变量测试立即渲染、同步codec、image-reader、direct AVIO等 | 均没有充分收益，撤回；不能重复拼装最快样本当优化 |
| 同连接编码目录 | 按精确Client缓存成功目录，暖校验约46–52ms；新传输仍重新探测 | 采用连接身份缓存；不复用远端进程或会话JAR，不说明持续输入改善 |
| 冷启动编排 | 身份校验并行、枚举与正常清理合并shell；默认主屏目录未知时直接捕获，严格格式/名称/应用仍预检 | 采用有界路径；失败/取消清理、未知能力与真实首帧核验保留。见[冷启动](video-cold-start.md) |
| 普通Driver后端 | 同配置原生60输入256/359ms，软件slice108/153ms；原生首帧仍超1000ms | 证明该AVD播放器路径有独立开销，不据此把生产默认换软件 |
| 显式codec异步 | 同配置A/B/A，以实际MediaCodec callback和系统trace核验生效 | 输入改善、首帧仍失败；AImageReader异步acquire不是codec异步证明。见[异步解码](android-decoder-async.md) |
| 高动态与目标资源 | 保持画面与画质，目标2→4→2vCPU；每组24输入 | P50/P95为1866/2202、1584/1865、1793/2145ms，全部失败；增加AVD资源不是产品修复。见[动态取样](video-dynamic-measurement.md) |
| raw窗口 | 单独比较PNG/raw，增加显式迟到窗口诊断 | 可取得慢场景分布；扩展期限强制diagnosticOnly/exit1，未提高硬预算 |
| ADB消费/转发 | 按同PTS记录首字节交出、整包、raw写和relay；动态组raw写约0.05ms，整包→relay约0.13ms | 没有证据把约1秒上游年龄归为该转发段；`AdbStream`首字节观测不含整个WRTE接收 |
| 逐WRTE观测 | 分开完整wire帧接收、路由与消费，保留慢header/payload边界 | 仅说明Transport等待，不能自动归因物理网络或把不同PTS关联 |
| 经典/Burst | 同配置各16输入，确认实际协商；P50/P95约1224/1493与1324/1670ms | 历史样本均严格失败，不能宣布普遍加速或普遍更慢；当时Burst为显式可选。当前产品默认请求，只有双方协商支持时启用，现行受控样本见下文 |
| 宿主快速排空 | 不解码，逐WRTE立即ACK；目标video TID strace，源PTS年龄仍约半秒 | 只排除该组长socket-write阻塞；无新像素核验，非端到端性能验收 |
| 源CCodec边界 | Perfetto中303个workDone与收到的PTS精确匹配，检查data-loss和时钟快照 | 本组主要年龄在完成回调前；含采集/队列/编码/IPC/调度，不能叫纯编码CPU或证明唯一根因 |
| 编码器/目标调度 | 固定格式与实际编码器对照，并看vCPU/runnable等待 | AVD软件编码器与调度影响不能外推实体硬编；无充分证据全局降低画质或改编码器 |
| 编码器首次分配复用 | 隔离候选复用首个codec，真实Java接缝验证创建/暂停/resize/失败清理 | 减少一次分配，完整首帧仍未过预算，候选未进入生产；源码实验已移除 |
| 有界输入/静态重复 | 隔离捕获候选改credit和每个源帧最多10次重复，保留stall期限 | 静态输入有收益，仍出现1036ms首帧；未替换生产JAR。源队列不支持未经证实的FIFO/Java回调堆积假设 |
| 提前挂载Texture | 同一隔离APK普通Driver A/B/A，保留ready和有效像素断言 | B验证阶段较短但完整首帧/输入不优于返回A；未采用，三组仍失败 |
| snapshot实现/生命周期 | 核对提交、callback、暂停顺序和原生空回调崩溃 | 旧本地保护已随fvp副本移除；不能据历史补丁称当前崩溃已修复，见工具链契约 |
| 黑洞/单流失活 | 分别注入TCP ACK丢失、应用层停转、控制WRTE不确认与HTTP消费者停读 | 各自测试精确故障边界，见[连接健康](connection-health.md)；不是低延迟优化或真实无线漫游 |

静态默认路径曾在旧依赖下3轮60输入达到首帧903/877/875ms、P50/P95147/225ms；高动态图案没有因此通过。当前原版切换后的运行证据见[验证记录](validation.md#构建与渲染证据)，不能把这组旧值当当前性能承诺。

## 时钟与帧身份

PTS用于帧身份，不直接当跨设备时钟。relay、onVideo与snapshot的同进程段使用共享Rust单调起点；消费者可在write Future完成前收到数据，因此relay段从`writeStartedUs`描述，不能将负值截零或把`writtenUs`换作因果起点。

目标input/draw与主控关联使用前后多次`/proc/uptime`往返的偏移区间，保留10ms量化、无休眠/时钟跳变假设。目标Perfetto BOOTTIME/MONOTONIC读取也不是严格同时采样误差界。各段中位数不可相加重建一条端到端路径；draw callback结束不是合成或编码完成。

相同PTS必须唯一对应目标事件、transport包、relay和decoded callback；缺失、重复、错误token/PID、跨会话或时间倒序均标不完整，不挑最近帧。最早包含新计数的编码帧可能早于轮询选中的snapshot，后者的draw→raw不能冒称最早源端延迟。

诊断`traceFrames/traceClock/tracePackets`会影响观测或snapshot实现，标记diagnosticOnly。编码前缀档案有32MiB/8192帧上限，封存完整chunk，不留半帧；离线分析在计时结束后运行，不增加第二消费者。原始帧档案工具见 `tool/e2e/video_fixture/{capture_first_counter,analyze_first_counter,analyze_player_archive}.dart`，系统trace分析见[异步解码](android-decoder-async.md#可复现的边界观测)。

## 普通调度基准与解码路径对照

先用独立目标准备 TCP 或实际已授权路径，并构建 `dart tool/e2e/video_fixture/build.dart`。fixture是隔离实验工具，不进入产品、不覆盖既有同名安装。当前主控/目标地址与产物路径由运行者提供；计时期间避免并行编译，使用新的系统临时输出目录。

受控弱网对照可先启动本仓库的有界回环代理
`tool/benchmark/weak_network_proxy.dart`。它按方向分别施加固定延迟和
token-bucket 带宽，并在待发送队列达到高水位时暂停读取源 socket，保留真实
TCP反压；代理本身不把队列扩成无界缓冲区。例如：

```sh
CONNECT_PROXY_LISTEN_PORT=15557 CONNECT_PROXY_UPSTREAM_PORT=15556 \
CONNECT_PROXY_UP_DELAY_MS=80 CONNECT_PROXY_DOWN_DELAY_MS=80 \
CONNECT_PROXY_UP_BPS=1000000 CONNECT_PROXY_DOWN_BPS=1000000 \
dart run tool/benchmark/weak_network_proxy.dart
```

性能目标随后使用 `CONNECT_E2E_PORT=15557`，其余 fixture、画质和预算参数保持
不变。该工具只提供链路条件，不能替代实体ARM/Wi-Fi、OEM编码器或最终面板
扫描验收。

2026-10-21 API36 x86_64 AVD的受控代理样本使用640宽、动态夹具和8次输入。
每组只有一轮，且目标出现Choreographer跳帧，因此只用于排除明显方向和保留
复现入口：

| 变量 | 输入到新像素 P50/P95 |
| --- | ---: |
| burst，30fps，2Mbps | 345/624ms |
| classic，30fps，2Mbps | 491/1308ms |
| burst，15fps，2Mbps | 385/618ms |
| burst，30fps，800kbps | 385/706ms |

burst的改善方向与ADB逐流ACK/credit模型一致；降帧率或降码率没有稳定改善，
不能据此写自动降档策略。要建立实体设备结论，仍需多个session、固定网络和
P50/P95/P99统计。

从仓库根进入 `app/`：

```sh
CONNECT_E2E_ADB=<SDK>/platform-tools/adb \
CONNECT_E2E_DEVICE=<主控serial> CONNECT_E2E_TARGET=<目标serial> \
CONNECT_E2E_VIDEO_FIXTURE=<本次fixture.apk> CONNECT_E2E_CAPTURE_DIR=<新输出目录> \
flutter drive -d <主控serial> \
  --driver=../tool/driver/live_video_performance.dart \
  --target=../tool/benchmark/live_video_performance.dart \
  --dart-define=CONNECT_E2E_ADDRESS=<目标地址> --dart-define=CONNECT_E2E_PORT=<连接端口> \
  --dart-define=CONNECT_PERF_DECODER=default \
  --dart-define=CONNECT_PERF_ROUNDS=3 --dart-define=CONNECT_PERF_TRANSITIONS=20 \
  --dart-define=CONNECT_PERF_MAX_SIZE=1280 --dart-define=CONNECT_PERF_MAX_FPS=60 \
  --dart-define=CONNECT_PERF_BIT_RATE=8000000 \
  --dart-define=CONNECT_PERF_MAX_START_MS=1000 \
  --dart-define=CONNECT_PERF_MAX_P50_MS=200 --dart-define=CONNECT_PERF_MAX_P95_MS=300
```

用同场景只更改decoder和输出目录进行对照。支持的值/参数以 benchmark 的setup校验为准，旧集成入口的参数不能直接移植。高动态/raw诊断额外参数见[动态取样](video-dynamic-measurement.md)。历史固定SDK哈希不再作为当前社区包的构建命令输入。

## 未完成边界

严格性能完成要求有效新像素、实际窗口、暂停恢复、停止/清理及预算分别通过；首包、playing、可读snapshot和面板显示不合并为一个成功标记。原生资源的`nativeDeleteConfirmed=false`不能被Texture撤下替代。

仍缺当前依赖的完整性能复验、实体ARM/profile/release、真实Wi-Fi/TLS切网、持续高动态、并发文件/声音/玻璃覆盖、P99、小时级长稳、温度功耗和共同音画时钟。旧隔离候选与原生栈样本用于排除假设，不作为这些要求的交付。
