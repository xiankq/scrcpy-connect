# 视频首帧、持续新像素与阻塞恢复

最新增量见[时钟括号与Surface输入实验](#时钟括号与surface输入实验2026-10-18)：
已把动态等待范围收窄到目标绘制结束至主控payload读取之间，仍未达到严格性能门槛。

2026-10-18。按用户最新优先级推进视频性能、首帧和连接稳定性；USB 等产品工作顺延。本批没有修改或重建 scrcpy JAR。[产物与官方机制核查](../research/scrcpy-first-frame-performance.md)区分官方 vendor 文件和当前视频依赖的既有暂停补丁产物。

## 测量范围

两台 API36 x86_64 AVD，主控 emulator-5554、被控 emulator-5556；被控 secure=0 的隔离 TCP 调试实验端经宿主 25556 转发，主控访问 `10.0.2.2:25556`。Flutter3.47.6/Dart3.13.5，fvp0.39.1。Flutter 为 debug，native hooks 编译 Rust release；不把这些数值当物理双机无线、TLS 配对、发布包或热功耗的验收。

- Core `captureStartupTimingMs`：同一 Rust `Instant` 的累计毫秒，依次记录设备/唤醒条件/编码器选择核验、JAR 上传、metadata、编码关键帧及启动完成。不是把设备媒体 PTS 与主控时钟相减。
- 输出 `outputStartupTimingMs`：从创建本代输出起，累计记录 relay 打开、player 打开、实际播放确认和 snapshot 首像素。`video.prepare`/`video.texture` 两项是 player.open 内部独立 Stopwatch 的观测，不能与累计项逐个相加。
- `firstDecodedFrameMs` 从 Core 已返回编码首帧之后开始；不含 ADB 设备连接或 Flutter 冷启动。实际 Texture 挂载和截图另验，不能称它为已经显示到屏幕。
- 图案测试从主控发送真实 `session.key` 前计时，直到实际 MDK snapshot 包含目标新计数器。包含控制传输、目标绘制、编码、媒体传输、解码、snapshot 和最多10ms轮询等待，是输入到解码像素可读的上界。每轮再检查 Flutter 真正呈现的截图；没有测量逐帧玻璃到玻璃延迟。

## 首帧对照与被否定的尝试

同样静止 Settings、H264、maxSize640/maxFps30，未改服务端或验证要求。

| 三次样本（毫秒） | 原配置 | 仅限探测字节数后 |
| --- | --- | --- |
| Core启动 | 924 / 787 / 755 | 882 / 738 / 764 |
| 输出到已解码首像素 | 1131 / 1036 / 995 | 491 / 410 / 411 |
| 启动到已解码首像素（两段相加） | 2055 / 1823 / 1750 | 1373 / 1148 / 1175 |

输出段中位数1036→411ms（约60%减少），完整会话启动中位数1823→1175ms（约36%减少），各只有三次实验样本，不是生产分位数。原始结果 `/tmp/connect-video-baseline-result.json` 和 `/tmp/connect-e2e/video-probe-32bytes/result.json`。

分段红回归 `/tmp/connect-video-probe-red-r3.log` 实际输出1100ms，900ms门槛失败；其中 prepare568ms、texture585ms、opened609ms、playing743ms、verified1098ms。先只加 `avformat.analyzeduration=100000`，实测1060/1122/943ms，没有明显收益，已撤回；不能把这个尝试记作优化。最终仅对本项目已提供 CodecPrivate/尺寸的 Matroska 输入配置 `avformat.probesize=32`，prepare 降到8/2/2ms，三次900ms回归通过；保留原始 IDR、播放确认和32×32像素验证，没有采用会丢弃探测阶段初始包的 `+nobuffer`。

此设置限定在共享实时视频适配器，未改文件播放器或音频策略。32 是 FFmpeg 允许的最小探测字节数，减小探测量可能减少可推断信息，所以必须验证自己的完整容器头与各编码，不可照搬到任意未知裸流。[FFmpeg格式参数](https://ffmpeg.org/ffmpeg-formats.html#Format-Options)、[fvp低延迟实现及初始关键帧注释](https://github.com/wang-bin/fvp/blob/v0.39.1/lib/src/video_player_mdk.dart)。

五编码真实共享播放器及各3次暂停恢复16秒通过：H264/H265/AV1/VP8/VP9 输出首像素545/607/409/294/287ms，每种都有实际PNG和快照回执。`/tmp/connect-video-probe-five.log`、`/tmp/connect-e2e/video-probe-five/result.json`。这里只证明五种仍能启动与恢复，不能据此宣称五种均变快或 HEVC 画质通过。早期计时插桩曾出现编译错误及事件类型错误，均修正后重跑；这两次失败不是用户性能问题的复现。

## 两种真实阻塞先红后绿

1. `run_video` 先接收完整 scrcpy 包再向本地 relay 发送。上游 ADB 已交付半包却不断开时，下游尚未看到首字节，其局部期限无法生效。真实内存 ADB OPEN/OKAY/WRTE→生产 `run_video`→认证 TCP 用例，11秒后仍 `streaming`，实际红日志 `/tmp/connect-video-transport-red.log`。
2. HTTP 消费者保持连接但停止读取，实际 TCP 接收窗口填满后，relay 写入无限等待、上游不再 drain。公开 `MediaStreams` 命令和真实 TCP 用例，12.2秒后仍 `streaming`，实际红日志 `/tmp/connect-video-http-red.log`。

修复：上游完整单元的第一字节之后，header/session/payload 总计限10秒；HTTP响应头和每个实际待交付chunk限10秒。失败沿既有取消路径关闭该视频通道；没有随意丢弃有参考关系的压缩包，也不关闭设备上其它ADB服务。完整包之间依旧可以长期静止，明确取消仍立即结束。

两组窄回归3/3和2/2通过，10.30/10.05秒。包括头、session、payload三类截断、完整包间静止10.3秒、半包取消和消费者背压取消。固定10秒意味着极慢消费者也会被结束；这是已有输出无法交付的期限，不是所有画面都必须固定产生新帧。

```sh
cargo test -p interop-core --lib video_transport_deadline -- --nocapture
cargo test -p interop-core --test media_http video_transport_deadline -- --nocapture
```

## 持续新像素与重复连接

`tool/e2e/video_fixture` 是独立实验目标APK，不属于产品，不改变被控端无需安装额外App的规则。它用四块色彩编码4 bit计数器；真实DPAD_DOWN松开后Android绘制下一个计数。测试逐次识别期望计数，旧帧、空白纹理、仅控制写回执都不能通过。截图按Texture实际矩形映射采样，逐轮检查停止回执的textureDetached，拒绝disposeDeferred/cleanupUnconfirmed，不捏造公开API无法确认的nativeDeleteConfirmed。

r1/r2初始严格颜色不匹配，r3颜色比例可识别但首个操作无变化；独立目标最终截图确认Android首次沉浸教育提示延迟出现、压暗画面并截获按键。夹具取消沉浸请求后r4完整25秒通过：4轮连接/新会话/暂停恢复/停止、32次新计数及4张实际Flutter截图。输入到解码像素P50=448ms、最近秩P95=495ms、最大562ms；约0.45秒的持续交互仍是待优化瓶颈。取帧方式与readback开销计入，不解释成纯网络延迟。

`/tmp/connect-e2e/video-performance-r4/result.json`、`/tmp/connect-video-performance-r4.log`。r4发现host driver成功后SDK直接exit(0)，finally不执行；已由主代理实际卸载自己的夹具并写明人工补清理来源，不能称r4自动清理通过。驱动修正为responseDataCallback中先完成卸载/确认包不存在/返回Settings并写cleanup，再交给SDK退出，finally仅兜底普通异常。

最终r5完整66秒通过：6轮新连接/会话、120次精确新计数、6次暂停恢复、6张实际Flutter截图和6次确认纹理分离。输入到解码像素P50=446ms、最近秩P95=452ms、P99=569ms、最大571ms；启动到解码首像素1189/1119/1121/1028/1212/1244ms。主控每轮单调计时的媒体观测区间共50451ms、640包/535040容器字节，这是低复杂度色块负载，不是高运动带宽或满负荷帧率测试。`videoPerformanceComplete`和`fixtureCleanupConfirmed`均true，cleanup的uninstalled/absent均true。`/tmp/connect-video-performance-r5.log`、`/tmp/connect-e2e/video-performance-r5/`；不是小时级长稳，也不把主动重连误称自动故障恢复。

可重复运行（工作目录apps/connect，先从仓库根构建夹具）：

```sh
python3 tool/e2e/video_fixture/build.py
flutter pub get --offline
CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
CONNECT_E2E_VIDEO_FIXTURE=/tmp/connect-video-fixture/video-fixture.apk \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/video-performance \
flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/video_performance.dart \
  --target=integration_test/video_performance_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=25556 \
  --dart-define=CONNECT_PERF_ROUNDS=6 \
  --dart-define=CONNECT_PERF_TRANSITIONS=20
```

运行前目标须是专用可唤醒的调试设备，25556转发已建立；驱动拒绝替换已有同名夹具安装。生产构建后使用--no-pub运行集成测试前，须先在应用目录pub get准备测试插件注册，见[打包说明](android-packaging.md)。

## 未关闭的主任务

- 继续降低平台AMediaCodec持续输入到新像素等待；冷连接Core启动核验仍约0.35秒，同连接暖校验已降至46–52ms，见后续连接级目录优化。不能用绕过真实能力/解码验证来换数字。
- 真实Wi-Fi切换、实际已配对Android adbd的网络故障恢复、视频活动恢复继续验证；后续真实TCP黑洞/Runtime TLS协议夹具已补，不能扩大为这些场景已通过。
- 播放器失败传播已由后续生命周期修复补齐，物理MediaCodec崩溃和原生资源释放仍需独立故障实测；不能仅依赖HTTP relay结束。
- Profile/release、真实ARM硬解、不同ROM/分辨率/帧率、并发文件/声音/玻璃覆盖、输入P95/P99、持续高动态和小时级长稳、温度/功耗、共同音画时钟继续开放。

没有把“数据已收到”“编码首帧已就绪”“snapshot已读取”“实际屏幕已呈现”合并为同一个成功标记。

## 持续交互分段与解码路径对照

同日继续使用相同双AVD、H264 640/30和独立计数图案。基准新增每次控制回执耗时、逐次snapshot耗时与MDK原生`decoder.video`事件。控制回执通常1–4ms、snapshot通常1–2ms，却能连续几十次读到旧计数；不能把约350–450ms稳定等待归因于readback本身。冷启动仍有个别较慢snapshot，全部保留在统计中。

先设置P95≤300ms，平台默认路径16次操作实际P50=397ms、P95=784ms失败，`/tmp/connect-video-latency-red.log`。按已公布假设单变量尝试，未满足门槛的设置均撤回：

| 对照（各16次，毫秒） | P50 | P95 | 结论 |
| --- | ---: | ---: | --- |
| `fps=-1`立即渲染 | 352 | 512 | 无稳定充分收益，撤回 |
| AMediaCodec `async=0` | 380.5 | 469 | 撤回 |
| AMediaCodec `image=1` | 401.5 | 546 | 撤回 |
| `avformat.avioflags=direct` | 362.5 | 615 | 撤回 |
| 仅使用默认FFmpeg | 240.5 | 421 | 用于定位，不替代平台默认硬解优先 |
| 仅使用FFmpeg且单线程/slice | 183.5 | 405 | 继续隔离线程策略，不全局固定单线程 |

对应结果目录为`/tmp/connect-e2e/video-latency-{asap,syncdecode,imagereader,direct,software-default,software}/`。这些实验不是把几个设置叠加后挑最快样本。`decoder.video`成功事件可以确认实际打开的后端；`mediaInfo.codec`和候选列表不能。`AMediaCodec`也不证明是物理硬件加速，本批未新增这种承诺。[MDK事件定义](https://github.com/wang-bin/mdk-sdk/wiki/Types#class-mediaevent)、[MDK公开参数](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)、[AMediaCodec参数](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#amediacodec)。

仅取消FFmpeg的跨帧线程、保留slice策略后，4轮80次实际新像素P50=151.5ms、P95=245ms；随后同样80次默认FFmpeg对照为244/254ms。最大值373/460ms，冷样本均未剔除；两组P95≤300ms其实都通过，不能把文件名`fallback-red`误写成失败。目录分别`video-latency-slice`、`video-latency-fallback-red`，每轮实际截图、暂停恢复、纹理分离及夹具自动卸载均通过。继续加入P50≤200ms门槛，以锁住持续等待而非仅比较一次冷峰。

FFmpeg默认允许跨帧线程，其额外等待与本次对照相符；选择`thread_type=slice`避免等待后续帧，仍允许有切片时的帧内并行，不强制所有设备单线程。产品仍保留各平台原先硬解优先，仅改变共享实时视频播放器中的FFmpeg回退参数；音频和文件播放器未改。高分辨率下的吞吐/功耗与各实际codec线程实现仍需继续测量。[FFmpeg线程选项](https://ffmpeg.org/ffmpeg-codecs.html#Codec-Options)。

基准现在支持`CONNECT_PERF_DECODER=platform|software|software-default`，默认platform；后两者要求收到实际FFmpeg打开事件，防止候选与实际后端混淆。相同fixture命令可重复对比，不必编辑生产优先列表。以上收益限于软件回退路径；平台AMediaCodec稳定等待仍约0.35–0.45秒，不能宣称主任务已解决。

加入P50门槛后实际复跑：`software-default`的2轮40次P50=243ms、P95=302ms失败；相同P50≤200/P95≤300要求下，`software`的4轮80次P50=149ms、P95=242ms通过，实际FFmpeg回执与自动卸载均通过。没有放宽预算、跳过冷操作或取消真实新计数判断。`/tmp/connect-video-latency-p50-{red,green}.log`与对应结果目录保留。复现时在前述drive命令后追加以下参数，只将decoder从software-default换成software：

```sh
--dart-define=CONNECT_PERF_DECODER=software \
--dart-define=CONNECT_PERF_ROUNDS=4 \
--dart-define=CONNECT_PERF_TRANSITIONS=20 \
--dart-define=CONNECT_PERF_MAX_P50_MS=200 \
--dart-define=CONNECT_PERF_MAX_P95_MS=300
```

## 已打开播放器的失败传播

真实回归接缝现在复用正式Bridge的`VideoOutputLifecycle`，经过PortableVideoOutputs和播放器事件流，不是孤立测试代次比较。红阶段确认已打开播放器报错、HTTP仍streaming时，正式`session.failed`为0；另确认迟到旧relay结果会误停已提交的新代，重复故障会多次stop。`/tmp/connect-video-lifecycle-red.log`保留这些失败。

正式事件和250ms媒体poll统一处理已提交输出的device/generation/relay/texture所有权：先同步认领并撤下对应输出，再并行请求远端stop和本地释放，避免等待远端回执期间重复结束，也不在旧清理完成后再查找并关闭新输出。候选尚未提交时的失败事件不能越权关闭旧输出；正式poll的真实恢复失败仍终止原活动，不把已经EOF的冻结旧纹理假称恢复成功或反复消费single-use入口。

新7条回归及既有Portable/Presentation共41条通过，`/tmp/connect-video-lifecycle-final-green.log`。覆盖已打开失败、候选失败、迟到旧代、迟到relay、偏好/暂停合并收据、重叠故障和旧stop/释放未完成时重新打开另一会话。测试中的播放器端口用于精确注入故障及控制回执时序；这不是已验证物理设备MediaCodec崩溃、网络切换自动恢复或原生delete完成。

最终源码正式RemotePage五编码28秒通过，结果`/tmp/connect-e2e/video-latency-product-five/result.json`，日志`/tmp/connect-video-latency-product-five.log`；H264全屏Settings和计数夹具VIDEO12代表截图已目视，其余图案计数逐轮自动检查。完整Bridge114项通过，`/tmp/connect-video-latency-bridge.log`。HEVC既有低清约束与真实网络自动恢复继续开放，没有把这些成功扩大成画质或全链路低延迟验收。

相关应用43项通过，`/tmp/connect-video-latency-app.log`。严格分析首次报新增生命周期模块/测试的5处括号风格问题，修正后4.9秒无问题。普通main构建15.7秒、安装574ms、CLI R热重启2557ms，设备列表截图已目视并detach；`/tmp/connect-video-latency-main.log`与`/tmp/connect-video-latency-main-restarted.png`。FRB旧isolate投递与SurfaceSyncGroup启动告警仍在，不记为启动性能达标。

`25c2ddc`提交失败生命周期修复，`d0215db`提交软件回退线程策略和测量门槛。JAR摘要再次一致，未构建服务端。清理406处过期debug/测试输出和Flutter中间缓存，实际释放3345MiB；筛选时也误删旧Dart AOT缓存，已明确修正记录并用当前代码补建arm64 release：78.42秒通过，同模式第二次4.64秒通过，APK摘要相同。最新签名产物`/tmp/connect-artifacts/connect-arm64-video-release.apk`，46,740,766字节，SHA-256 `506f80ff966bed5669640c66e397120a0a400b9a3271a5fa319b7f7ae657ffd9`；ZIP/manifest/ARM64 ELF/16KB ZIP对齐及签名由打包工具检查，不是物理ARM运行证据。[打包与缓存细节](android-packaging.md)。

闲置Gradle再次停止，保留有效Rust/native hooks/CMake/Gradle及重建后的release缓存、当前成品和临时原始证据，最终空闲73.8GiB。`/tmp/connect-video-latency-cleanup.json`记录误删和补建，未抹去过程。主控普通App保留运行，被控返回Settings；最终四个性能会话精确JAR路径由宿主另验均不存在。原有五项未跟踪文件未动，未push。

## 本批回归与构建边界

`1cc5774`提交Rust阻塞修复和捕获启动分段，`d41a26d`提交播放器探测限制、输出计时与真实图案基准。完整Core测试141 passed / 48 ignored，35 suites，忽略项不计实际设备验证；Bridge完整107项、应用远控/会话/后台相关43项通过。严格Flutter分析无问题，165输入的生成一致性通过，cargo fmt及Core全targets clippy -D warnings通过。日志分别为`/tmp/connect-video-core-regression.log`、`/tmp/connect-video-bridge-regression.log`、`/tmp/connect-video-app-regression.log`、`/tmp/connect-video-clippy.log`。

Core交叉check：aarch64-apple-ios 8.61秒、aarch64-apple-darwin 3.19秒、x86_64-pc-windows-msvc 6.59秒通过（包含共享构建目录锁等待），分别留存`/tmp/connect-video-check-<ios|macos|windows>.log`。Android当前源码已在实际x64 Flutter整包运行，不将这些交叉check当成Apple/Windows宿主Flutter链接和运行，也没有为本批重新生成可分发ARM release。

正式RemotePage五编码28秒通过，`/tmp/connect-e2e/video-product-five/`、`/tmp/connect-video-product-five.log`；H264实际全屏设置页及图案VIDEO4/VIDEO8代表图已目视。r5每张Flutter截图的计数由测试自动验证。宿主另独立检查r5六个精确会话JAR路径均已不存在，没有删除其它远端文件。

普通lib/main.dart实际构建27.4秒、安装584ms，CLI R热重启2250ms；`/tmp/connect-video-main.log`和`/tmp/connect-video-main-restarted.png`，设备列表空态已目视后detach。两条FRB旧isolate投递告警和启动SurfaceSyncGroup告警仍有，未将其写成启动性能达标。

所有编译/测试/drive/run进程结束后停止本批闲置Gradle daemon，实际清理391处debug/测试暂存/incremental目录及29个过期非视频测试可执行文件，释放11132MiB，余量73.2GiB，记录`/tmp/connect-video-cleanup.json`。保留当前视频反馈循环的测试可执行文件、Rust依赖、native hooks、release/Gradle缓存和必要临时原始证据，避免清理导致下一轮视频验证/打包全量重建。用户原先五项未跟踪测试/examples未修改，未push。

## 同一设备连接再次打开远控

后续同日测量发现，每次捕获都会独立推送官方JAR、运行`list_encoders`并清理，即使正在复用同一ADB传输。`EncoderCatalog`现在按实际`Client`连接身份共享一次成功枚举，不按设备ID、地址或banner复用。并发请求共享初始化；失败或取消可重试，连接关闭时拒绝结果，替换连接重新枚举；最多保留32个最近连接的目录，淘汰不关闭连接。缓存不落盘，不复用捕获进程或会话JAR，每次仍重新检查休眠状态、启动服务端并验证编码关键帧与实际解码像素。

窄回归在未复用实现上实际2失败/2通过，最终6项通过：顺序/clone、并发合并、换传输与关闭、失败/取消重试、探测中关闭、容量淘汰不误断线。`/tmp/connect-encoder-catalog-{red,green}.log`。独立只读review未发现可证正确性问题。

双AVD真实相同连接基准先以250ms暖校验门槛失败：第二次校验378ms、Core启动814ms。保持同门槛后4轮通过，首次冷校验361ms/Core805ms/启动到解码1197ms；后三轮校验52/47/46ms、Core431/450/440ms、启动到解码711/707/739ms。优化的是已连接设备的重复打开，首次冷启动没有改善。16次实际新计数P50/P95为348/557ms，不能把启动收益记为持续解码延迟改善。`/tmp/connect-video-warm-validation-{red,green}.log`，结果在`/tmp/connect-e2e/video-warm-validation-{red,green}/`。

随后默认断开/重连3轮15秒通过，校验346/357/360ms，Core741/808/808ms：新传输仍执行完整探测，未错误复用上一连接。逐轮新像素、暂停恢复、截图、纹理分离及夹具自动卸载均通过，`/tmp/connect-video-catalog-reconnect.log`、`/tmp/connect-e2e/video-catalog-reconnect/result.json`。

在前述图案命令后追加可重测同一连接暖启动；默认不复用连接：

```sh
--dart-define=CONNECT_PERF_KEEP_CONNECTION=true \
--dart-define=CONNECT_PERF_ROUNDS=4 \
--dart-define=CONNECT_PERF_TRANSITIONS=4 \
--dart-define=CONNECT_PERF_MAX_WARM_VALIDATION_MS=250
```

## TCP链路丢失且对端没有EOF

AOSP ADB默认启用1秒间隔、10次失败探测。本项目此前仅设置TCP_NODELAY，空闲网络黑洞不会自动变为closed，既有Runtime监控因此无法进入重连。现于Rust`connect_tcp`建立后、TLS包装前设置相同keepalive；Android/Linux另设11秒TCP_USER_TIMEOUT，覆盖有数据未获ACK而走TCP重传的情况。没有添加固定视频帧间隔期限，也没有修改USB、自定义字节transport或普通反向转发socket。[AOSP连接入口](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/socket_spec.cpp#238)、[Unix探测参数](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/sysdeps_unix.cpp#28)、[TCP_USER_TIMEOUT语义](https://kernel.googlesource.com/pub/scm/docs/man-pages/man-pages/+/refs/tags/man-pages-6.13/man/man7/tcp.7#1212)。

回归完成真实ADB握手后，在测试自己接受的TCP socket上安装RET0过滤器，保持该对象打开，丢包发生在TCP处理/ACK之前；不是仍代答ACK的用户态TCP代理，也不是关闭peer制造EOF。宿主SO_ATTACH_FILTER返回EPERM，user namespace也不可用；该次失败属于夹具权限失败，没有当成目标故障红证据。改在专用API36 x64 AVD中执行同一Rust测试二进制，以测试进程`su 0`安装过滤器；产品没有新增root要求，未改宿主或AVD全局防火墙。

真实Android红阶段两个丢包用例16秒后仍在线/OPEN等待，健康静止17秒通过；最终三项17秒全部通过：空闲丢包被识别、未ACK OPEN不依赖120秒操作期限而结束、健康静止仍在线并可主动关闭。`/tmp/connect-tcp-liveness-android-{red,green}.log`。默认宿主运行显式ignore两项需过滤器权限的用例，不能将ignored计为通过；Android实际命令使用`--include-ignored --test-threads=3 --nocapture`。

这些期限检测的是TCP链路/ACK丢失；仍正常ACK却不处理ADB的代理或daemon应用层挂起、真实Wi-Fi切换、ROM后台策略、视频活动自动恢复与物理双机长稳仍需独立验证。Apple/Windows只共享keepalive，尚未声称它们具有Android/Linux的未ACK数据11秒边界。

公开Runtime另使用真实TLS socket和ADB协议端夹具，手动端点、关闭伴随轮询，按公开事件验证offline→同ID connected、设备记录仍仅一个。作为对照临时仅保留原TCP_NODELAY策略构建测试二进制，构建后立即恢复最终源码并逐字节核对；原策略在25秒恢复期限失败，整项30.23秒。最终策略相同夹具20.84秒通过，包含显式disconnect后第二socket实际EOF、autoReconnect=false和额外5秒无第三次accept的断言。`/tmp/connect-tcp-runtime-android-{red,green}.log`。这是Android内核上真实TCP/TLS与正式Runtime恢复链路，协议端不是实际配对的Android adbd，未宣称实体无线配对/切网或已有视频活动恢复通过。

独立review补强了主动close的验收：原先只检查同步取消标志，现保留peer并要求2秒内真实读到EOF。最终Android三项重新通过，`/tmp/connect-tcp-liveness-android-verified.log`。跨包feature组合会改变测试可执行文件哈希，最终执行路径从本次Cargo JSON的`compiler-artifact.executable`读取，不能拿旧文件名代替当前产物。

交叉构建反馈循环（NDK路径按本机安装配置；两个同名测试分别属于两个包）：

```sh
CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$ANDROID_HOME/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android26-clang" \
CARGO_BUILD_JOBS=2 cargo test -p interop-adb -p interop-core \
  --test tcp_liveness --target x86_64-linux-android --no-run \
  --message-format=json > /tmp/connect-tcp-test-artifacts.jsonl
```

分别从JSON读取两个executable，推送专用AVD的`/data/local/tmp/`并chmod755。ADB测试以`adb shell su 0 <binary> --include-ignored --test-threads=3 --nocapture`运行；Core测试以`adb shell su 0 env TMPDIR=/data/local/tmp RUST_MIN_STACK=8388608 <binary> --ignored --nocapture`运行。执行结束删除自己推送的二进制；不在普通手机要求root或安装测试APK。

## 本批最终验证与交付

`9542e05`提交连接级目录复用；`25e9bac`提交TCP丢失识别及Runtime恢复回归。完整Core147 passed/49 ignored、37 suites，`/tmp/connect-catalog-core-regression.log`；ADB50 passed/13 ignored，`/tmp/connect-catalog-adb-regression.log`。新增目录6项包含在Core通过数内；有权限条件的Android故障结果由上面的独立显式运行证明，不把default ignored冒记为通过。最终补强的EOF断言在`connect-tcp-liveness-android-verified.log`实际通过。

两包all-target clippy -D warnings8.51秒、cargo fmt、严格Flutter分析4.7秒及165输入生成一致性通过，日志前缀`/tmp/connect-catalog-{clippy,analysis,generated}`。Core iOS/macOS/Windows MSVC交叉check4.08/4.07/4.02秒通过（`/tmp/connect-catalog-check-<ios|macos|windows>.log`），不是三宿主Flutter整包或运行证据。

最终Rust源码的正式RemotePage五编码24秒通过，`mediaAcceptanceComplete=true`，`/tmp/connect-video-catalog-product-five.log`及`/tmp/connect-e2e/video-catalog-product-five/result.json`；H264全屏Settings与悬浮退出截图已目视。普通`lib/main.dart`构建13.5秒/安装598ms、CLI R热重启1724ms，设备列表空态截图已目视后detach（`/tmp/connect-catalog-main.log`、`/tmp/connect-catalog-main-restarted.png`）。DTD发现的IDE实例没有活动App，实际热重启使用本次CLI连接；旧isolate投递和SurfaceSyncGroup启动告警保留，未宣称启动流畅已通过。

最终arm64签名release总65.03秒（Gradle63.9秒），同模式第二次4.09秒，APK摘要相同。当前`/tmp/connect-artifacts/connect-arm64-video-release.apk`为46,757,150字节、SHA-256 `f701f9690d5e00c4ee9ae23fcefb8c1e96e5c1f99a5a2540985d4309a3d759fb`，原签名身份保留；ZIP/manifest/arm64 ELF/16KB ZIP对齐/签名均由脚本复验。前一批视频APK归档为`connect-arm64-before-tcp-release.apk`，未冒称当前ARM包已物理上机。[打包记录](android-packaging.md)。

所有编译与测试结束、闲置Gradle停止后，按本次Core回归日志的准确可执行文件路径清理30个非视频测试程序及对应incremental、一个旧Android测试程序和debug APK，实际释放8259MiB，剩余65.0GiB。保留当前视频反馈循环、依赖、release/native hooks/CMake/Gradle及所有无法确认模式的Flutter缓存，未按app.dill盲删；`/tmp/connect-catalog-cleanup.json`。AVD内自己推送的三个TCP测试二进制已删除，视频夹具包不存在；临时图像和原始日志继续在/tmp，未进入Git。原有五项未跟踪文件修改时间仍在10月17日，未动、未stage，未push。

## 下一段定位：解码输出到呈现

以下为实施前记录；该观测已在后续批次实现，实际结果及仍未关闭的范围见文末。

只读核查发现，现有CCodec日志中H264/HEVC为input.delay=0、output.delay=8，AV1为4。这是Codec2参数上界，不是实测积压8帧，也不能直接换算为毫秒。[AOSP定义](https://android.googlesource.com/platform/frameworks/av/+/cdb38d6e4150efa3918d61c52daca8798b3c593e/media/codec2/core/include/C2Config.h)。Rust HTTP转发每个完整AU经mux后立即写chunk，Matroska每AU一个cluster、PTS减首PTS，没有定时攒包或固定偏移；这仍不能仅凭源码排除实际socket背压。现有SPS parser没有完整VUI重排序字段证据，不能宣称重排序深度为零。

下一项研究/实施任务是补`decoded→renderer→snapshot`真实分段，按generation和同一PTS关联，耗时必须使用统一主控单调时钟。MDK官方onFrame/onVideo位于交付renderer之前；本地固定SDK C头`mdk/c/Player.h`的mdkVideoCallback为同步int返回值和frame in/out指针，不能直接把它当可异步投递Dart的普通事件。fvp0.39.1本地`lib/src/callbacks.cpp::MdkSnapshot`收到frameTime却只把像素发给Dart。接入前需验证回调线程、所有权、清理时序和既有回调是否会被替换；优先评估Rust原生回调/有界指标的跨平台路径，不增加Android平台呈现代码、不做逐帧Dart数据搬运。[MDK回调说明](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#templateclass-frame-player-onframestdfunctionintframe-inttrack-cb)。本次只读结论，不冒记新增计时已实现或已测得MediaCodec内部延迟；`buffered()`也只代表未解码packet队列。


## 原生路径分段与持续交互优化（2026-10-18 后续批次）

`bf4262a`增加可选Rust原生观测，`c058957`补真实Flutter合成面的有界新像素检查。没有新增Android播放代码或重建JAR。正常播放默认关闭观测：不注册逐帧回调、不分配指标环、不逐帧进入Dart。观测开启时按generation/token隔离，原生`onVideo`同步返回并保留原frame，最多256条PTS/主控单调时钟；snapshot仅在回调内复制限定尺寸像素，借用指针不跨回调，关闭先撤销请求，迟到回调不能访问Dart已释放的buffer。MDK C前缀按固定0.39头校验，运行版本拒绝未知主次版本；Android诊断snapshot借用固定fvp的video-output导出，正常播放不依赖该诊断接口。

relay写前/写后、MDK onVideo及native snapshot共用Rust单调时钟，按同一归一化PTS连接。MDK秒值转换允许1.1微秒误差，不跨帧模糊匹配；每次操作立即保存关联，避免等长测结束才读取已淘汰环。该测量分清HTTP写耗时、交付renderer之前的等待和snapshot可读之前的等待，不能把它称为显示面板扫描完成时间。`buffered()`仍仅表示未解码packet。[MDK回调与播放语义](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)。

固定双API36 x64 AVD、H264、maxSize640/maxFps30/2Mbps、音频关闭；每次真实按键驱动被控夹具计数变化并核对主控实际像素。下表除最后两行均开启同PTS观测、2轮共16次；冷操作保留，失败结果不删除。

| 改动 | P50 / P95（ms） | 结论 |
| --- | --- | --- |
| 原生基线 | 357 / 586 | relay写后到onVideo中位320ms，onVideo到snapshot约12ms |
| 仅AMediaCodec low_latency=1 | 355 / 581 | 无有效改善，未设默认 |
| 仅AMediaCodec surface=0 | 354 / 537 | 无有效改善，未设默认 |
| 指定c2.android.avc.decoder | 447 / 504 | 无有效改善，未设默认 |
| FFmpeg slice回退 | 194 / 450 | 有冷尾延迟，不能声称该次P95达标 |
| 仅repeat间隔33333微秒 | 318 / 405 | 有改善，仍未达门槛 |
| repeat33333加视频fps=-1 | 181 / 343 | 有效候选，仍有冷尾，扩大到80次复验 |
| 正常播放基线，4轮80次，观测关闭 | 359 / 452 | 200 / 300预算失败；四轮呈现、暂停恢复均通过 |
| 正常播放最终候选，4轮80次，观测关闭 | **186 / 241** | 相同200 / 300预算通过；四轮呈现、暂停恢复均通过 |

正常路径结果分别为`/tmp/connect-e2e/video-native-control-80-{baseline,fast}/result.json`，日志`/tmp/connect-video-native-control-80-{baseline,fast}.log`。最终最大样本352ms仍保留，P95通过不等于每次都小于300ms。基线总32秒、候选约15.5秒完成80个串行变化，因此不能直接将这两段的包量/时长视作相同输入负载带宽测试。

最终生产改动只有两处：Rust通过现有`video_codec_options=repeat-previous-frame-after:long=...`将静态重复间隔设为`ceil(1e6 / min(maxFps,30))`微秒，尊重1–29fps的低帧率选择；独立视频Player打开前设置MDK `fps=-1`，尽快呈现解码帧。该Player关闭音轨，独立音源播放器不变。[scrcpy v5.0.1 SurfaceEncoder默认值与自定义覆盖顺序](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java)、[MDK setFrameRate](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-setframeratefloat-value)。组合试验中relay写后到onVideo中位约130ms、onVideo到snapshot约12ms；不能把全部改善归因于某一个内部队列。

此处调整的是静态画面重复超时，从默认100ms缩短到约33.334ms。Android API契约是在没有新帧时重复一次，不代表固定每秒输出30帧；更早重复可能增加编解码工作，实际包量仍需测量。[MediaFormat契约](https://developer.android.com/reference/android/media/MediaFormat#KEY_REPEAT_PREVIOUS_FRAME_AFTER)。2秒静止观察基线6–15包/300–787字节，候选5–12包/280–988字节，不足以推断真实手机功耗或高动态带宽。首帧仍未改善：同4轮基线启动到可读像素997–1256ms，候选1172–1286ms；不能将持续交互收益写成冷首帧收益。

可复现正常路径门槛：沿用前述drive入口，追加以下定义，不启用TRACE_FRAMES。开启观测则追加`CONNECT_PERF_TRACE_FRAMES=true`，不要混合两种snapshot实现的统计作为同路径对照。

```sh
--dart-define=CONNECT_PERF_ROUNDS=4 \
--dart-define=CONNECT_PERF_TRANSITIONS=20 \
--dart-define=CONNECT_PERF_MAX_P50_MS=200 \
--dart-define=CONNECT_PERF_MAX_P95_MS=300 \
--dart-define=CONNECT_PERF_IDLE_MS=2000
```

一次早期80次尝试在40次后发现Flutter截图仍为VIDEO4、目标为VIDEO8，未算完整80次基线。固定SDK的integration_test Android截图先acquire ImageView再等待两帧，可能捕获上一幅合成；现在最多8次、1.5秒观察窗口重新获取，每次像素/耗时与原图全部保留，仍不匹配即失败。没有忽略陈旧画面或放宽交互门槛。最终两次80样本的四轮合成面均第一次即匹配；该重试只修测试取样，未宣称修复所有可能的产品停帧。

捕获的H264 CSD解析为Baseline、pic_order_cnt_type=2、num_reorder_frames=0/max_dec_frame_buffering=1；这是所测码流证据，不能从CCodec output.delay上界反推实际B帧数。指定c2.android.avc.decoder实测output.delay=3，AOSP软件libavc含额外显示延迟；默认AVD宿主另有CUVID初始化失败日志与软件解码路径。不同AVD版本/实现不能混为实体手机硬解，也不通过重写SPS或换JAR掩盖等待。[C2SoftAvcDec](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/android16-release/media/codec2/components/avc/C2SoftAvcDec.cpp#920)、[libavc显示延迟](https://android.googlesource.com/platform/external/libavc/+/refs/heads/android16-release/decoder/ih264d_defs.h#48)。

本批仍开放：默认1280/60/8Mbps与高动态图像吞吐、冷首帧、真实ARM硬解/功耗/热、小时级长稳、真实配对adbd切网及已有视频活动恢复、音画共同时间基、四宿主整包。TCP黑洞局部恢复证据沿用上一节，本批80次没有模拟Wi-Fi故障。


### 本批验证边界

Rust bridge17项（含9项原生观测）、真实HTTP媒体16项通过；原生snapshot回归覆盖原frame透传、行拷贝、PTS、容量/超时、关闭/迟到回调和generation隔离。relay关闭观测时不插入frameTrace空字段，开启时有界256条并核对真实mux PTS及写入时钟。最终生产改动后Core lib39 passed/2 ignored、两包all-target clippy -D warnings及cargo fmt通过，Bridge Flutter完整114项通过。严格分析发现有界截图循环缺花括号，修正后4.9秒无问题；165输入生成一致性通过，没有生成文件变化。没有将ignored或命令参数错误计作通过。

Core交叉check iOS/macOS/Windows通过；bridge Android arm64在明确NDK CC/AR后通过。直接在Linux检查其余三个bridge target仍受dart-sys所需宿主C工具链/SDK限制（Windows lib.exe及Apple SDK缺失），失败日志保留在`/tmp/connect-native-trace-check-<target>.log`，不能把Core通过写成四宿主Flutter/bridge整包通过。

最终正式RemotePage五编码约24秒通过，`/tmp/connect-e2e/video-native-final-product-five/result.json`各codec为rendered且mediaAcceptanceComplete=true；H264全屏Settings与浮动退出以及最终图案VIDEO0截图已目视。普通main构建11.6秒/安装588ms，DTD发现并连接本次CLI App，实际热重启1642ms，运行错误工具无错误；`/tmp/connect-native-main-restarted.png`设备列表空态已目视。保留启动跳帧/SurfaceSync及两条FRB旧isolate告警，不当作冷启动流畅证明。

宿主独立检查本批29个精确会话JAR路径均不存在，视频夹具APK已卸载；`/tmp/connect-native-final-remote-cleanup.json`。官方枚举JAR和协作暂停捕获JAR摘要仍分别为764eb6f7…和91606a60…，本批未修改、未重建，普通APK继续嵌入现有产物。


最终`a694b78`的arm64签名release构建63.53秒，同模式`--no-pub`复建22.59秒，两次APK摘要一致；该增量耗时高于前批4.09秒，未做额外归因或宣称打包进一步加速。当前产物`/tmp/connect-artifacts/connect-arm64-video-release.apk`，46,773,534字节、SHA-256 `c9cc21d19df2b5d5ca726ad5b182854bbb5721a10fa06de0981e171e6f5a285f`；原签名身份和包结构/16KB对齐检查通过。未在物理ARM运行。[打包记录](android-packaging.md)。

全部构建结束后停止本批闲置Gradle，删除明确debug模式中间产物/重复debug APK及一个被替代Core测试程序，共59处，实际释放1379.4MiB，空闲63.0GiB。保留release、native hooks、CMake、Gradle、当前视频测试及模式不明的Flutter hash缓存；`/tmp/connect-native-final-cleanup.json`。原有五项未跟踪文件未动、未stage，未push；任务07和完整产品目标保持开放。


## 冷启动身份校验与默认高清复验（2026-10-18 后续）

上一批640/30/2Mbps持续交互结果不覆盖默认画质。本批给真实图案入口增加可选maxSize/maxFps/bitRate，仍使用原来的默认值保留旧基准可复现；追加首帧与关键帧后工作量两个独立门槛，记录实际解码尺寸和各项预算判定，任一失败仍使整体回执失败。本次1秒完整首帧是工程排查门槛，未通过不能写成产品承诺或已验收。

本节冷启动指重新ADB连接后的新捕获/播放器，未重启AVD或清空系统缓存。默认1280/60fps/8Mbps、实际AMediaCodec、关闭诊断trace，三轮8次真实变化的基线完整跑完：实际尺寸均576×1280；首帧1210/1246/1254ms，P50/P95=185/371ms，统计未去掉冷操作。1秒首帧失败，P95也超过300ms，不能套用上一批640结果宣称高清延迟通过。`/tmp/connect-e2e/video-hd-cold-baseline-r2/result.json`和`/tmp/connect-video-hd-cold-baseline-r2.log`。

此前第一次高清尝试只完成一轮后因integration_test注册缺失失败，不是三轮基线：release准备流程过滤了开发插件，直接--no-pub切回drive沿用了该注册。应用目录执行`flutter pub get --offline`重新准备后复跑完成完整采样但性能门槛失败，不能把测试基础设施失败当成媒体性能红证据。

| 身份校验步骤（均为同配置三轮） | 首关键帧后剩余Core工作（ms） | 完整首帧（ms） |
| --- | --- | --- |
| 基线：关键帧后再读/proc并核验 | 95 / 97 / 93 | 1210 / 1246 / 1254 |
| 仅复用launcher的starttime，省重复读取 | 47 / 47 / 48 | 1235 / 1281 / 1205 |
| 再与首关键帧读取并行核验 | **0 / 1 / 0** | 1276 / 1196 / 1245 |

launcher已经为了断线解冻而读取子进程PID/starttime；现在通过有界PID:starttime回执交给Rust，严格拒绝缺失/多字段、非十进制、0/1 PID、0 starttime、溢出和非法UTF8。exec替换程序而保留进程身份，因此无需随后再次cat同一stat；后续每次signal仍检查starttime及完整JAR/SCID nice-name，不退化为数字PID。metadata已经证明app_process进入socket初始化后，才开始identity核验；与首关键帧预读用try_join本地并行，两者成功才发布listener，任一失败另一future被drop且外围取消守卫仍清理。START_APP仍先记录durable permit、提交再等待，不自动重放unknown。[execve属性](https://man7.org/linux/man-pages/man2/execve.2.html)、[/proc starttime字段](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html)。

这消除了可复现的关键帧后等待，但**目前完整首帧没有得到改善证据**：不同轮次的枚举/首编码及播放器首次输出浮动掩盖了局部收益。不得将95→0ms直接从独立轮次的总耗时相减，或将source关键帧就绪称为主控画面可见。step1/并行结果分别在`/tmp/connect-e2e/video-hd-cold-{identity,parallel}/result.json`，失败日志保留。

真实Rust→adbd→现有JAR进程回归：step1为7.59秒、并行为4.17秒，错误starttime拒绝、STOP/CONT、连接EOF后暂停进程解冻并退出通过，最后通过独立连接精确删除自己的JAR。最初默认2MiB调试测试线程stack overflow，不是产品回归通过；以RUST_MIN_STACK=8388608重跑，日志`/tmp/connect-cold-identity-real-step1-r2.log`、`/tmp/connect-cold-identity-real-parallel.log`。解析边界单元通过。独立只读review未发现新增正确性问题。

只调整repeat超时约16.667ms的额外候选，在首轮1139ms首次可读后遇到session.pause控制超时，未完成三轮，更未过1秒门槛。已恢复约33.334ms超时，不纳入生产；`/tmp/connect-e2e/video-hd-cold-repeat60/result.json`。不能只挑其首帧数字而忽略暂停失败，也不能仅凭一次失败断言所有设备会有同一根因。后续需对高负载暂停的消费者背压/ACK链路建独立回归；本地先暂停是为解决MDK静止输入确认，不能未经验证简单颠倒顺序。继续保留现有JAR及暂停扩展。


最终保留33.334ms超时并扩大到默认高清4轮80次：P50=**201ms**、P95=**248ms**，门槛仍为200/300ms，没有将201向下取整或放宽门槛。完整首帧1185/1122/1141/1234ms，1秒门槛仍失败；关键帧后开销四轮均0ms，20ms门槛通过。`startupBudgetMet=false`、`postKeyFrameBudgetMet=true`、`inputLatencyBudgetMet=false`、整体`videoPerformanceComplete=false`。四轮实际AMediaCodec、576×1280新像素、Flutter呈现、暂停恢复、输出停止确认与纹理分离、夹具卸载都完成，nativeDeleteConfirmed仍false，不能称原生资源已全部确认删除。`/tmp/connect-e2e/video-hd-cold-final-80/result.json`、`/tmp/connect-video-hd-cold-final-80.log`。该图案负载不等于高动态吞吐或60fps稳定输出验证。

`67d6fb9`提交测量入口，`657990c`提交身份校验时序。复现默认高清严格门槛时，沿用图案drive及环境变量，将定义设为：

```sh
--dart-define=CONNECT_PERF_DECODER=native \
--dart-define=CONNECT_PERF_MAX_SIZE=1280 \
--dart-define=CONNECT_PERF_MAX_FPS=60 \
--dart-define=CONNECT_PERF_BIT_RATE=8000000 \
--dart-define=CONNECT_PERF_ROUNDS=4 \
--dart-define=CONNECT_PERF_TRANSITIONS=20 \
--dart-define=CONNECT_PERF_MAX_START_MS=1000 \
--dart-define=CONNECT_PERF_MAX_POST_KEYFRAME_MS=20 \
--dart-define=CONNECT_PERF_MAX_P50_MS=200 \
--dart-define=CONNECT_PERF_MAX_P95_MS=300 \
--dart-define=CONNECT_PERF_IDLE_MS=2000
```

在release和E2E之间切换后，应先在应用目录执行`flutter pub get --offline`（依赖尚未缓存时使用正常pub get），再执行--no-pub drive；不要手改生成的注册文件。此严格命令当前预期退出非零，不能把完成80次采样等同全指标通过。

后续研究/实施保持三项：记录首包到首次onVideo/renderer的冷阶段，区分AVD软件实现与实体ARM；为高负载暂停的HTTP消费者背压与控制ACK建真实故障回归；独立固定高动态图案、持续时长和码率测量吞吐/内存/热。并行JAR上传与枚举仅列为候选，必须先验证失败/取消后无晚到上传复活文件，不因预计节省几十毫秒跳过清理所有权。保持原有完整产品目标与任务07开放。


本批最终Rust Core lib40 passed/2 ignored（10.30秒）、Core/Bridge all-target clippy -D warnings（4.47秒）及cargo fmt通过；严格Flutter分析7.1秒无问题。ignored不计真实通过；上面的真实进程测试另行显式执行。Core iOS/macOS/Windows MSVC交叉check通过，日志`/tmp/connect-cold-check-{ios,macos,windows}.log`，不代表三宿主Flutter/bridge整包或运行。

正式RemotePage五编码24秒通过，`/tmp/connect-e2e/video-cold-product-five/result.json`各codec rendered且mediaAcceptanceComplete=true；H264全屏Settings/浮动退出、高清最终VIDEO0及普通main设备列表截图已目视。普通main构建12.4秒/安装552ms，DTD实际热重启2325ms、运行错误查询无错误，日志`/tmp/connect-cold-main.log`；仍有启动SurfaceSync/跳帧和两条旧isolate投递告警，不记启动流畅通过。热重启后已detach。

宿主独立核对本批17个精确会话JAR路径均不存在，目标夹具APK已卸载（`/tmp/connect-cold-remote-cleanup.json`）。两个原有scrcpy JAR的完整摘要仍与前文一致，未改、未重建。


当前签名ARM64产物59.50秒构建、同模式复建2.40秒且摘要一致；`/tmp/connect-artifacts/connect-arm64-video-release.apk`为46,773,534字节、SHA-256 `9411b4f9ab12a20c75d18c4ad0942e93b2d8a0fa024c391a7af6ef5a672a66ae`，原签名身份与ZIP/manifest/ELF/16KB对齐检查通过。它包含`657990c`，未物理ARM上机；原c9cc21d1…产物已另存。详见[打包记录](android-packaging.md)。


最终另行显式执行既有真实应用窗口/剪贴板/关闭保留任务测试，4.37秒通过，`/tmp/connect-cold-app-window.log`；它覆盖新并行路径中的START_APP，但不是所有unknown故障/UI迁回验收。随后独立ps和目录检查未发现残留捕获进程或捕获JAR，`/tmp/connect-cold-final-target-inspection.json`。闲置Gradle已停止，清理59处明确debug/过期测试产物，实际释放1373.8MiB、剩余62.6GiB；保留release/native hooks/CMake/Gradle和当前视频测试，`/tmp/connect-cold-cleanup.json`。原先五项未跟踪文件仍未动、未stage、未push，完整目标继续active。


## 动态负载下的合作暂停与JAR重建（2026-10-18）

本批由上一批16.667ms repeat试验的暂停超时继续排查，生产repeat仍33.334ms。
给独立目标增加可选持续变色块，保留中心四位计数采样带；每次暂停后经真实输入
改变目标计数，恢复必须读到新像素。`CONNECT_PERF_PAUSE_CYCLES`默认1、可设1–50，
每次保存阶段/暂停/恢复/新像素耗时，已完成cycle也写宿主日志以保留原生崩溃前的进度。
夹具独立构建/安装/卸载，未加产品原生代码或改变被控免APK要求。

| 真实双API36 x64 AVD，H264 1280/60/8Mbps、AMediaCodec、trace关闭 | 结果 |
| --- | --- |
| 原捕获JAR、静态、2轮×10次暂停 | 20次新像素/呈现/清理通过；不能代表动态负载 |
| 原捕获JAR、动态 | 第5次暂停ACK超时；首次输入1640/1628ms |
| 原JAR加临时主控探针、动态 | 第6次暂停超时；Capture写约1.255ms后无ACK，未判定根因 |
| 仅修gate/consumeReset窗口 | 动态仍出现超时，不是完整修复 |
| 增加有界输出等待及pending退出后的第一次动态 | 主控MDK线程SIGABRT，无最终JSON，不能计通过 |
| 最终源码动态复跑＋相同APK直接复跑 | 各2轮×10次全部通过，共40次；暂停148–306ms，恢复调用至新像素410–869ms |

原JAR的确定性竞态：gate已打开，codec尚未注册时暂停入队，只能置reset；随后
consumeReset清除该位，编码器进入encode，队列中的请求无法返回gate。JVM按真实
调用顺序先红，`isResetRequested`同时检查pending队列后绿。
但实际动态仍超时，故没有止于第一个理论。超时瞬间raw输出最长写447µs、最后完成包距
超时约12ms，未发现该层背压。目标超时前约2秒的SIGQUIT栈：control-recv已读下一消息、
control-send等空队列、video在`dequeueOutputBuffer(-1)`。这支持排查依赖EOS的编码退出，
不能单凭栈断言Android永远丢EOS，或完全排除其他阶段背压。

第二个回归直接反射调用构建后的真实SurfaceEncoder.encode，codec stand-in不产EOS，
先确认正常静止输入继续等待，再在读中入队暂停；旧实现确定性失败。最终将dequeue
等待设为100000µs，完成当前完整packet及releaseOutputBuffer后检查pending请求，
允许进入原finally清理，再在gate发ACK；未提前确认，也未在普通播放中任意丢P帧。
恢复仍要求新session/config/关键帧和真实新像素。100ms只约束该次codec读等待，
不保证socket写、native stop/release或完整暂停在100ms内完成。

仅我们的捕获扩展JAR需要此次重建，SHA-256为
`b46cd074600c33802dc764df8a9e056271725cb9b51daf4a3494dfffadbbac89`；
官方v5.0.1 JAR保持`764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`。
协议128/序列/ACK语义未变。普通Flutter/Rust构建仍直接嵌入产物；不是每次打包重建Java。
独立只读review未发现packet边界、资源清理/ACK、display保留的新缺陷；指出100ms不约束
包写/native清理，以及JVM无EOS用例不覆盖正长度packet。真实压力覆盖实际packet与像素。

原始证据：`/tmp/connect-e2e/video-pause-stress-{baseline,motion,probe,fixed,stack,stack-r2,stack-r3,bounded,bounded-r2,bounded-r3}/`；
对应`/tmp/connect-video-pause-stress-<同后缀>.log`。`bounded`因崩溃没有result.json，
驱动finally仍卸载并确认夹具不存在。两个确定性红日志为
`/tmp/connect-capture-{race,eos}-red.log`，最终JVM绿为`/tmp/connect-capture-eos-green.log`；
目标栈`/tmp/connect-pause-stack-r3-0.txt`，MDK完整tombstone
`/tmp/connect-video-pause-native-tombstone.txt`。临时Rust状态探针、Dart延迟/诊断标记均移除。

**开放问题不被复跑通过覆盖**：第一次候选在主控`JNISurfaceTextu`线程SIGABRT，MDK栈
为0x17951d/0x919ec/0x1631b9（BuildId 901726b6b0358c34d504c453a084538af9c7ef27）。
同APK随后40次通过，但原生崩溃根因/复现率仍未定位，不能称整体稳定验收通过。
动态完整首帧2753–3091ms，8次输入新像素1049–1769ms，远超严格预算；本批功能压力
沿用start5000、P50/P953000ms，`videoPerformanceComplete=true`只对这些门槛成立。
没有放宽前一批严格1000/200/300ms验收或用四个输入计算可信性能分位数。
静止3秒期间实际63–74包、约1.17–1.38MB，不等于稳定60fps/8Mbps；目标自身gfx统计
332帧，中位25ms、P9557ms、7.83% jank，见`/tmp/connect-video-pause-stress-fixed-target-gfxinfo.log`。
夹具绘制/AVD负载与编码/传输/解码需继续分段，不能把所有动态延迟归咎网络。

复现：先构建独立夹具，设置既有drive要求的ADB/主控/目标/APK环境变量（见夹具README），
在apps/connect目录使用：

```sh
rtk proxy env CONNECT_E2E_VIDEO_MOTION=true \
 CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/video-pause-stress \
 flutter drive -d emulator-5554 --no-pub \
 --driver=test_driver/video_performance.dart \
 --target=integration_test/video_performance_test.dart \
 --dart-define=CONNECT_PERF_DECODER=native \
 --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
 --dart-define=CONNECT_E2E_PORT=25556 \
 --dart-define=CONNECT_PERF_MAX_SIZE=1280 \
 --dart-define=CONNECT_PERF_MAX_FPS=60 \
 --dart-define=CONNECT_PERF_BIT_RATE=8000000 \
 --dart-define=CONNECT_PERF_ROUNDS=2 \
 --dart-define=CONNECT_PERF_TRANSITIONS=2 \
 --dart-define=CONNECT_PERF_PAUSE_CYCLES=10 \
 --dart-define=CONNECT_PERF_IDLE_MS=3000
```

同一编译定义的重复测试可用`--use-application-binary=build/app/outputs/flutter-apk/app-debug.apk`
直接安装运行当前测试APK，免重编译；不要用于改变dart-define的实验。严格性能命令仍按上一节，
本批不关闭任务07或完整目标。下一批优先复现MDK动态原生崩溃，再分段动态积压/冷首帧。


本批实现分批提交：`5a6cfda`为真实压力夹具/恢复新像素与失败回执，`91ae381`为两处
合作暂停修复/JVM回归/可复现捕获JAR。最终JAR --check及JVM通过，
`/tmp/connect-pause-jar-check.log`；严格Flutter分析5.8秒无问题，
`/tmp/connect-pause-analyze.log`。正式RemotePage五编码24秒全部rendered且
mediaAcceptanceComplete=true，`/tmp/connect-e2e/video-pause-product-five/result.json`；
H264全屏Settings/浮动退出与动态最终VIDEO8实际截图已目视。真实应用窗口/剪贴板/
停止保留原任务4.25秒通过，`/tmp/connect-pause-app-window.log`，不外推所有任务迁回。


普通main实际构建10.0秒、安装567ms，DTD实际热重启2729ms、运行错误查询无错误；
`/tmp/connect-pause-main.log`、`/tmp/connect-pause-main-restarted.png`，设备列表已目视后detach。
仍保留启动SurfaceSync及两条旧isolate投递告警，不把它称为启动流畅通过。
ARM64签名release 62.74秒完成，签名/ZIP/manifest/ELF/16KB ZIP对齐通过；另直接检查
APK的libinterop_bridge.so确实嵌入当前b46cd074…完整JAR，x64 debug也单独核对。
当前`/tmp/connect-artifacts/connect-arm64-video-release.apk`为46,773,534字节，SHA-256
`5ea20787311dec169eaed3a911b3a1c88eb7139947ff83de6e2190217e1fc9cb`，未物理ARM运行。
旧9411b4…包保留为`connect-arm64-before-pause-gate-release.apk`。


同模式release热构建2.50秒、摘要一致。停止闲置Gradle，清理382处明确debug输出，
实际释放1488.5MiB、空闲62.5GiB，保留release/native hooks/Gradle/CMake和模式不明的
Flutter缓存。`/tmp/connect-pause-cleanup.json`及`/tmp/connect-pause-remote-cleanup.json`：
目标无捕获进程/JAR且夹具已卸载，自己的SIGQUIT/tombstone已复制留证后精确移除。
MDK x64崩溃二进制`/tmp/connect-pause-libmdk-x64.so`也留存，供后续符号/反汇编定位。
原五项用户未跟踪文件未修改、未stage，没有push，完整目标仍active。

## MDK截图崩溃与动态上游分段（2026-10-18）

本批不改生产播放参数，也不重建任何JAR。官方JAR仍为`764eb6f7…`，捕获扩展仍为
`b46cd074…`。普通Flutter／Rust构建直接嵌入受控产物；修改被控服务端源码／补丁／
固定工具链或明确复现构建时才重建，详见[构建规则](../../servers/scrcpy/README.md)。

### 同栈崩溃已重复，尚未修复

先用原配置连续3轮各20次动态暂停／恢复，60次均完成，暂停149–343ms、恢复到新像素
467–850ms；完整首帧3096／2634／3030ms。原始`video-native-crash-baseline/result.json`
仍是宽功能门槛，不是严格1000／200／300ms通过。

为缩小触发范围，测试增加`CONNECT_PERF_SNAPSHOT_STRESS`（0–10,000，默认关闭）：
在输入／暂停前连续读取64×64实际像素，逐次等完成并断言计数器，每100次输出进度。
连续动态但计数不变时2,000次串行截图全部通过，34.475秒；随后输入、暂停和实际
Flutter合成画面核对也完成，`/tmp/connect-e2e/video-snapshot-stress/result.json`。
这只否定“高频串行截图必然失败”，不证明截图线程安全或崩溃已消失。

对旧完整tombstone与精确x64二进制反汇编，SHA-256仍为
`72e5f6370f98a3a09755004a0c6be1c01d688c79d7b1f0a5cce3a2e7d49c8ad3`，
BuildId为`901726b6b0358c34d504c453a084538af9c7ef27`：

- `.eh_frame`确认`VideoRenderer::redraw`实际范围`0x1612f2..0x16309b`。
  它从与`VideoRenderer::snapshot`共用的96字节队列项取出完成回调，
  在`0x162ae8`创建独立线程，入口`0x1630d4`。
- 线程读取参数`+0x30`的回调，空值分支到`0x1631b5`，经`0x919db`加载
  `bad_function_call was thrown in -fno-exceptions mode`，最终`0x179519`主动abort。
  实际回溯返回地址为`0x17951d / 0x919ec / 0x1631b9`。
- 真正主线程在Looper poll；崩溃新线程继承`JNISurfaceTextu`名称。不能从线程名
  直接归因GL或AVD。普通addr2line的最近导出`SubtitleDecoder`／`cryptograph`也
  不是这些地址的真实函数归属。其他线程无release／destroy正在执行的证据。

随后只将动态帧率上限60改30、保留1280／8Mbps并打开已有同PTS trace的对照，
进程20秒时再次SIGABRT，相同三地址和BuildId。旧实验使用fvp公开snapshot，本次
使用Rust C snapshot；两条路径都传入有效完成回调，均进入MDK renderer快照队列。
因此已指向两者共用的MDK内部空回调路径，仍未证明空值的产生机制、ABI、队列
竞争或生命周期中的具体原因。没有通过修改本机pub缓存、换全局软解或删除像素
断言掩盖问题；目前没有可靠修复。30fps该次没有最终JSON，不能计算性能结论。

新增现场`/tmp/connect-video-dynamic-trace-30-tombstone.txt`为625,837字节，核对
pid3986／tid4462与BuildId；日志`/tmp/connect-video-dynamic-trace-30.log`，宿主
`cleanup.json`确认夹具卸载。旧现场与原二进制继续保留在临时目录。
[MDK snapshot契约](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-snapshotsnapshotrequest-request-snapshotcallback-cb-void-vo_opaque--nullptr)
说明请求会调度renderer重绘，完成回调在独立线程执行；本批二进制证据比线程名称更具体，
不把已有Changelog中的其他snapshot修复当成本次缺陷已解决。

### 动态延迟主要出现在relay之前

60fps动态、1280／8Mbps、实际576×1280、实际AMediaCodec，两轮16次实际新计数器
全部完成同PTS关联，`/tmp/connect-e2e/video-dynamic-trace/result.json`：

| 同一帧的主控单调时钟段 | 中位 | 范围 |
| --- | ---: | ---: |
| 发送操作前→该新像素帧到relay mux入口 | 1002.024ms | 808.981–1187.199ms |
| relay HTTP写入 | 0.051ms | 0.032–11.939ms |
| relay写后→onVideo交付renderer之前 | 262.107ms | 174.815–368.868ms |
| onVideo→snapshot可读 | 35.260ms | 14.432–213.592ms |

输入到新像素P50／P95为1290／1434ms，完整首帧3007／2411ms。逐段中位不能直接
相加还原总量分位数；快照读回／轮询与真实视频推进重叠，也不能从总量减掉累计
snapshot耗时来宣称“净延迟”。本对照开启trace会切换snapshot实现，不能冒充正常
关闭观测路径的直接优化对照。最明确的下一步是上游采集／编码／ADB分段，非继续
只调MDK缓冲：Rust逐包转发没有主动按时长囤帧，但这不排除内核、adbd或codec队列。
当前证据不能把上述1秒具体归因于网络、目标绘制或编码。两条JAR保持不变。

30fps相同测试APK原样复跑（`--use-application-binary`，未重编译或换参数）完成两轮
16次同PTS关联，`/tmp/connect-e2e/video-dynamic-trace-30-r2/result.json`，P50／P95为
1335／1613ms；输入→relay中位1035.756ms、HTTP写0.053ms、relay→onVideo220.213ms、
onVideo→snapshot30.700ms。没有明显改善上游主要等待，不更改默认帧率。首次同栈
崩溃继续计失败；后一次通过不能证明30fps修复了稳定性。下一项为独立测试夹具记录
目标实际按键／绘制单调时钟，并保留原始源PTS，核对各时钟定义后再关联；不直接相减
两个设备的时钟，也不为此增加主控Android媒体代码。

本批同PTS对照复现沿用上节完整环境与drive入口，设置
`CONNECT_PERF_TRACE_FRAMES=true`、`CONNECT_PERF_ROUNDS=2`、
`CONNECT_PERF_TRANSITIONS=8`、`CONNECT_PERF_PAUSE_CYCLES=1`、
`CONNECT_PERF_MAX_SIZE=1280`、`CONNECT_PERF_BIT_RATE=8000000`，仅以
`CONNECT_PERF_MAX_FPS=60`／`30`分别编译；动态夹具环境变量始终为true。

`c65105e`提交串行截图隔离测试及说明。严格Flutter分析5.1秒无问题，
`/tmp/connect-native-crash-analyze.log`；普通main构建10.5秒／安装607ms，实际DTD
热重载成功（131ms，0库变化），已detach。设备首页截图
`/tmp/connect-native-crash-main.png`及最终动态计数2截图已目视。启动仍有SurfaceSync
与跳帧告警，不能据此称首帧／流畅度达标。生产播放源码／JAR均未改，未重复构建相同
release，也不把旧release说成包含新测试入口。

停止闲置Gradle后清理382处明确debug输出，实际释放1488.5MiB、空闲61.8GiB，
`/tmp/connect-native-crash-cleanup.json`。保留release、native hooks、Gradle／CMake
缓存、未知模式的Flutter缓存与临时崩溃证据。新tombstone已复制核对后精确移除设备
对应文件；目标检查无本批捕获进程，夹具不存在。原五项用户未跟踪文件未修改。

## 目标输入绘制与源PTS观测（2026-10-18）

`aa9330e`在已有默认关闭、最多256条的relay trace中补原始`sourcePtsUs`，独立于
减去首帧origin后的`ptsUs`；不改变码流、播放参数或关闭观测时的逐帧路径。实际
HTTP回归先看到Null／5003000不等，再补实现，16项HTTP测试全部通过，
`/tmp/connect-source-pts-{red,green}.log`。本批未重建任何scrcpy JAR。

`e99d4b6`给独立实验夹具增加可选`CONNECT_E2E_VIDEO_TIMELINE=true`：每次新计数
记录真实按键处理、首次onDraw开始／结束、公开KeyEvent事件毫秒值。每轮运行ID
隔离，递增sequence跨轮关联，而不只按会回绕的4 bit计数查找；驱动同时匹配暂停
期间输入，缺失／重复／计数不符／同进程负间隔均使观测验收失败。默认不开启日志，
不是产品额外安装APK或主控原生视频实现。每次完整输入还打印有界阶段回执
`VIDEO_INPUT_SAMPLE`，使原生崩溃后仍可追溯已完成样本。

### 时钟范围

同目标`System.nanoTime()`在AOSP基于MONOTONIC，与uptime时钟一致；
KeyEvent的公开`getEventTime()`只有毫秒精度，scrcpy注入时以uptimeMillis赋值。
因此事件时间至应用处理的差值只反映注入后的目标分发等待，不包含主控至注入的
传输。onDraw开始／结束只给出该回调CPU执行区间，不等于GPU／合成／屏幕呈现。
[Android SystemClock](https://developer.android.com/reference/android/os/SystemClock)、
[KeyEvent](https://developer.android.com/reference/android/view/KeyEvent#getEventTime())。

scrcpy的Streamer直接发送`BufferInfo.presentationTimeUs`，这是输入帧派生时间戳，
不是`dequeueOutputBuffer`完成时刻。[BufferInfo契约](https://developer.android.com/reference/android/media/MediaCodec.BufferInfo#presentationTimeUs)、
[固定scrcpy Streamer](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/device/Streamer.java)。
AOSP虚拟显示HWC路径在queueBuffer时使用systemTime，GPU路径可透传输入时间戳；
普通Surface默认使用MONOTONIC。GL路径、厂商、重定基准与速度调整仍须单独核对，
不能把任意SurfaceTexture PTS都保证为nanoTime。
[VirtualDisplaySurface](https://android.googlesource.com/platform/frameworks/native/+/bfb51bb9a282ae2c1c48d777679890bbb038a287/services/surfaceflinger/DisplayHardware/VirtualDisplaySurface.cpp#250)、
[SurfaceTexture契约](https://developer.android.com/reference/android/graphics/SurfaceTexture#getTimestamp())。

本次匹配同一目标的画面计数，源PTS与目标nano域吻合；报告“绘制结束至所观察源帧
PTS间隔”，不标为纯合成或编码耗时。一次轮询不保证捕获首个包含新计数的源帧，
重复上一帧还可递增PTS，因此这是所观察新像素帧的间隔。主控relay单调时钟与目标
PTS保留各自域，未直接相减。[GraphicBufferSource时间戳与重复帧](https://android.googlesource.com/platform/frameworks/av/+/d37e465f355b37efd6f0fac99a42991e5f88a3cb/media/module/bqhelper/GraphicBufferSource.cpp)。

### 双AVD动态对照

相同1280／8Mbps、实际576×1280、AMediaCodec、2轮各8个输入／1次暂停，动态夹具
开启；60fps原始结果`/tmp/connect-e2e/video-source-clock/result.json`，18个实际输入
与绘制均唯一匹配，包括计数回绕。15fps结果`video-source-clock-15/result.json`
由新增驱动自动完成同样的18项校验，`targetTimelineComplete=true`。

| 指标 | 请求60fps | 请求15fps实验 |
| --- | ---: | ---: |
| 报告输入→新像素P50／P95 | 1308／1707ms | 566／911ms |
| 输入→relay中位 | 1012.366ms | 227.061ms |
| relay HTTP写中位 | 0.059ms | 0.069ms |
| relay→onVideo中位 | 222.241ms | 316.613ms |
| onVideo→snapshot中位 | 33.401ms | 32.368ms |
| 目标按键处理→onDraw开始中位 | 0.902ms | 1.003ms |
| onDraw回调CPU区间中位 | 0.393ms | 0.419ms |
| 绘制结束→所观察源PTS间隔中位 | 67.483ms | 83.174ms |
| 目标注入事件→应用处理中位 | 39.902ms | 36.053ms |
| 完整首像素两轮 | 2821／2567ms | 2914／2802ms |

码流配置仅把maxFps改15；现有重复超时也随其派生为66.667ms，60fps配置为33.334ms。
两轮对照之间还补了计时结束后的逐输入进度日志，尚未用最终同版夹具重采60fps；
15fps是后续负载实验线索，不是严格单独修改编码器内部帧率的归因证明。实际转发约17.54／17.95包每秒与
15.17／15.16包每秒，这不是保证对应唯一图像的呈现fps。支持负载／排队方向，
没有排除控制注入之前的延迟，也尚不区分目标编码完成与ADB传输。默认画质保持，
不能把降帧实验当所有设备的产品优化或1000／200／300ms已通过。两次未崩溃也
不能关闭已有MDK空snapshot回调崩溃。下一项补默认关闭的Rust ADB读取完成／
raw写出／relay同PTS时钟，先缩小主控传输等待，无需重建服务端JAR。

复现沿用上节drive环境／定义，加`CONNECT_E2E_VIDEO_TIMELINE=true`；第一次为
`CONNECT_PERF_MAX_FPS=60`，第二次为15。原日志分别
`/tmp/connect-video-source-clock.log`与`/tmp/connect-video-source-clock-15.log`，
目标原始记录单独保存在对应目录的`target-timeline.json`。临时汇总
`/tmp/connect-source-clock-segments.json`不是独立原始证据，最终原始JSON优先。

### 观测失败保留原始故障

只读代码复核发现时间线采集失败会在finally抛出并覆盖主流程错误。实际临时ADB
代理注入“首次目标截图失败＋logcat失败”：修复前错误变为timeline失败，修复后
保留`Cannot capture target-initial`，`cleanup.json`仍记录timelineError及卸载／
不存在确认。记录`/tmp/connect-source-clock-fault-{red,green}.log`，目录对应
`/tmp/connect-e2e/video-source-clock-fault-{red,green}/`。这些退出码是预期失败，
判定通过依据是原始错误、采集错误与最终卸载三个事实，不把非零退出本身称绿。

另只让logcat失败，复用同一15fps测试APK完成实际16次输入：最终
`/tmp/connect-e2e/video-source-clock-report-fault/result.json`先保存完整原始视频
报告（videoPerformanceComplete=true），再以targetTimelineComplete=false报观测
失败，卸载仍确认。该次不计为时间线或性能通过。采集异常现在只记录，成功回调
落盘后再检查完整性；崩溃时可以保存空／部分目标记录而不凭空补数据。修复复核通过。

最终严格Flutter分析8.1秒无问题，Core all-target clippy -D warnings 4.81秒与
cargo fmt通过；原始日志`/tmp/connect-source-clock-final-analyze.log`及
`/tmp/connect-source-clock-clippy.log`。两次完整动态画面与故障代理均使用真实目标，
没有将lab APK作为产品依赖。既有签名ARM64包未更新，新增诊断字段只在本批实际
构建的x64测试APK运行验证，正常关闭trace的播放逻辑没有变化。

普通main首次构建18.6秒后安装失败：原主控QEMU进程174462已退出，设备不在线。
没有把这次失败当应用安装或热重载通过。恢复原AVD数据；一次误选host GPU的启动
因无显示环境失败，已终止该次启动并恢复此前SwiftShader后端。新QEMU进程276588、
工具session57057启动，5554的sys.boot_completed=1，普通main热构建6.7秒、安装979ms，
实际DTD热重载123ms成功，错误查询无Dart运行错误，截图
`/tmp/connect-source-clock-main.png`与15fps最终计数2画面已目视。仍有SurfaceSync及
跳帧原生告警，不视为启动流畅度或完整视频首帧已通过。性能数据均在原进程退出前
取得；恢复后只作普通App验收，未来性能配对测试必须重新固定环境。

临时故障代理与三个marker已删除，保留日志／JSON收据；
`/tmp/connect-source-clock-fault-cleanup.json`。停止Gradle并清理382处明确debug输出，
实际释放1488.5MiB、空闲61.4GiB，`/tmp/connect-source-clock-cleanup.json`；保留
release、native hooks、Gradle／CMake及未知模式的Flutter缓存。被控无本批捕获
进程，夹具已卸载，原五项用户未跟踪文件未改。完整目标与任务07继续开放。

## ADB消费、raw转发与解码后端对照（2026-10-18）

新增`session.start(traceFrames:true)`诊断，正常不开启。`run_video`记录原始source PTS、
首字节已交给scrcpy消费后／完整包读完／raw写入开始及完成的主控Rust单调微秒值。
最多256条，配置包不占条目；captureSegment随新尺寸标记递增，初始预缓冲首帧不计，
不等于renderer generation。关闭时不采逐帧时钟、不建立记录数组或新增逐帧写锁，
仍有一次启动读锁、flags解析与条件判断。没有增加Dart逐包传输、原生日志或改码流。

真实内存ADB路由→`run_video`→认证raw TCP回归，分开的第一字节WRTE与后续WRTE之间
保留20ms等待；修复前因无收据超时，修复后验证时序、原始转发字节、分段、配置包排除、
256条上限及正常不开启。`cargo test -p interop-core --lib video_transport_`共4项通过，
10.30秒，含已有截断期限／静止／取消测试。日志
`/tmp/connect-transport-trace-{red,green}.log`及`/tmp/connect-transport-regression.log`。

**边界：**[Frame::read](../../crates/adb/src/protocol.rs)收齐整个WRTE payload才返回，
reader路由后[AdbStream::read](../../crates/adb/src/client.rs)才交付其中字节。
`adbStreamReadUs`只是交出首字节之后的scrcpy拼包跨度；同WRTE先前接收／排队不在其中，
跨WRTE时后续包等待才可能可见。此字段不能称完整网络接收时间。最初两次收据名为
`adbReadUs`，最终代码改名明确边界，值的定义未变。下一接缝应测ADB头收齐后的payload
读取以及路由至消费，仍只能称Transport等待，不能自动归因物理无线。

### 同环境后端对照

这三次运行都在恢复后同一主控QEMU276588／原目标进程，不能与恢复前数据混为配对。
动态夹具、目标时间线、1280／60fps／8Mbps请求、实际576×1280、2轮各8次输入及1次暂停，
保持1000ms首帧、200／300ms输入P50／P95预算。仅将测试decoder从native换software，
实际成功事件分别为AMediaCodec与FFmpeg；默认产品后端未变。

| 指标 | AMediaCodec | FFmpeg slice对照 |
| --- | ---: | ---: |
| 报告P50／P95 | 1310／1699ms | 1098／1549ms |
| 完整首像素 | 3636／2814ms | 2102／1848ms |
| 输入→relay中位 | 1064.190ms | 1067.421ms |
| relay→onVideo中位 | 233.155ms | 4.025ms |
| onVideo→snapshot中位 | 26.678ms | 20.813ms |
| AdbStream消费跨度中位／最大 | 0.012／42.355ms | 0.014／10.793ms |
| raw写中位／最大 | 0.049／0.073ms | 0.053／0.269ms |
| 完整包读完→relay中位／最大 | 0.123／0.210ms | 0.139／0.380ms |

每次16项新像素同PTS匹配、18项目标输入绘制关联、2次暂停恢复、实际Flutter截图和
纹理分离均完成，夹具自动卸载；`frameCorrelationComplete`／`targetTimelineComplete`
为true，但`videoPerformanceComplete=false`、startup／input预算false。驱动退出1是
明确保留的严格失败，不能把功能循环完成称性能通过。没有在本批复现MDK崩溃，也没有
关闭既有崩溃项。解码端存在独立开销，但替换解码器未消除主要上游等待；尚不确定是
编码输出、adbd／Transport、控制注入前或其它排队。

原始结果`/tmp/connect-e2e/video-transport-{stage,software}/result.json`、对应
`/tmp/connect-video-transport-{stage,software}.log`。复现沿用前节drive入口，设置
`CONNECT_E2E_VIDEO_MOTION=true CONNECT_E2E_VIDEO_TIMELINE=true`及
`CONNECT_PERF_TRACE_FRAMES=true`、MAX_SIZE1280、MAX_FPS60、BIT_RATE8000000、
ROUNDS2、TRANSITIONS8、PAUSE_CYCLES1、MAX_START_MS1000、MAX_P50_MS200、MAX_P95_MS300，
只将`CONNECT_PERF_DECODER=native`换为`software`；原始JSON优先于临时汇总。

只读复核指出raw写完成的future恢复前下游已可能解码。最终Dart在计时结束后最多1秒
重读期望PTS的收据；仅缺失重试，重复仍失败，不用假值或负数截零补齐时序。
严格Flutter分析4.8秒无问题，Core all-target clippy -D warnings 5.32秒与fmt通过，
`/tmp/connect-transport-final-analyze.log`、`/tmp/connect-transport-clippy.log`。
正常生产播放参数、官方及捕获扩展JAR均未改／重建；旧ARM64 release未更新，新增诊断
只由本批x64测试APK实际运行。服务端重建条件见[构建规则](../../servers/scrcpy/README.md)。

最终有界等待／字段命名版再跑同样AMediaCodec配置2轮，16次同PTS与18项目标时间线
完整匹配，两次暂停、Flutter计数9／2呈现与卸载确认完成；P50／P95=1259／1968ms，
首帧3256／2862ms，原严格预算仍失败，未省略最大样本。完整包读完→relay中位0.132ms，
raw写0.051ms，输入→relay1025.218ms，relay→onVideo270.623ms，与前述段落方向一致。
`/tmp/connect-e2e/video-transport-final/result.json`与
`/tmp/connect-video-transport-final.log`；这是最终代码功能／观测复跑，不是性能绿。
前两组最终计数2实图已目视；集成测试使用专用播放器页面，不冒充正式远控页全流程。

代码提交`b2c2993`。普通main热构建9.2秒、安装620ms；DTD的IDE实例未发现CLI App，
VM Service改用WebSocket连接后实际热重载241ms成功、Dart运行错误查询无错误，已detach。
最初误用HTTP URI的工具连接被拒绝，不算热重载通过；后续成功有实际回执。设备首页
`/tmp/connect-transport-main.png`与三组最终计数2图片已目视；仍有SurfaceSync及
1421ms启动帧原生告警，不把无Dart异常当启动流畅度通过。

停止闲置Gradle后清理382处明确debug输出，释放1488.6MiB、空闲61.0GiB，收据
`/tmp/connect-transport-cleanup.json`；保留release、native hooks、Gradle／CMake、
未知Flutter模式缓存和性能／崩溃原始证据。被控无本批捕获进程且夹具不存在，原五项
用户未跟踪文件未动。此次没有改默认画质、后端或scrcpy JAR，完整目标与任务07继续开放。

## 逐WRTE接收与消费实测（2026-10-18）

独立ADB库增加[可选接收观测](../../crates/adb/README.md)，调用方提供单调微秒clock。
`Frame::read_observed`在24字节头校验／payload分配后、payload读取前后计时；路由将
metadata随原有字节队列交给AdbStream。首次消费记时，后续部分读复用同一sequence及
首次消费时间。Core仅在`traceFrames`开启时订阅，已有256条raw trace中补
`firstAdbRead`／`lastAdbRead`，不增加Dart逐包桥接、日志或JAR行为。

订阅以token标识，路由与消费各复核一次，换clock／停用清空当前收据并丢弃旧metadata，
不丢字节；在途payload仍可能完成一次旧clock调用，然后丢弃结果。Route移除／CLSE／
连接清理自动释放订阅。正常无订阅的新WRTE不采时钟或多取路由锁，保留一次原子检查、
可选metadata字段及每连接订阅计数；没有声称完全零开销。收据只保留当前包，不累积历史。

真实tokio byte transport→ADB reader／路由→AdbStream回归：header及一字节payload
先到，剩余延迟30ms，完整包就绪后再等20ms消费；先前stub在期望收据处真实失败，补
实现后通过。验证读取消、未整包前不交字节、部分消费不提前ACK、计时／字节一致、关闭
不采时钟，并补换clock期间在途旧包及停用前已排队包的隔离。最初一次服务参数类型编译
错误已修正，不当作症状红。日志`/tmp/connect-adb-read-trace-{red,green}.log`。

完整ADB52 passed／13 ignored、Core视频传输4 passed（10.30秒）、两crate all-target
clippy -D warnings（7.97秒）及fmt通过，日志`/tmp/connect-adb-read-{full,core-regression,clippy,fmt}.log`。
只读review未发现确定问题；保留“多个scrcpy包可能共用一个WRTE收据”的语义边界。

### 实际Android路径

沿用上节同一双API36 x64 AVD、动态夹具与目标时间线、H264 1280／60fps／8Mbps请求、
实际576×1280及AMediaCodec，2轮各8次输入／1次暂停。原有Dart测试自动保留新增raw
字段，无需修改测试播放器或生成FRB。16项同PTS关联、18项目标输入／绘制、2次暂停
恢复、Flutter实际计数9／2呈现和卸载确认完整；最终计数2图已目视。严格1000／200／300ms
预算失败，驱动退出1，未当作性能绿。

| 指标 | 中位 | 最大 |
| --- | ---: | ---: |
| 20个去重首末WRTE的payload读 | 0.256ms | 9.252ms |
| WRTE路由→首次消费 | 0.014ms | 0.034ms |
| 首WRTE读完→scrcpy首字节返回 | 0.019ms | 0.038ms |
| 首WRTE开始读payload→末WRTE读完 | 0.310ms | 14.335ms |
| raw写 | 0.047ms | 0.107ms |
| 完整scrcpy包读完→relay | 0.125ms | 3.221ms |
| 输入→relay | 1002.445ms | 1297.105ms |
| relay→onVideo | 256.443ms | 405.122ms |

16项中4项跨两个WRTE，12项首末sequence相同；这20项是当前新像素样本的端点包，
不是整场所有ADB包分位数。payload开始计时前的头等待、TLS／kernel先前缓存、目标
编码／adbd积压均未计入，起点不能解释为第一个网络字节到达。首次消费与首字节返回
相差的是主控小段处理，多个scrcpy包共享WRTE时也不能称为每帧独立的队列停留。

报告输入到新像素P50／P95=1268／1584ms、完整首像素3138／2840ms。实际同域小区间
不支持“该一秒在已测payload读或消费队列中”，但没有排除第一包头前的ADB／网络等待。
下一项用明确误差界关联源PTS／目标时钟与主控收包，进一步区分输出前后，不凭这组
数据断言是编码器。仍不关闭既有MDK snapshot空回调崩溃。

原始JSON `/tmp/connect-e2e/video-adb-packet/result.json`、目标时间线及Flutter图片在
同目录，日志`/tmp/connect-video-adb-packet.log`，临时派生汇总
`/tmp/connect-adb-packet-segments.json`不是独立原始证据。复现命令与上节native完全相同，
只把capture目录改为video-adb-packet；两个JAR摘要保持764eb6f…／b46cd074…，均未重建。
构建70.4秒含本批Rust改动与恢复debug输出，仍有SDK XML工具版本告警；不是稳定热构建
时间，也不与此前增量秒数混比。

并行只读研究确认当前[AOSP Burst](../research/adb-host-and-connectivity.md#24-burst-mode复核与当前实现差距2026-10-18)
仍为实验性默认关闭；当前经典流控有明确兼容范围。完整credit支持是独立工作，可能
提高吞吐也可能放大排队，尚无本项目A/B收益，未只加feature或修改默认窗口。

代码提交`2f54b91`。修改后Core交叉`cargo check -p interop-core --target`分别覆盖
`aarch64-apple-ios`（3.94秒）、`aarch64-apple-darwin`（3.86秒）、
`x86_64-pc-windows-msvc`（3.87秒）通过，日志
`/tmp/connect-adb-read-<target>.log`。这是Rust库编译检查，不是三个宿主的最终链接／
Flutter整包或运行证据。Android本批由实际x64测试APK验证，既有签名ARM64 release
未更新，不声称包含新诊断。

普通main重新构建9.1秒、安装592ms，经真实VM WebSocket连接热重载134ms，运行错误
查询无Dart错误，已detach；首页`/tmp/connect-adb-read-main.png`及最终动态计数2画面
已目视。仍有SurfaceSync／跳33帧／1432ms原生启动帧告警，不视为启动性能通过。
停止Gradle后清理382处明确debug输出，释放1488.7MiB、空闲60.5GiB，收据
`/tmp/connect-adb-read-cleanup.json`；保留release、native hooks、Gradle／CMake、未知
Flutter模式缓存、原始性能／崩溃证据。被控无本批捕获进程，夹具已卸载；原五项用户
未跟踪文件未纳入提交。任务07与完整目标继续开放。


## 时钟括号与Surface输入实验（2026-10-18）

这批是诊断和可撤回配置实验，没有默认帧率／后端变更，也没有重建scrcpy JAR。
只重建独立目标测试夹具APK，以采集本次所需的双时钟读数；普通产品仍不向被控端安装APK。

### 时钟定义、边界与拒绝条件

`session.clock.probe`仅允许已有逐帧观测会话。Core用与WRTE／relay同一进程本地
`monotonic_micros()`在ADB exec前、stdout完整EOF后分别采样a／b，固定执行
`cat /proc/uptime`。包含启动shell、调度、传输和EOF全部开销，不减“shell开销”，
不假设往返对称。整个操作限2秒、128字节，取消沿既有会话token；严格整数解析拒绝
截断、错误文本、额外字段和溢出。它不是系统时钟同步服务，默认播放不执行这些命令。

Linux `/proc/uptime`取BOOTTIME并截断到百分之一秒，因此读值u表示[u,u+10000)µs。
[Linux v6.12实现](https://github.com/torvalds/linux/blob/v6.12/fs/proc/uptime.c)。
目标夹具在input、onDraw起止分别读取elapsedRealtimeNanos／nanoTime／elapsedRealtimeNanos，
形成真实调用顺序括号；不把onDraw记录或源PTS当作编码输出完成。
[elapsedRealtimeNanos](https://developer.android.com/reference/android/os/SystemClock#elapsedRealtimeNanos())
包含深度休眠，[nanoTime](https://developer.android.com/reference/java/lang/System#nanoTime())
不包含；[Linux时钟区别](https://www.kernel.org/doc/html/latest/core-api/timekeeping.html)
也不允许把BOOTTIME和MONOTONIC直接等同。AVD暂停／快照恢复不是已证明的Android休眠等价物。

本轮以θ=target BOOTTIME−controller monotonic、δ=target BOOTTIME−target nanoTime
为常数的条件模型求交。整数微秒截断余量先加入每个输入区间，再相交：

```text
θ_i ∈ [u − b − 1, u + 10000 − a + 1]
δ_i ∈ [bootBefore − nano − 1, bootAfter − nano + 1]
到达时刻R与目标绘制结束D的差：
[R − D + θlo − δhi − 1, R − D + θhi − δlo + 1]
```

每轮输入前、输入循环后各三次probe，计时主体排除probe开销。探针会延长输入前的
流水线预热，不能将不同测量代码前后的变化当严格单变量性能收益。
缺失记录、回绕后sequence／counter不匹配、input→draw逆序、各括号逆序、交集为空、
实际payload／完整包时间不在前后探针之间，均拒绝本轮分析并保存原始数据。
夹具与主控进程重启、已知休眠／VM暂停／快照恢复／连接或捕获代次变化须另起采样轮；
**非空交集不证明未暂停、时钟速率相同或没有未观察到的跳变**。没有引入未经证明的ppm界。

源PTS另加“与目标nanoTime同原点、同速率”的假设才可代入同一式子。
[BufferInfo契约](https://developer.android.com/reference/android/media/MediaCodec.BufferInfo#presentationTimeUs)
只承诺对应输入时间标签，[pinned Streamer](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/device/Streamer.java)
只是原样发送它。额外PTS假设不相容时保留draw边界、单列ptsCompatible=false，
不把它伪装成所有校准失效，也不把正PTS年龄解释成纯编码耗时。

### 实际双AVD与单变量配置

同一持续运行双API36 x64 AVD，默认请求1280／60fps／8Mbps，实际576×1280，
H264、AMediaCodec实际打开、音频关闭、持续动态夹具。每组两轮16次输入及2次暂停后输入；
新计数、source PTS关联、18项目标时间线、真实Flutter截图、暂停恢复、停止纹理分离和
夹具卸载完整。两组均驱动退出1，严格1000／200／300ms门槛失败，未提高门槛。

| 指标 | 现有默认 | 仅Surface输入15fps |
| --- | --- | --- |
| 输入→snapshot P50／P95 | 1301／1701ms | 540／1567ms |
| 完整首帧（两轮） | 3042／2606ms | 2685／2634ms |
| 绘制结束→首payload，中位界，第1轮 | 961.535–1013.451ms | 563.377–625.829ms |
| 同上，第2轮 | 957.489–1009.239ms | 161.409–202.680ms |
| 校准区间宽，第1／2轮 | 51.916／51.750ms | 62.452／41.271ms |
| 观测trace正PTS间隔中位，第1／2轮 | 47.510／47.078ms | 65.052／65.834ms |

PTS间隔来自保留的有界trace，包含循环前启动／预热部分，不是60fps面板呈现证明，
也不宣称15fps是重复帧在内的严格总输出上限。两组相同请求配置与解码尺寸；实际目标
编码器仍是平台默认选择，没有取得固定厂商编码器的物理设备对照。
默认输入→relay等待仍约1秒，主控首末WRTE已观测payload读取／消费／raw输出短，
因此把主要范围收窄到目标绘制后、主控首payload读取前；无法单独区分Surface队列、
编码计算／输出、服务端socket、adbd及更早网络缓冲。源PTS条件中位年龄两轮约
891–943ms／888–940ms，不据此认定编码耗时。

候选只在Rust启动参数的现有同一个逗号列表追加：

```text
max_fps=60
video_codec_options=repeat-previous-frame-after:long=33334,max-fps-to-encoder:float=15
```

[固定SurfaceEncoder](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java)
先设置max_fps，再应用codec options，因此覆盖生效；追加第二个video_codec_options
会替换整份列表，不能这么做。[固定Options](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/Options.java)。
该版本已设priority=0和latency=1；重复加相同值不算新优化。
[Android Surface入口限帧契约](https://developer.android.com/reference/android/media/MediaFormat#KEY_MAX_FPS_TO_ENCODER)
和[AOSP GraphicBufferSource](https://android.googlesource.com/platform/frameworks/av/+/d37e465f355b37efd6f0fac99a42991e5f88a3cb/media/module/bqhelper/GraphicBufferSource.cpp)
说明过量源帧在入口丢弃。它也会降低后续socket／adbd压力；改善支持负载／排队方向，
不唯一定位编码器。第1轮仍有1567ms长尾，不能只挑第2轮结果；暂停两轮各一次通过
也不关闭已存在的MDK snapshot崩溃。候选已精确撤回，不加入默认产品。

原始结果／实际截图／cleanup在`/tmp/connect-e2e/video-clock-{brackets,input15}/`，日志
`/tmp/connect-video-clock-{brackets,input15}.log`。默认暂停373／176ms、恢复新像素524／638ms；
候选204／227ms、612／574ms。两个组各18项目标事件完整。默认最终VIDEO2纹理已目视。

复现使用上一节drive命令，加`CONNECT_E2E_VIDEO_TIMELINE=true`、
`--dart-define=CONNECT_PERF_TRACE_FRAMES=true --dart-define=CONNECT_PERF_TRACE_CLOCK=true`；
rounds=2、transitions=8、pauseCycles=1、maxSize1280／maxFps60／bitRate8000000，
decoder=native。候选需临时添加上面唯一codec option，跑完还原；正常工程不保留该覆盖。

Core实际exec/EOF括号与错误响应回归先红后绿，两项通过；Dart区间计算先红后绿，
另用未来PTS而有效draw括号证明额外假设不覆盖主结论。最终检查及清理另见本批收尾。
下一项应在Surface／编码输出／adbd边界区分积压，验证兼顾静态响应与动态负载的策略；
不在已证明短的主控raw／relay段继续增加缓冲参数。


本批收尾：代码提交`424c40a`。Core真实协议括号2项通过（0.04秒），日志
`/tmp/connect-clock-core-final.log`；错误文本／截断／数值溢出均拒绝。Dart区间3项通过，
`/tmp/connect-clock-bounds-green.log`；未来PTS不覆盖有效draw结论的真实红日志
`/tmp/connect-clock-pts-assumption-red.log`先得到Expected true／Actual false。
严格分析4.2秒无问题，`/tmp/connect-clock-bounds-analyze.log`；Core all-target clippy
1.90秒及fmt通过，`/tmp/connect-clock-{clippy,fmt}-final.log`。最终helper重新分析两组
原始报告，各16项draw区间／PTS相容检查通过，没有将原报告的性能false改成true。
iOS／macOS／Windows Rust核心check分别0.97／0.94／0.96秒，
`/tmp/connect-clock-{ios,macos,windows}.log`，不代表三宿主Flutter整包链接或运行。

普通main在撤回临时15fps覆盖后重新构建55.7秒／安装601ms，实际VM热重载124ms成功、
运行错误查询无Dart错误，随后detach；设备首页`/tmp/connect-clock-main.png`及两组
VIDEO2实际纹理已目视。保留SurfaceSync、跳36帧与1441ms原生启动帧告警，未称启动达标。
本批未生成新的签名ARM包或物理ARM运行证据。两JAR摘要与既有记录一致，完全未重建。
停止Gradle后删除380处精确debug目录及debug APK／sha1，释放1488.8MiB，空闲60.3GiB；
保留release／native hooks／Gradle／CMake缓存与原始性能／崩溃资料。
`/tmp/connect-clock-cleanup.json`记录删除范围；被控独立核验无本批捕获进程，夹具包不存在。
原五项用户未跟踪文件未动，未push。下一轮继续性能／首帧／稳定性，完整目标仍active。

## 可选ADB Burst与宿主排空诊断（2026-10-18）

本批不修改、重建两个scrcpy JAR，也不新增Android原生媒体实现。Rust ADB的
`ConnectOptions::burst_mode`默认false，主动宣告`delayed_ack`并与对端相交后才启用。
外部连接器原入口始终经典格式，新入口须明确传入本地主动宣告结果；实际模式由
`Client::burst_mode()`及Core连接／诊断的`adbBurstActive`返回。
Core `settings.adbBurstMode`只影响新连接，已有连接不静默改变线协议。

实现signed i32增量／i64累计send credit、正信用可整包超额、部分读取返还信用，
取消／关闭清除不再有效的返还并保留已收到尾包。每流64KiB接收窗口，额外保留一个
max_payload和保守元数据／读缓冲；全连接128MiB预留，路由和消费者均释放才归还。
零字节WRTE不占队列；普通writer仍64帧＋一个in-flight，拒绝反向OPEN另有128个
空CLSE控制槽，满时有界等待、取消可中断，不无限spawn或关闭整连接。

真实协议回归先红后绿：初始CNXN缺feature、反向关闭尾包被丢、writer满且CLSE后
tail read等待无效credit三个接缝均复现后修复。消费停读超过5秒仍完整收到尾包，
不再以固定5秒超时截断。两轮独立只读review先发现反向拒绝全连接取消与尾包截断，
修复后复核两项关闭、未新增有证据问题；静态review不冒充动态测试。
完整ADB 72通过／13忽略（含19个Burst wire测试），Core 153通过／49忽略，
`/tmp/connect-burst-{adb,core}.log`；workspace all-target `-D warnings` clippy及fmt通过，
`/tmp/connect-burst-{clippy,fmt}.log`。被忽略设备项不是实际运行通过。
这些测试包括本地TCP反向桥及Rust STLS/TLS协议端，不覆盖实际USB／无线TLS adbd长稳。

### 先隔离解码／呈现，再观察目标写出

临时`/tmp/connect-raw-drain.py`直接连接宿主127.0.0.1:25556，用经典ADB逐WRTE立即ACK，
排空相同H264 1280／60／8Mbps、repeat33334µs码流12秒，无解码／Flutter／新像素断言。
只用于故障隔离，非产品依赖或性能验收替代。系统adb仅负责独立实验夹具安装、已有
JAR推送、时钟采样及清理。每次唯一nice-name／远端JAR和fixture均由该次任务精确清理。
初次pm path不存在返回1导致脚本在安装前退出，改为仅接受空输出的不存在结果后重跑，
没有把该次失败计为测量。

| 宿主诊断 | 媒体包数／后半统计数 | PTS→首payload中位条件界 | 头→整包中位 |
| --- | --- | --- | --- |
| 快速排空 | 406／203 | 461.589–494.773ms | 0.012ms |
| 排空＋目标video TID strace | 417／209 | 513.819–553.180ms | 0.958ms |

前后各三次`/proc/uptime`保留10ms量化／全往返区间；额外假设目标BOOTTIME−nanoTime
接近相邻夹具观测的0、运行中无休眠／VM暂停／跳变。表中是源buffer PTS年龄条件界，
没有新像素匹配，不能替代Android输入到实际呈现；全量包均保留，后半统计仅排除启动。
原始`/tmp/connect-raw-drain-{15ba2e4dfadb,3e20eb2a8cb8}/result.json`。

第二次只strace自己捕获服务的video TID11799，857个write、417个媒体头均按原始PTS
匹配；syscall中位25µs、最大9505µs，没有100ms以上调用。
`/tmp/connect-raw-drain-3e20eb2a8cb8/{video.strace,trace-summary.json}`。
**只排除这次宿主排空时的长socket write阻塞**，没有观测Android呈现路径相同结论。
仍数百毫秒的源年龄支持继续区分Surface采集／GPU fence／编码输入及组件排队，
不能叫作纯编码CPU时间或断言16个input slots已实际积满。
固定AOSP时间轴、slot与fence源码、后续首帧候选及MDK官方修复边界见
[本轮研究](../research/scrcpy-first-frame-performance.md#aosp-surface-时间轴输入槽与无重建观测2026-10-18)。

### Android同配置经典／Burst对照

同一主控emulator-5554与目标emulator-5556、API36 x64／SwiftShader、H264请求
1280／60／8Mbps、实际576×1280、AMediaCodec、动态夹具、逐帧trace及时钟括号。
没有重启AVD、重建夹具或改变编码参数；未固定实际目标编码器名称，只请求同一平台默认。
先经典再Burst，各两轮8次正常输入＋1次暂停期间输入；两个连接回执分别false／true。
Core独立数据目录每组显式写setting，避免前一次持久状态污染。

| 指标 | 经典 | Burst |
| --- | --- | --- |
| 输入到解码像素 P50／P95 | 1224／1493ms | 1324／1670ms |
| 完整首像素，第1／2轮 | 3014／2876ms | 2521／2768ms |
| Core关键帧后额外工作 | 0／0ms | 0／0ms |
| 绘制结束→首payload，第1轮中位界 | 998.464–1055.279ms | 932.954–971.210ms |
| 同上，第2轮 | 893.405–960.046ms | 1022.362–1082.362ms |
| 校准区间宽，第1／2轮 | 56.815／66.641ms | 38.256／60.000ms |
| 输入→relay中位 | 995.621ms | 1045.510ms |
| relay→onVideo中位 | 217.038ms | 223.456ms |
| onVideo→snapshot中位 | 33.194ms | 33.319ms |
| 完整scrcpy包读取跨度中位 | 0.015ms | 0.013ms |
| raw写中位 | 0.049ms | 0.046ms |
| 暂停确认，第1／2轮 | 264／272ms | 262／286ms |
| resume→新像素，第1／2轮 | 459／575ms | 579／544ms |

所有16项正常输入及额外2项暂停输入均匹配目标时间线，clockBounds.complete／
frameCorrelationComplete／targetTimelineComplete均true。画面新像素、两轮实际
Flutter呈现和停止／纹理分离通过；两个最终VIDEO2截图已目视。每组第二轮首次Flutter
截图仍旧VIDEO9，驱动沿已有有界重试取得VIDEO2，首张失败证据保留，不当成无延迟呈现。
nativeDeleteConfirmed仍false；夹具uninstalled／absent均true。

**两组严格命令均退出1**：首帧1000ms、P50 200ms、P95 300ms门槛没有放宽，
startupBudgetMet／inputLatencyBudgetMet／videoPerformanceComplete均false。
这批没有消除主要上游等待；不能依据两轮首帧数值就宣称可靠加速，也不把更高P95解释成
已证明所有Burst设备更慢。Burst保留为显式可选协议能力、默认关闭；真实无线TLS、USB、
多流公平／资源、断网恢复和小时级稳定性仍未通过此对照。

复现命令（同上一节`transportDrive`环境与已构建独立fixture，候选仅改false为true和
输出目录／日志名；不在计时期间并行编译其他任务）：

```sh
CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
CONNECT_E2E_TARGET=emulator-5556 CONNECT_E2E_DEVICE=emulator-5554 \
CONNECT_E2E_VIDEO_FIXTURE=/tmp/connect-video-fixture/video-fixture.apk \
CONNECT_E2E_VIDEO_MOTION=true CONNECT_E2E_VIDEO_TIMELINE=true \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/video-burst-classic \
flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/video_performance.dart --target=integration_test/video_performance_test.dart \
  --dart-define=CONNECT_PERF_DECODER=native --dart-define=CONNECT_PERF_TRACE_FRAMES=true \
  --dart-define=CONNECT_PERF_TRACE_CLOCK=true --dart-define=CONNECT_PERF_ADB_BURST=false \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 --dart-define=CONNECT_E2E_PORT=25556 \
  --dart-define=CONNECT_PERF_MAX_SIZE=1280 --dart-define=CONNECT_PERF_MAX_FPS=60 \
  --dart-define=CONNECT_PERF_BIT_RATE=8000000 --dart-define=CONNECT_PERF_ROUNDS=2 \
  --dart-define=CONNECT_PERF_TRANSITIONS=8 --dart-define=CONNECT_PERF_PAUSE_CYCLES=1 \
  --dart-define=CONNECT_PERF_MAX_START_MS=1000 --dart-define=CONNECT_PERF_MAX_P50_MS=200 \
  --dart-define=CONNECT_PERF_MAX_P95_MS=300
```

原始`/tmp/connect-e2e/video-burst-{classic,credit}/result.json`、各自target-timeline／cleanup
和实际截图；日志`/tmp/connect-video-burst-{classic,credit}.log`。
经典APK构建74.1秒、安装1741ms；两组仅改变Dart define，第二组使用同一Rust本地产物。
严格Flutter分析4.2秒无问题（实施时终端回执）；Core iOS／macOS／Windows交叉check
3.13／3.11／3.10秒通过，`/tmp/connect-burst-{ios,macos,windows}.log`，不等于三宿主Flutter整包。

下一项优先区分Surface输入fence／采集及编码组件排队，并比较静态、动态负载；
首帧另核实重复codec创建的实际代价，证实需要服务端变更才重建JAR。
MDK安全帧读回候选单独验证，不以取消像素断言绕过崩溃。

代码提交`b391cac`。恢复普通main首次构建8.6秒／安装590ms后，原主控QEMU276588
退出、管理会话exit143，日志仅有正常关闭／等待kill流程及既有GL告警，触发源未确定；
不冒称该次热重载成功或归因产品崩溃。`/tmp/connect-burst-main.log`。
确认进程不存在后，恢复同一interop-controller原数据、原SwiftShader后端，
`-no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect`，17.905秒启动。
`/tmp/connect-burst-controller-recovery.log`。**所有A/B性能样本均在恢复前采集**，
恢复后未补混比样本，也未因为重启覆盖失败结果。

随后普通main构建6.5秒／安装1134ms，实际VM热重载124ms成功、运行错误查询无Dart错误；
`/tmp/connect-burst-main-r2.log`、设备首页`/tmp/connect-burst-main.png`已目视，随后detach。
SurfaceSync／跳37帧／1504ms启动帧告警仍在，不称应用启动性能通过。
本批未生成新的签名ARM包，未物理ARM运行；两个JAR摘要不变、完全未重建。
被控独立复核没有本批捕获／strace进程，实际包`dev.scrcpyconnect.videofixture`不存在，
`/tmp/connect-burst-target-inspection.json`。首次独立包名检查误写了下划线，已按manifest
修正并重测；驱动自身两组卸载回执始终使用正确包名。

停止Gradle后清理436处明确debug目录／debug APK及本批非视频Core测试可执行文件／.d，
实际释放5740.1MiB、空闲54.9GiB；`/tmp/connect-burst-cleanup.json`。
保留release／native hooks／Gradle／CMake／Rust依赖与incremental、当前视频／ADB／
网络稳定性测试程序及原始性能／崩溃证据，没有使用全仓clean。
原五项用户未跟踪文件未动、未stage、未push；完整目标继续active。

## 目标CCodec完成边界与源年龄（2026-10-18）

为区分上一批宿主快速排空仍约半秒的年龄，本批在同目标emulator-5556、既有捕获JAR、
H264 1280／60／8Mbps／repeat33334µs动态夹具下，用目标自带Perfetto采8秒
gfx／video／hal／sched／sync，16MiB ring。仅实验collector与独立fixture，不增加产品
root或APK要求。临时raw-drain脚本在codec头后启动`perfetto -D -t 8s -b 16mb`，
继续排空12秒；采集完精确pull并删除自己的远端trace，关闭连接、删除自己的JAR和卸载
fixture。非Android呈现测量，Perfetto开销也保留在样本，不与无观测基线混称性能收益。

原始`/tmp/connect-raw-drain-fbf1db6ec385/`含result.json、capture.perfetto-trace与
codec-work-verified.json；`/tmp/connect-capture-perfetto.log`。466个媒体包全部保留，
后半233个的条件PTS→宿主首header中位界515.579–562.307ms，header→整包中位11µs。
官方工具v58.2-add693d8b／RPC14，下载helper内置校验摘要的预编译产物，
没有添加应用依赖。[官方分析工具](https://perfetto.dev/docs/analysis/trace-processor)。

实际trace在该唯一捕获进程14802上给出303个
`CCodecBufferChannel::onWorkDone(c2.android.avc.encoder#252@ts=...)`，全部与原始
收到的媒体PTS精确匹配，无重复／匹配缺失，trace data-loss为0。303项是8秒trace内
已捕获回调的匹配集合，原始466包包含trace时间窗外媒体，不能据此证明全部源帧完整。
由此确认实际编码器名称；
另行官方JAR枚举仅有该软件AVC及其OMX别名，`/tmp/connect-capture-encoders.txt`。
并未把AVD系统二进制与固定AOSP源码逐字节认定相同。

| 303项实际同PTS关联 | 结果 |
| --- | --- |
| 源buffer PTS→CCodec workDone，全体中位 | 299.213ms |
| 同上，固定最后1/3的101项中位 | 590.659ms |
| workDone→宿主首header，最后1/3中位条件界 | −5.496至41.228ms |
| C2Node单次fence wait，310项平均／最大 | 0.117／7.405ms |
| C2Node queue调用，310项平均／最大 | 0.991／11.187ms |
| video dequeueOutputBuffer，303项平均／最大 | 23.023／78.678ms |

source→workDone使用目标Perfetto的BOOTTIME事件时刻和source MONOTONIC PTS，按
同trace完整clock snapshots的BOOT−MONO中位−0.132µs换算；各snapshot差范围
−0.191至−0.052µs。**相继clock读取不是严格同时采样或正式误差括号**，报告明确保留
源PTS同MONOTONIC及本轮连续运行假设。逐项PTS相等也不能单独证明该假设。
workDone→宿主header另沿用raw receipt的完整往返与10ms量化时钟区间，负下界来自
校准不确定性，不解释为实际负耗时。初段因启动collector未立即消费而有host额外等待，
全部原始匹配保留，后段统计不是剔除慢样本来过性能门禁。

主要年龄在本次CCodec完成回调处理前已经存在；该边界包含采集、Surface／组件队列、
编码计算、IPC和回调调度，不能叫纯编码CPU。单次C2Node fence／queue没有数百毫秒
阻塞，但没有证明所有上游队列占用或唯一根因，也不能外推Android实际呈现路径。
这改变下一项排查优先级：继续看输入与组件在途工作，避免重复盲调ADB／MDK缓冲。
没有降低60fps默认或重建JAR。

可复跑分析器筛唯一nice-name进程，拒绝缺钟／offset变化超过1ms、trace丢失、重复PTS
和采集区间内没有收到的帧；额外区间外事件单独计数。时钟与数据完整性三项校验通过，
`/tmp/connect-codec-trace-tests.log`；对本次真实回执删除一项中间媒体帧，实际拒绝
`CCodec event inside capture has no matching received frame`，没有生成假完整结果。

```sh
python3 tool/e2e/video_fixture/analyze_codec_trace.py \
  --trace-processor /tmp/connect-trace-processor \
  --receipt /tmp/connect-raw-drain-fbf1db6ec385/result.json \
  --trace /tmp/connect-raw-drain-fbf1db6ec385/capture.perfetto-trace \
  --output /tmp/connect-raw-drain-fbf1db6ec385/codec-work-verified.json
```

软件编码器参数的独立一手核查排除了无效complexity快速档、将通用mapper当组件实现、
将CBR叫低延迟等假设。[固定源码与边界](../research/scrcpy-first-frame-performance.md#软件avc可调参数边界2026-10-18)。


## 冷启动探测并行与默认栈修复（2026-10-18）

主屏启动的只读电源查询与真实编码器枚举改为join，并等待两者完成后按原电源错误优先级
处理；仍验证真实编码器列表，不在不兼容时提交应用启动。独立应用启动不新增电源查询。
编码器探测持有最多4项的全局许可后启动有主人的任务，调用方取消时仍执行原有清理；
各ADB操作有既有截止时间。进程退出／runtime shutdown不在此保证内，Sync失败也不
代表远端SEND已经完成。因此捕获JAR上传仍在验证后顺序执行，没有冒险并行远端写入。

真实wire gate先在旧顺序实现上因无法越过电源门控而红，最终覆盖：门控期间完整内置
JAR SEND/DATA/DONE与枚举、休眠拒绝、真实编码器不兼容拒绝、调用方取消后清理、
电源拒绝仍等待失败探测清理。没有把同一门控红误写成每个清理缺陷都独立复现。

同双AVD、静态真实像素夹具、Classic、H2641280/60/8Mbps（实际576×1280），
关闭帧跟踪及clock/timeline，HEAD与候选分别4次新连接：

| 指标 | HEAD | 并行候选（栈修复前） |
| --- | --- | --- |
| validatedMs四轮 | 408/414/390/358 | 281/281/273/327 |
| validatedMs中位 | 399ms | 281ms |
| Core启动中位 | 758.5ms | 648ms |
| 完整首像素四轮 | 1604/1174/1226/1263ms | 1158/1032/1123/1071ms |
| 完整首像素中位 | 1244.5ms | 1097ms |
| 正常输入P50/P95 | 229/467ms | 217/398ms |

每组16次正常及4次暂停后的新像素、Flutter呈现、停止纹理分离和fixture卸载完成；
两组**均因严格首帧／输入预算失败而exit1**。输入差异不归因为仅冷阶段的优化，静态
结果也不与此前动态场景混比。nativeDeleteConfirmed仍false，MDK既有截图崩溃未关闭。
原始`/tmp/connect-e2e/video-prepare-{baseline,candidate}/result.json`，日志
`/tmp/connect-video-prepare-{baseline,candidate}.log`，两组最终截图均已目视。

补验发现宿主默认2MiB线程栈的真实应用窗口测试SIGABRT；HEAD同一精确测试也红，
不是探测job新引入。GDB显示启动handshake状态在入口嵌套async frame重复内联，
叠加命令poll栈后溢出。仅在生产start_session→start_session_with_settings边界
Box::pin，仍在原task中await，入口Future由40512B降到160B。未加大线程栈，
未改测试调用方。尺寸回归红绿及默认栈真实Settings窗口／剪贴板／停止保留任务测试
通过；尺寸断言本身不声称测得poll栈上限。日志`/tmp/connect-prepare-app-{head-baseline,
red-repro,box-session}.log`及`/tmp/connect-prepare-session-frame-{red,green}.log`。
最终Core lib48通过／2真机忽略，all-target严格clippy通过，分别
`/tmp/connect-prepare-stack-{lib-green,clippy}.log`。独立只读review无需修复问题。

最终栈修复后同配置再跑4轮：validatedMs=378/366/271/294（中位330ms），
Core总阶段783/723/675/649ms（中位699ms），完整首像素1247/1198/1166/1074ms
（中位1182ms）。P50/P95=190/310ms；首帧与输入P95仍超1000/300ms门槛，
驱动exit1，`videoPerformanceComplete=false`。16次正常新像素、4次暂停／恢复、
Flutter呈现计数5/10/15/4、停止纹理分离及卸载均完成，最终截图已目视，
nativeDeleteConfirmed仍false。结果波动意味着不能把此前约148ms改善写成稳定保证。
本次启动误用了无效输出环境变量，驱动按默认路径写入，结束后完整移至
`/tmp/connect-e2e/video-prepare-final/`保存，不影响运行参数或测量；日志
`/tmp/connect-video-prepare-final.log`。没有重跑挑好样本或放宽门槛。

Core iOS/macOS/Windows交叉check分别1.86/1.89/2.09秒通过，fmt通过；
`/tmp/connect-prepare-{ios,macos,windows,fmt}.log`，不等于三宿主Flutter整包。
普通main恢复后VM热重载127ms成功、无Dart运行错误，设备首页截图已目视并detach；
`/tmp/connect-prepare-main.{log,png}`。日志仍有跳35帧与1380ms启动帧告警，
不宣称普通应用启动已通过性能要求。
停止Gradle，清理436项精确debug输出及本批非视频测试执行文件／.d，释放5730.4MiB，
空闲52.3GiB；`/tmp/connect-prepare-cleanup.json`。保留release/profile、native hooks、
Gradle/CMake、Rust依赖与incremental、视频／ADB／网络／会话回归程序及原始证据。
两个既有JAR的SHA256复核与基线相同，本批完全未重建。五项用户未跟踪文件未改未stage。
代码`c121a51`，离线分析及校验`8201485`；完整目标继续active。

远端独立检查`/tmp/connect-prepare-target-inspection.json`确认无本批捕获进程／fixture。
发现3项官方encoder探测JAR：其中mtime1792281852/1870的两项与HEAD崩溃/GDB
时段吻合且摘要为官方SERVER，按这项时间关联推断精确删除；日志未打印UUID，
不把归属写成直接证明。较早mtime1792272590的一项没有归属证据，保留。
`/tmp/connect-prepare-remote-cleanup.json`。有主探测清理不承诺进程SIGABRT后仍执行。


## 读帧候选否定与真实网络恢复（2026-10-18）

本轮原路径动态1280/60/8Mbps、Classic、AMediaCodec、trace开启，2轮各200次
串行64×64截图及10次暂停：400次截图、8次正常新像素、20次暂停恢复、同PTS关联
和Flutter合成计数14/12全部完成，本次没有崩溃。首帧3146/2766ms，输入P50/P95
1360/1478ms，严格1000/200/300门槛失败，exit1；不能覆盖既有两次同栈MDK崩溃。
`/tmp/connect-e2e/video-readback-baseline/result.json`、
`/tmp/connect-video-readback-baseline.log`。

固定头及官方文档核查支持一个临时next-frame转换实验：同步onVideo中只在有单次
请求时to(C RGBA=9)，核对尺寸/格式/data/stride并复制限定像素，delete转换句柄，
原借用frame保持不变、return0，不调用renderer snapshot，也不切换Surface/软解。
真实AVD首帧转换返回有效尺寸，但64×64四点均[0,0,0,255]，独立计数器期望0实际
为null，测试立即失败，不能把有buffer／更短首次返回当成成功。
`/tmp/connect-e2e/video-frame-conversion/result.json`、
`/tmp/connect-video-frame-conversion.log`。该次失败不能证明所有Surface配置永远不能
转换，但足以拒绝当前候选。它尚未到Flutter合成面检查，不声称原renderer仍正确。
候选完整补丁仅存`/tmp/connect-frame-conversion-candidate.patch`，三个修改源码按原
字节恢复并git diff逐一核对为0；未提交实验代码、DEBUG或新ABI，默认播放参数和
两个JAR不变。研究边界见[固定MDK帧转换](../research/scrcpy-first-frame-performance.md#mdk帧转换读回的可行边界2026-10-18)。

随后转向真实视频断网恢复，避免沿一条未验证读帧路线继续叠设置。新host driver在
127.0.0.1:25557透明代理到既有25556→真实adbd，双向Socket.addStream保持背压；
仅关闭本测试唯一活动ADB连接两端，不解析/保存ADB字节，不杀adbd或改全局网络。
独立静态图案fixture仍只用于实验，产品被控端无需额外APK。完整App通过生产
router/controller/shared Player打开显式主屏；driver有ready/cut/ack、accept编号及
时刻、结果和所有权清理，缺证据即失败。不能将此TCP EOF故障叫物理Wi-Fi切换。

首个运行遗漏RemoteLaunchIntent停在路由保护页，属于夹具错误，不当产品红。修正
后的`video-recovery-red-r2`实际从合成面识别图案0，切断socket1后1.237秒新accept，
设备offline→connecting→connected，但30秒内无新视频会话，任务失败、完整清理。
证实设备自动重连与视频自动恢复是两个不同门槛。首修复候选
`video-recovery-green`又因旧SessionView向已结束输出发pause产生未处理RequestFailure
而红，不能计通过；据此补本地已结束绑定撤销，而非忽略整个E2E异常。

生产修复保留已观看主屏的短时恢复意图；设备autoReconnect的offline→connected后，
只在当前可见前台、状态已核验且用户未停止时重建主屏，分配新sessionId并重新验证
首帧。widget.existingSession不被当成可复活身份，原工具initialAction不重放。
独立应用/unknown启动仍走核验，不能再次START_APP。明确session.stop、设备断开/
忘记及activities.stop两个相关入口在等待回执前同步撤销意图；恢复list前后检查
可见性，已提交结果迟到时清理精确新ID，不绑定回界面。已结束SessionView只撤销
本地owner与排队权限，不发送无效pause，也不误删同ID successor。

新widget最初主屏/retained两项红；background测试自身在暂停期间dispose后恢复
造成Ref错误，修正测试清理顺序，不当产品修复。只读review另4项问题中，旧输出
清理已由真实E2E复现；补5条精准回归实际红后绿：清理、停止前/后提交、后台跨await
与成功reconcile后再断线。最终相关52项通过，完整App275项46秒通过，
`/tmp/connect-remote-recovery-final-unit.log`、`/tmp/connect-recovery-app-suite.log`。

首个最终运行`video-recovery-final`已3.028秒恢复新session并完成合成图案0→1，
但测试把App根组件先卸载再调清理API，Bridge已关闭，整条exit1；该次不算通过。
修正夹具先清理设备/偏好再卸载根组件，并把complete移至清理之后，生产实现不变。
随后`video-recovery-verified`完整17秒、exit0：恢复3.965秒，新sessionId、真实
mdk.snapshot首帧、合成图案[0,0,1]、停止2秒无新活动、两次socket接受与一次切断、
fixture卸载/缺席、Settings恢复、代理结束全部确认。
`/tmp/connect-e2e/video-recovery-verified/{result,proxy-events,cleanup}.json`，
`/tmp/connect-video-recovery-verified.log`，最终全屏VIDEO1及浮动退出截图已目视。
这是EOF断线+重新捕获并重新解码，不是保留原sessionId或任意应用任务自动重放。
静态恢复时间不替代严格动态输入/冷首帧预算。

同版第二次`video-recovery-verified-r2`亦17秒、exit0，恢复3831ms，合成[0,0,1]，
新session/2次accept/1次cut/停止/夹具缺席/Settings及代理清理全部确认。
`/tmp/connect-e2e/video-recovery-verified-r2/`和同名日志。最终App全量275通过、
相关52项通过，严格分析无问题；只读复核修复后无新可证问题。全部命令与失败原件
保留，不能把这些成功覆盖先前MDK崩溃或严格性能失败。

普通main已恢复，实际VM热重载148ms、无Dart运行错误，首页截图已目视后detach。
`/tmp/connect-recovery-main.{log,png}`；仍有跳34帧、SurfaceSync1000ms和1522ms
启动帧告警，不称普通启动流畅已达标。最终fixture两文件严格分析与格式检查通过。
Gradle停止后精确清理382项debug目录/APK，释放1489.4MiB，空闲51.6GiB；
`/tmp/connect-recovery-cleanup.json`。保留host Flutter测试native asset、native hooks、
release/profile、Gradle/CMake、Rust依赖/incremental及原始证据，避免下一轮全量重编。
目标独立PID/NAME检查无捕获进程，fixture缺席；按本批所有已存回执sessionId查验
未发现残留capture JAR，没有扩大删除旧文件。
`/tmp/connect-recovery-{target-inspection,remote-cleanup}.json`。
两个JAR摘要与基线完全相同，未重建。五项用户未跟踪文件未改未stage，完整目标active。

代码`39f62ca`、真实E2E和使用说明`9c42aff`；未push。下一项继续动态上游采集/编码
排队与MDK安全读帧，独立应用任务接续及物理无线切换须另取实际证据。
