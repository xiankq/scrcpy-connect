# 入编码前 buffer 驻留与可控边界

2026-10-18。针对当前高动态延迟继续分段。本次重新分析已有目标追踪并检查固定
一手源码，没有改变生产参数或重建JAR；随后补采当前默认入口trace如下。

## 已有实际追踪的新证据

输入为`/tmp/connect-raw-drain-fbf1db6ec385/capture.perfetto-trace`，SHA-256
`1b0c76da1b5f11074fe6b2794bab8d070a2001f0231f4bc757c80f00c7fcf5c5`。
该记录对应先前隔离的H264 1280／60／8Mbps、实际576×1280快速排空实验；原始
PTS／CCodec关联及假设见[目标完成边界](../implementation/video-performance.md#目标ccodec完成边界与源年龄2026-10-18)。
它不是最新普通Driver／异步解码的再次测量，不能将下列数值当生产收益。

后台只读分析后，根代理独立复跑slot查询，确认trace data-loss为0，唯一进程
`interop.rawdrain.fbf1db6ec385`（pid14802）。保存SQL、完整事件、完整生命周期及
摘要到`/tmp/connect-source-slot-analysis.json`：

| slot事件统计 | 结果 |
| --- | --- |
| acquire／release | 309／303 |
| 完整acquire→release对 | 293 |
| 同时acquired数量范围 | 10–16 |
| 最后墙钟1/3同时持有16个的时间占比 | 99.913% |
| 后段完整持有周期中位 | 583.259ms |
| 后段完整持有范围 | 503.514–678.189ms |

slot首次事件若是release，推断它在trace开始前已经acquired；这些没有已知起点的
周期不计入完整持有时长。所有后续事件须满足不重复acquire、没有无来源release。
末段按slot事件的墙钟跨度最后1/3切分，占用按相邻事件间隔加权，不能与旧文档按
样本数量最后1/3的590.659ms混成相同集合。查询如下：

```sql
SELECT s.ts, s.name, par.name op
FROM slice s
JOIN slice par ON par.id=s.parent_id
JOIN thread_track tt ON tt.id=s.track_id
JOIN thread t ON t.utid=tt.utid
JOIN process p ON p.upid=t.upid
WHERE p.name='interop.rawdrain.fbf1db6ec385'
  AND s.name GLOB 'GraphicBufferSource: *'
  AND par.name IN ('acquireBuffer','releaseBuffer','queueBuffer','dequeueBuffer')
ORDER BY s.ts
```

使用既有官方`/tmp/connect-trace-processor query <trace> '<SQL>'`离线执行，无设备
操作。slot acquired数是BufferQueue consumer持有数，不是精确Codec2 work队列长度，
也不是所有Surface／应用帧数量。本次根代理没有复跑后台代理的HIDL/map顺序关联，
因此这里只用已独立复核的slot结果支持下一动作。

## 为什么普通codec参数不足以控制它

固定Android16源码的因果链如下；源码不等于已证明AVD二进制逐字相同：

- [MediaFormat.java](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/media/java/android/media/MediaFormat.java#1787)
  中`num-slots`是codec输出信息，应用设置会被忽略；`max-input-size`是输入字节大小。
  不能凭这些参数名宣称降低了输入在途数量。
- [CCodec.cpp](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/CCodec.cpp#288)
  从wrapper取`nBufferCountActual`，
  [C2OMXNode.cpp](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/C2OMXNode.cpp#88)
  转到`getInputBufferParams`。
- [C2NodeImpl.cpp](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/C2NodeImpl.cpp#224)
  在当前尺寸路径给出16；超过4096×2340才走另一计数分支。
  [GraphicBufferSource.cpp](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/module/bqhelper/GraphicBufferSource.cpp#1170)
  将其用于consumer的`setMaxAcquiredBufferCount()`。只减少producer缓冲数不能撤销
  consumer已经取得的16帧。

## 下一项实验与重建条件

当前入口验证已取得，见下节。输入驻留仍在，可继续受控候选；没有据此宣称全部
延迟都来自输入槽，也没有跳过实际解码／窗口验证。

若当前仍成立，可在scrcpy已有`OpenGLRunner`接缝做隔离候选：保留最新尚未提交的
源帧，限制1–2帧实际入编码，按真实输出PTS归还许可。不能按任意输出包数归还，
CONFIG／EOS／重复帧需区分；没有后续frameAvailable时，唯一静态终帧仍须被提交。
暂停／停止不得阻塞GL handler等待许可，旋转和Surface重建要撤销旧代待提交工作。
一帧输入不保证所有encoder都会立即输出，需先限定并验证候选codec。

固定scrcpy v5.0.1源码中，`ScreenCapture`无filter时直接将encoder Surface交给显示，
`OpenGLRunner`当前对frameAvailable直接render，`SurfaceEncoder`处理实际编码输出；
仓库版本及受控来源见[捕获服务说明](../../servers/scrcpy/README.md)。
这种方案改变被控端实际执行的采集／提交逻辑，必须构建有独立摘要的候选JAR，
不能只改`.build`或把已有产物重新打包冒充修复。应先支持独立候选输出，保留当前
两份产物不变。用户“不无故重建”的要求不排除确有服务端源码变化时的必要构建。

候选先验证动态→唯一终值→完全静止、静态冷启、暂停恢复、旋转和停止清理，再做
同1280／60／8Mbps请求的普通Driver A/B/A及实际窗口。只有输入年龄下降且终帧、
生命周期、实际输出和严格预算均有证据，才考虑落入生产；降低默认画质或增加AVD
资源不算该修复。真实ARM硬编、热／功耗和无线吞吐仍须单独验收。

## 当前默认入口复核

普通Driver、默认AMediaCodec async=1、H2641280／60／8Mbps、实际576×1280，两端
2vCPU AVD。一次8秒／32MB的gfx／video／hal／sched／sync追踪，实际完整进程名为
`interop.scrcpy:1c2a1e04:/data/local/tmp/interop-scrcpy-f397fede-9e83-4b75-8b3d-5c2d9c06d565.jar`，
pid4886。原件 `/tmp/connect-e2e/current-source-slots-r3/capture.perfetto-trace`，
SHA-256 `1debad089e480b0c26f30024910eb58b76440573af1a7ce96271ff241039b0e3`。

严格分析器保存全部事件与周期到同目录`capture-slots.json`：data-loss0、精确进程唯一，
735事件、87 acquire／87 release、71完整周期；末墙钟1/3有99.951971%时间同时持有
16个，后段28个完整周期中位1318.763ms、范围1079.972–1470.559ms。18个被观察到的
slot编号不等于同时在途18个。已有推断规则不变，未闭合生命周期不人为补时长。

同次真实输入8次P50／P95=1929／2405ms、首像素2349ms，10张实际窗口计数吻合；
暂停恢复／停止／App与fixture清理完成。诊断期限15秒、硬窗口3秒和性能门槛均保留，
整体exit1、videoPerformanceComplete=false。trace有观测开销，不是无追踪性能A/B。
首次运行完成8次输入1859／2090ms但外围trace定位失败，第二次一次性入口未重启被
setup拒绝，原件均保留，不以第三次覆盖前两次。Android ps NAME只展示路径末尾，
因此实际按精确会话JAR定位PID，再从/proc读取完整nice-name，不猜测PID或匹配截断值。

```sh
rtk proxy python3 -B tool/e2e/video_fixture/analyze_capture_slots.py \
  --trace-processor /tmp/connect-trace-processor \
  --trace /tmp/connect-e2e/current-source-slots-r3/capture.perfetto-trace \
  --process-name 'interop.scrcpy:1c2a1e04:/data/local/tmp/interop-scrcpy-f397fede-9e83-4b75-8b3d-5c2d9c06d565.jar' \
  --output /tmp/connect-e2e/current-source-slots-r3/capture-slots-replay.json
rtk proxy python3 -B -m unittest discover -s tool/e2e/video_fixture \
  -p test_analyze_capture_slots.py -v
```

九条离线测试通过；CLI拒绝覆盖原始证据。分析器拒绝data-loss、进程歧义、未闭合或
越出父slice、重复／逆序acquire、无来源release及slot状态冲突；按墙钟间隔加权，
不使用PTS或跨时钟相减。源侧隔离候选需要下一轮实际验证，不能将本次测量当修复。

## 下一批隔离候选的最小实施约束

只读设计以当前受控源码为准，首个候选限定API36主屏H264／`c2.android.avc.encoder`，
请求画质1280／60／8Mbps不变，最多两个实际输入。以下尚未实施、构建或设备验证。

- `ScreenCapture.start()`无filter时强制经过identity GL桥；保留当前videoSize，不能
  顺带扩大源纹理到完整物理分辨率。`OpenGLRunner`复用现有SurfaceTexture／EGL。
- 独立纯Java状态模块管理最新pending、最多两项ledger与单一drain任务。GL handler
  继续updateTexImage取得最新源帧，无credit也不等待；pending可以覆盖。输出credit
  到达后主动drain，确保唯一终帧不依赖下一次frameAvailable。
- 每次codec重建取得独立输入流，`codec.start()`成功后激活；不能在现有capture.start
  先于codec.start的窗口提前swap。登记PTS在swap前，失败撤销整代，不伪造输出。
- `SurfaceEncoder.encode()`成功交付完整媒体packet及releaseOutputBuffer后按精确PTS
  删除一条ledger；CONFIG／重复／未知PTS不误还credit。首个候选拒绝partial-frame与
  无法对应的媒体PTS，不用最大PTS批量释放。`SurfaceCapture`接缝默认无操作，其他
  capture adapter保持原行为。
- 原生`repeat-previous-frame-after=33334`会在GBS内部自行生成输入，绕过GL ledger；
  候选必须关闭原生repeat，将原33.334ms重复策略交给同一个credit模块。限帧也在该
  模块按原60fps请求执行，避免GBS静默丢掉已记账输入造成credit永不归还。
- 静态首帧没有输出时，可按重复期限用尚存credit提交保留纹理的第二帧。满两个仍无
  输出则有界失败，不自动扩窗／降画质／隐式回退。仅ledger非空检查stall；不得将
  正常静止的空ledger判失败。
- 重复提交有独立单调编码PTS；ledger同时保留原始SurfaceTexture timestamp、实际
  编码PTS和repeat标记。源PTS因重复而冲突时显式映射，源年龄仍按原始源时间算，
  不把重绘后编码时间更新当优化。真实输入→像素／实际窗口门槛不变。
- 暂停／旋转／stop先关闭这一代输入流，撤销timer／drain／旧output，再沿现有顺序
  capture.stop→codec.stop/release→Surface释放→pause ACK。GL handler不等待credit，
  但未实际完成底层清理也不能提前ACK。旋转重建全套状态，不跨代保留待提交纹理。

[官方SurfaceTexture生命周期](https://source.android.com/docs/core/graphics/arch-st)
支持在所属GL上下文调用updateTexImage并释放旧buffer的接缝；不代表桥的性能已通过。

受控补丁叠加当前暂停补丁，在独立工作树／临时构建目录生成候选JAR／SHA／manifest，
保留两份补丁摘要；实际Driver路径由Rust静态嵌入，候选APK也必须在隔离工作树嵌入
候选JAR及对应SHA。仅将文件push到目标不能证明正式路径使用它；原生产产物不覆盖。

最小状态测试覆盖：两项占满后多次变化只提交最新pending、无后续事件的终帧、静态
第二帧bootstrap与满窗stall、CONFIG／重复／未知／partial、output早于swap返回、
swap失败、暂停穿过reserve窗口、关闭后旧timer／output无效。继续执行原CapturePause
测试，并补真实encode接缝。实际设备先验证静态冷启、动态→唯一终值→完全静止、
暂停恢复、旋转及stop，再做同负载普通Driver A/B/A和slot追踪。GL成本与失败原件
保留；实际新像素改善和输入驻留收窄均有证据后，才考虑产品默认。


## 隔离候选首次实施与服务端验证

`servers/scrcpy/experiments/bounded-input/candidate.patch`已实现上述限定候选，三新增
模块及四个原类接缝。独立构建入口不接受仓库内或已存在输出目录；七条保护回归通过，
其中下载分支的输出变量遮蔽在本轮检查中修正并加入实际输出控制流测试。该下载测试
使用临时SDK／编译器替身，只验证目录／ZIP输出，不冒称编译Java。

```sh
rtk proxy python3 -B servers/scrcpy/test_build.py -v
rtk proxy python3 servers/scrcpy/build.py --output-dir /tmp/connect-bounded-input-baseline-build
rtk proxy python3 servers/scrcpy/test.py --build-dir /tmp/connect-bounded-input-baseline-build
rtk proxy python3 servers/scrcpy/build.py --candidate bounded-input \
  --output-dir /tmp/connect-bounded-input-candidate-build
rtk proxy python3 servers/scrcpy/test.py --candidate bounded-input \
  --build-dir /tmp/connect-bounded-input-candidate-build
```

实际基线独立重建SHA仍为b46cd074…、CapturePause通过；候选SHA-256
`34294a6a21ef57f0ecdb74b8ed418bdd2e05198eea553446c7b5c7e44911fc6b`，原CapturePause及
六组纯Java行为通过。编译器source/target8废弃警告保留。外部manifest同时记录基础
补丁和候选补丁摘要；生产vendor／捕获JAR未覆盖。

目标AVD两vCPU／SwiftShader，实际宿主ADB部署、双socket scrcpy协议／控制与H264
完整数据包，经临时固定imageio-ffmpeg0.6.0所带FFmpeg7.0.2离线解码核对：

| 场景 | 真实解码计数 | session／尺寸 |
| --- | --- | --- |
| 静态冷启 | 0 | 1／576×1280 |
| 仅一次静态变化 | 1 | 1／576×1280 |
| 持续动态后关闭动画、唯一终值静止 | 1 | 1／576×1280 |
| 暂停期间变化后恢复 | 2 | 2／576×1280 |
| 旋转重建（夹具Activity重新创建） | 0 | 3／1280×576 |
| 横屏继续操作 | 1 | 3／1280×576 |

pauseACK后先排空300ms再观察300ms媒体计数不变，服务端正常exit0；唯一进程／JAR／
fixture／forward移除、系统旋转设置恢复均确认。原件
`/tmp/connect-e2e/bounded-input-smoke/`含脚本副本／SHA、server.log、各阶段完整H264、
实际解码64×64图像、FFmpeg摘要和result.json。复跑命令使用新输出目录：

```sh
rtk proxy python3 -B /tmp/connect-e2e/bounded-input-smoke/driver.py \
  --jar /tmp/connect-bounded-input-candidate-build/interop-scrcpy-server.jar \
  --out /tmp/connect-e2e/bounded-input-smoke-replay
```

这是临时单目标服务端实验，固定测试机名emulator-5556和lab工具路径，不作为产品
依赖／通用安装脚本。所有实际像素来自编码输出；FFmpeg离线解码结果不能当实时
Flutter窗口或首帧／输入延迟，未称性能收益。下一步在隔离工作树嵌入候选APK，
核对实际native库确含候选JAR字节，再跑原普通Driver和真实窗口。


补丁现改为无上下文diff，避免diff语法中的空白context触发Git空白检查。独立r2构建
及JVM重跑通过，候选JAR与首次字节完全相同；只读review未发现确定的新问题。
当前正式Driver基线APK的`lib/x86_64/libinterop_bridge.so`已查到完整原JAR字节，
回执`/tmp/connect-bounded-input-baseline-apk-receipt.json`。候选APK在独立工作树编译，
不以另推文件或只检查摘要字符串代替实际嵌入验证。


## 普通Driver A/B/A与候选slot复核

基线debug构建34.5秒、隔离候选97.5秒，计时前均已结束并停止Gradle。两份APK的
`lib/x86_64/libinterop_bridge.so`分别含完整原／候选JAR字节，候选库没有原捕获JAR；
保存`/tmp/connect-bounded-input-{baseline,candidate}-apk-receipt.json`。同两vCPU／
SwiftShader AVD、持续动态图案、H2641280／60／8Mbps、默认async=1、普通Driver，
三轮八输入，实际setup／decoderPolicy／画质／样本数逐项核对后结果如下：

| 顺序 | 输入P50／P95 ms | 首像素3次 ms | 实际窗口匹配／迟到 |
| --- | --- | --- | --- |
| A1 原JAR | 1722／1984 | 3124／2419／2218 | 30／25 |
| B 候选 | 666／927 | 2780／2544／2399 | 30／13 |
| A2-final 原JAR | 1700／2080 | 1879／1992／2297 | 30／21 |

每组24次真实输入、暂停恢复／停止／App与fixture清理确认；结果分别在
`/tmp/connect-e2e/bounded-input-{a1,b,a2-final}/`，匹配回执
`/tmp/connect-bounded-input-aba-matched.json`。候选有输入改善，但仍超过200／300ms，
首帧没有改善，窗口预算依旧3秒，全部严格exit1／performanceComplete=false。诊断
收集期限15秒不放宽成功判定；不能据此替换生产默认或称完整性能验收通过。

返回A2首跑在第二轮一次输入超过3秒而失败，第一轮8个输入和全部原件／清理保留。
A2-r2错误使用R热重启，丢失原预编译APK的Dart defines，实际native decoder／每轮4次
输入，12输入1999／2411ms被排除，不混入匹配对照。最终直接重装同一基线APK、显式
保留default／3轮／8次编译参数后才取得上表A2-final。使用预编译APK时，后续热重启
仍须显式传递同一Dart defines；不能只凭APK文件名假定正在运行的配置。

独立一轮候选追踪的外围脚本错误要求JAR路径仍可读取而assert失败，宿主流程被
中断。固定上游`CleanUp.unlinkSelf()`在cleanup启动时删除自身路径，缺席不是会话
已退出；未取得运行时文件摘要，也不以该探针当失败的产品连接。保持同一会话，
另行采8秒／32MB gfx／video／hal／sched／sync并精确pull与清除远端文件：

- 进程`interop.scrcpy:5d181b8c:/data/local/tmp/interop-scrcpy-07e90112-5f35-49fe-be0c-e4d9ba3c7f25.jar`，pid14115。
- trace SHA-256 `da2d59511b35077b93533384ef421a045b5092caaf33471a53d479dfd0529aa2`。
- 严格分析data-loss0、唯一进程，379事件／95 acquire／94 release／93完整周期，
  观察到同时acquired范围0–2；末墙钟1/3持有2个79.213%、1个20.737%、0个0.050%。
- 后段34个完整周期中位128.621ms、范围55.524–244.493ms。宿主中断后无继续输入／
  实际窗口循环，播放器仍运行；该数值不能和先前1318.763ms当同负载定量比。
- `/tmp/connect-e2e/bounded-input-b-trace/`保存原trace、严格完整分析及身份回执。
  该次宿主没有完成性能组，重新连接同一Driver发cleanup，输出／设备断开／移除
  全部确认；再精确卸载fixture并返回Settings。`manual-cleanup.json`明确记录恢复，
  不将其写成自动finally成功；没有因外围观察异常重启实际会话。

候选仍是明确限定API36／主屏H264软件编码器的实验补丁。后续先处理首帧额外开销和
剩余解码／呈现等待，再做其他codec／硬编支持与真实ARM／Wi-Fi／功耗资格验证，
不把此处局部输入改善外推为所有设备支持。普通发布仍使用原捕获JAR。


复现普通Driver需在`apps/connect`构建并保留每组APK，候选步骤在隔离工作树执行，
先复制外部构建的JAR／SHA／manifest，原工作树不替换。构建与运行均显式传同一配置：

```sh
rtk proxy flutter build apk --debug --target-platform=android-x64 \
  --target=benchmark/live_video_performance.dart \
  --dart-define=CONNECT_PERF_DECODER=default \
  --dart-define=CONNECT_PERF_ROUNDS=3 --dart-define=CONNECT_PERF_TRANSITIONS=8
rtk proxy flutter run --no-pub --use-application-binary=/tmp/connect-artifacts/bounded-input-candidate-debug.apk \
  --target=benchmark/live_video_performance.dart --print-dtd -d emulator-5554 \
  --dart-define=CONNECT_PERF_DECODER=default \
  --dart-define=CONNECT_PERF_ROUNDS=3 --dart-define=CONNECT_PERF_TRANSITIONS=8
rtk proxy env VM_SERVICE_URL='<本次App的实际VM service URI>' \
  CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_VIDEO_FIXTURE=/tmp/connect-video-fixture/video-fixture.apk \
  CONNECT_E2E_VIDEO_MOTION=true CONNECT_E2E_SCREEN_CAPTURE=raw \
  CONNECT_E2E_DIAGNOSTIC_SURFACE_MS=15000 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/bounded-input-new-group \
  dart --packages=../../.dart_tool/package_config.json test_driver/live_video_performance.dart
```

先按既有夹具入口启动两台AVD并设置目标TCP5555及host25556 forward。A1／A2换回
`bounded-input-baseline-debug.apk`，每次安装后核对setup；目标质量保持1280／60／8M。
`/tmp/connect-bounded-input-aba-matched.json`保存本次配置一致性证据。计时期间不编译
或跑trace；最终恢复普通main并复核实际native库含原JAR、候选缺席，再做MCP热重载
及首页视觉检查。当前main构建36.8秒、安装1145ms、热重载118ms／无Dart错误，实际
首页与三组VIDEO1窗口均目视；root和隔离工作树的debug白名单788项清理2871.6MiB，
空闲42.96GiB。保留两份生产JAR及release、有效缓存、候选工作树和必要原始证据；
AVD／Gradle／forward均停止或清除，不因工具改动重打同源release。

## 双项启动、单项稳定输入的后续实验

普通Driver新增源端input／首次draw与前后时钟区间的唯一关联后，原固定双项候选
24次新计数drawEnd→raw接收完成的条件下界均≥217.334ms，中位下／上界
310.819／390.331ms。目标input→drawStart中位0.463ms。后续核查发现此raw包是
snapshot选中的新计数帧，未证明它是最早的新计数包，不能唯一归因于源端或decoder。
区间依赖固定偏移、无休眠／时钟跳变，draw callback结束不代表合成结束。

当前实验补丁保留首个有效媒体output前最多2项以支持静态codec bootstrap，之后
缩到1项。精确媒体PTS归还credit后才缩窗，CONFIG／空EOS不缩窗，两项启动输入
全部退还后才准入后续输入；保留主动终帧drain和3秒stall，不扩大窗口兜底。
七组状态测试的新断言在旧二项实现实际红、新实现绿，暂停JVM测试也绿。

因此实际重建一次隔离JAR（SHA1a3d2c82…），两份生产JAR不动。真实H264解码验证
静态唯一变化后完全静止3.5秒仍持续输出且终值正确，暂停恢复／旋转／停止通过；
`/tmp/connect-e2e/bounded-input-steady-one-smoke/`。该smoke证明当前软件codec可
持续单项推进，不代表所有codec支持，也不作为Flutter性能证明。

同普通Driver／质量／默认async=1／traceFrames及traceClock、各3轮24输入的
固定双项→新变体→固定双项返回：P50／P95=691／852→581／810→686／925ms。
drawEnd→raw条件下／上界中位310.819／390.331→290.802／367.212→328.236／
401.090ms，各组区间仍重叠。输入P50约下降15–16%，首帧无稳定收益，严格性能
预算仍失败；30张窗口每组均正确，迟到16→9→15。三组暂停恢复／停止／自动清理
确认。原件`/tmp/connect-e2e/source-{clock-bounded,window-steady-one,window-two-return}/`，
汇总`/tmp/connect-source-window-aba.json`，完整产物和复现配置见
[视频性能记录](../implementation/video-performance.md#普通driver源端绘制关联与单项稳定输入实验)。

新变体仅保留在实验目录及隔离工作树，不推广生产。实际ARM硬编／Wi-Fi／小时长稳
和其他codec资格仍待验证，普通主控侧优化继续复用已有生产JAR。

## 完整编码序列核查选择偏差

为避免把较晚snapshot选帧当最早源包，新增完整raw packet ledger→生产Matroska
转封装→逐帧解码／精确PTS／新计数关联。修正后的r2实录308包与308帧完全对应，
8键／首次draw完整，输入→最早新计数raw包中位156.400ms，首次drawEnd→该包
条件下／上界中位113.375／161.004ms；时钟区间47.629ms。原件
`/tmp/connect-e2e/first-counter-raw-steady-one-r2/`。未重建JAR，仍为1a3d2c82…。

该实验由宿主直接forward接收，主控AVD空闲，未包含产品Rust复用和Flutter负载。
因此不能与普通Driver581ms作减法或断言余量属于某个模块；它说明最早帧与snapshot
选中帧必须分开验证，下一步在同一实际产品路径保留完整媒体序列，而非继续凭选中
raw帧的较晚时间修改源队列。复现和工具验收见
[完整帧记录](../implementation/video-performance.md#最早新计数帧与快照选帧的区别)。
