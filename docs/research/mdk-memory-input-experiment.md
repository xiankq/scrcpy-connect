# MDK 输入链路与解码延迟对照

2026-10-19，原实验工具提交 `2f5123d`，后续诊断工具提交 `1cd5d1b`。两阶段工具现已合入 `dev`，位于 `tool/benchmark/native_input_*.dart`、`tool/driver/native_input.dart` 和 `crates/interop_bridge/src/media_input_probe.rs`。正式播放器仍使用 Matroska localhost HTTP；实验入口独立运行，没有新增产品播放模式，也没有修改社区原版 fvp 0.39.1 或 pub cache。

结论：**Rust 经 MDK `stream:` / C API `appendBuffer` 直送 Matroska 已实际解码、渲染成功；最初两组使用同一 AMediaCodec 后端，均出现约一帧等待，因此这组结果只能说明该后端下更换入口没有明显收益，不能说明94ms合理或是传输成本。** 随后的单变量对照将相同HTTP输入改用FFmpeg slice解码，输入到onVideo降至约1.6ms，等待范围已缩小到本机AMediaCodec解码/输出路径，详见下文。它不是直播内存所有权、背压或跨平台生命周期已经满足生产要求的证明。接口依据及未明确契约见[输入链路研究](cross-platform-media-pipeline.md#2026-10-19-输入链路复核)。

## 环境与输入

- Ubuntu x86_64；Flutter 3.47.6 / Dart 3.13.5；Android 16 API36 x86_64 AVD `emulator-5554`，指纹 `google/sdk_gphone64_x86_64/emu64xa:16/BE2A.250530.026.F3/13894323:userdebug/dev-keys`。只使用既有主控 AVD，没有增加被控设备。
- Android-x64 profile/AOT 包，入口 `tool/benchmark/native_input_probe.dart`，APK SHA-256 `734aa6597ef827d3631d670e2521f9fd328bac2a65e45cd7b12cf1298ecb4b7e`。运行时 MDK version=9984（0.39.0），沿用原版 fvp 的本机 SDK 缓存，stamp `70d9dffb289a26054567e51088786af730bb1ffc46bffdf2f09e10d7ebf7b012`。
- 同一份既有动态色块录像，H264、576×1280，381帧、36,352,674µs；不是60fps负载或当前实连 ADB 端到端测试。原 MKV 为7,185,539字节，SHA-256 `28ae976f7f2d79f046da6194c8101a0d1af2da5eb1aae035b22a1ffaee09889f`。
- 夹具按真实 EBML 元素及记录 PTS 切分为一个 header、381个逐帧 Cluster，拼接字节与原 MKV 相同；不通过扫描任意 magic 字节猜边界。MDKP 夹具7,190,131字节，SHA-256 `b142de208940c16e6f8711383b182dd1937b78b2e2cefa505683c266455188fb`。

两组使用同一 APK、同一 Player 配置和容器字节，由 Rust 专用线程按相同 PTS 供数。HTTP 使用一次持久在线连接、TCP_NODELAY及逐 chunk 三次写入；内存组借用 fvp 的 `mdkPlayerAPI*`，通过其 `object` 调用真实 C 函数指针，不经过 Dart 逐帧转发。两组实际 `decoder.video` 均报告 AMediaCodec；AVD 的 goldfish codec 不作为物理硬解证据。buffer 为 min=0/max=150/drop，Matroska probe 参数保持一致。

为了避免猜测 append 是否同步复制，固定夹具在整个实验进程保留；预读、哈希和该固定存储的建立在计时前完成。它没有验证持续增长数据的回收期限，也没有证明零复制或 append 内部字节队列有界。

## 测量方法与结果

顺序为 `HTTP, append, HTTP, append, append, HTTP, HTTP, append`。前两轮作为预热，后六轮每组3轮；每轮在源仍持续供数的15秒窗口内采集。性能测量期间没有并行构建或测试。

延迟定义为同一帧的 **Rust 输入调用进入 → MDK onVideo 回调**，两端共用 Rust 单调时钟。按 PTS 容差小于2µs匹配，只比较六轮均成功解码、PTS在 `[3s,14s)` 的109帧；header不计入帧。每轮实际累计162个解码回执，六轮 trace drops=0、append拒收=0、native error为空。以下为每轮百分位的组内中位数，不是把相关帧当独立重复实验计算置信度。

| 指标 | HTTP | 内存 append |
| --- | ---: | ---: |
| 输入到解码 P50 | 94.518ms | 93.740ms |
| 输入到解码 P95 | 163.222ms | 163.353ms |
| 计划供数时刻到解码 P50 | 94.583ms | 94.024ms |
| 计划供数时刻到解码 P95 | 163.384ms | 163.518ms |
| 写入／append 调用耗时 P95 | 0.151ms | 0.062ms |
| CPU，100%为占用一个核 | 21.03% | 21.06% |

CPU按 `/proc/self/stat` 的 utime+stime、实际 wall 时间计算，设备 CLK_TCK实测100。内存组调用本身较快，但两组输入到解码 P50仅差0.778ms，P95没有改善，CPU范围重叠。不能将调用耗时当整段传输成本，也不能从这组有限样本推出两种输入在所有设备上等价。

逐轮原始指标如下，P50/P95单位ms，CPU为一个核的百分比：

| 正式轮次 | 模式 | P50 | P95 | CPU |
| --- | --- | ---: | ---: | ---: |
| 3 | HTTP | 93.692 | 163.222 | 20.96 |
| 4 | append | 93.740 | 164.862 | 21.20 |
| 5 | append | 94.503 | 163.353 | 20.73 |
| 6 | HTTP | 94.539 | 163.209 | 21.03 |
| 7 | HTTP | 94.518 | 163.320 | 21.30 |
| 8 | append | 93.243 | 163.259 | 21.06 |

HTTP prepare耗时8～16ms，append为3～5ms；这是准备回执，不是实际显示首帧。HTTP轮次峰值RSS为271.85～278.79MiB，append为274.88～276.71MiB；共享进程、固定夹具及解码器缓存随轮次变化，不能据此宣称内存占用改善。

两组都表现出上一帧的 onVideo 紧跟下一帧输入：六轮该时间差P50为0.503～0.706ms，P95为2.344～3.949ms。这曾使容器读取与后续提交节拍成为优先候选；下文实验中，明确Cluster长度、direct和noparse均没有改善，而更换解码后端显著改善。不能继续把这一相关性直接解释为容器必须等待下一帧。

每轮计时后执行一次实际64×64像素读取，色块 counter oracle有效，并核对 snapshot PTS存在于解码回执；最终两组截图也已目视看到动态色块内容。截图与snapshot在性能计时后，不把截图捕获成功当作显示延迟测量。未测物理屏幕扫描、触控往返或完整 ADB 编码链路。

## 同日继续定位：公共解码后端掩盖了输入差异

诊断阶段的配置工具提交 `b74e314`、偶数轮中位数修正 `1cd5d1b`。先对旧回执执行 `jq -e '.groups.http.inputP95Ms.median < 20 and .groups.append.inputP95Ms.median < 20' comparison.json`，稳定返回false/退出1；20ms是本次诊断预算，不是产品SLA或官方scrcpy保证。随后保持编码包、PTS、供数节拍和测量定义不变，逐项测试。

第一项只把Cluster的未知长度VINT替换为实际长度，字节数、内部payload和时间戳不变；新夹具SHA-256 `ef187d382f7c6033f286e940b2edd53b3808151b128044b80096d47a6d84dbcb`。HTTP与append的P50/P95分别为94.408/163.541ms、94.508/166.855ms，没有改善，故不将该变换合入生产mux。

其他项恢复原夹具 `b142de…188fb`，共用同一profile APK，SHA-256 `70d8e896539c47078d41220e3ac4de01e07fe642f08dc162d417f8d658e937c4`。两批合计12轮，全部完成真实像素和清理回执；每批按共同PTS窗口对照，分别均109帧。下表每项是指定轮次的P50/P95，不把单轮当作所有设备的统计分布。

| 配置，其他参数保持不变 | 输入到onVideo P50 | P95 |
| --- | ---: | ---: |
| 原AMediaCodec async基线 | 95.055ms | 163.248ms |
| 仅 `avformat.fflags=+noparse+nofillin` | 95.262ms | 164.455ms |
| 仅 `avformat.avioflags=direct` | 95.158ms | 163.256ms |
| 仅改用 `FFmpeg:thread_type=slice` | 1.606ms | 1.835ms |
| FFmpeg slice再加 `avcodec.flags=+low_delay` | 1.591ms | 1.783ms |
| AMediaCodec async，`surface=0` | 93.739ms | 163.335ms |
| AMediaCodec async，`low_latency=1` | 95.440ms | 166.610ms |
| AMediaCodec async，`image=0` | 93.409ms | 163.164ms |
| AMediaCodec，`async=0` | 296.970ms | 413.040ms |

第二批再次测试FFmpeg slice为1.587/1.912ms，前后AMediaCodec基线分别为94.532/163.245ms和94.853/163.800ms。实际decoder事件分别报告FFmpeg与AMediaCodec，没有将候选字符串当运行选择。`low_latency`、`direct`等配置无改善只说明本次调用的实际结果；MDK允许存储未知property，不能从设置未报错反推每个参数在内部均生效。

最后用FFmpeg slice做 `HTTP, append, append, HTTP` 四轮对照，启用driver的P95小于20ms预算。四轮均通过预算、像素及停止清理断言，按同样109个共同PTS比较：

| 轮次 | 输入 | P50 | P95 |
| --- | --- | ---: | ---: |
| 1 | HTTP | 1.586ms | 1.746ms |
| 2 | append | 1.524ms | 1.674ms |
| 3 | append | 1.520ms | 1.691ms |
| 4 | HTTP | 1.561ms | 1.767ms |

每组两轮的中位数取两个中心值的平均：HTTP为1.574/1.757ms，append为1.522/1.683ms。差异远小于最初约一帧等待，不支持以绕过HTTP解释或解决那94ms。完整回执为 `/tmp/connect-mdk-latency-software/run-YYAQXE/`；该批20ms断言实际返回true/退出0，未仅回放旧数值作通过声明。

第一批原AMediaCodec首个编码帧进入到onVideo为342.167ms，软件slice为6.682ms，加low_delay为5.192ms。各轮prepare回执仅8～10ms，说明prepare不能代替首帧。这里仍不含部署、连接、被控编码器启动、Flutter/GPU与物理显示，不能写作整个远控首屏已优化到5ms。

这份录像381帧跨36.35秒，帧间隔并非固定60fps。约一帧的等待在该输入下就会变成约94ms，不能机械外推为60fps下固定额外94ms；同样，静止前最后一帧被保留的问题也不能用平均fps掩盖。

**可下的因果结论：同一HTTP、相同容器和包在FFmpeg路径可迅速交帧，最初高延迟的主要等待位于当前AVD所走的MDK AMediaCodec解码/输出边界。** 尚未获得系统codec输出可用、MDK取出输出与onVideo之间的独立时间点，因此不能唯一归因于goldfish驱动、MDK轮询或重排。软件对照不是所有Android设备都应默认软件解码的依据；生产没有据此强制切换后端。

官方scrcpy的完整包直送、LOW_DELAY及默认不额外缓冲的源码依据，以及上述候选的反证，见[客户端路径研究](scrcpy-client-latency-path.md)。参考FFmpeg的Matroska H264 parser本就使用完整帧模式；未知Cluster可立即交付内部SimpleBlock。软件slice与slice+low_delay本次也近似，不能把本次改善再归因于后加的low_delay标志。

本次回执：`/tmp/connect-mdk-finite-cluster/run-ZHEBVE/`、`/tmp/connect-mdk-latency-options/run-CISJSA/`、`/tmp/connect-mdk-latency-native/run-NMHSWY/`。诊断driver支持逐轮配置及 `CONNECT_MDK_INPUT_MAX_P95_US` 预算，写出原始回执后才判断超限，避免只以进程正常结束判定低延迟通过。生产修复、物理设备与完整首屏对照仍未完成。

## 失败记录与生命周期边界

最早一次 HTTP 试验要求在保持连接、不发EOF时等待完整36秒夹具的最后PTS。全部382个chunk已写入、无拒收，但未在预算内得到指定末帧回执，该次失败未保存完整逐帧回执，不能据此确定原因。随后将直播性能测量改为源仍供数的窗口；**有限流 EOF 收尾仍未验证**，没有猜测使用空指针/零长度EOF协议。

另外两次测试程序失败分别为：Flutter drive默认卸载测试包导致预载夹具丢失；同一进程第二轮重复初始化FRB。二者均发生在有效 append 测量前，不算作 MDK append 失败。驱动现于安装后复制夹具、结束时删除，保留测试应用；FRB初始化复用一次Future。

正常路径每轮确认供数线程实际退出、无在途native调用、释放借用token，再确认 stopped、分离Texture并请求 fvp dispose。8轮及最终cleanup均通过，夹具删除成功；未发现 Dart runtime error。原版 fvp dispose为async void，故回执明确 `nativeDeleteConfirmed=false`，不宣称已独立确认原生对象删除。

失败路径保留未结算的纹理创建Future；超时不会被当成取消。停止后仍无法结算的操作会使cleanup失败并保留Player，避免提前销毁被借用地址。Rust测试覆盖阻塞append期间取消不能提前release、实际HTTP chunk/凭据/保持连接及ABI布局；interop-bridge库25项测试通过。新增Dart工具分析通过。实验profile应用不支持hot restart（VM返回unknown method），不将它写作热重启通过。

本轮没有验证音频、慢消费者、长期内存增长、暂停恢复、重连/旋转generation、其他Android版本或其他宿主。尚不具备将该适配器替换生产链路的依据。

## 复现与证据

当前 `dev` 复跑时，夹具生成和结果汇总仍从仓库根执行；Flutter构建与drive从 `app/` 执行，入口改用 `--target=../tool/benchmark/native_input_probe.dart`、`--driver=../tool/driver/native_input.dart`。下列命令用于重现原提交的目录布局。

实验代码保留在本地提交 `2f5123d`，包含fixture生成器、独立Flutter入口、host driver和按共同PTS汇总的Dart工具；依赖仍为原版 fvp 0.39.1。在该实验提交、已有完整录像归档的条件下，从该提交的仓库根目录执行（下列路径保留实验提交布局）：

```sh
flutter pub get --offline --enforce-lockfile
dart tool/benchmark/native_input_fixture.dart /absolute/archive-directory \
  --bundle /tmp/native-input.mdkp --defines /tmp/native-input-defines.json
flutter build apk --profile --no-pub --target-platform android-x64 \
  --target=tool/benchmark/native_input_probe.dart \
  --dart-define-from-file=/tmp/native-input-defines.json
CONNECT_E2E_ADB=/absolute/adb CONNECT_E2E_DEVICE=emulator-5554 \
CONNECT_MDK_INPUT_BUNDLE=/tmp/native-input.mdkp \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-mdk-input-abba \
CONNECT_MDK_INPUT_ORDER=http,append,http,append,append,http,http,append \
flutter drive -d emulator-5554 --profile --no-pub --keep-app-running \
  --use-application-binary=build/app/outputs/flutter-apk/app-profile.apk \
  --target=tool/benchmark/native_input_probe.dart \
  --driver=tool/driver/native_input.dart
dart tool/benchmark/native_input_compare.dart /tmp/connect-mdk-input-abba/run-XXXXXX
```

原始归档：`/tmp/connect-e2e/product-packet-diagnostic/round-1-archive-AQYDHG/`。正式回执、每轮JSON/PNG、cleanup与comparison：`/tmp/connect-mdk-input-abba/run-RJPMZR/`，驱动日志`/tmp/connect-mdk-input-abba.log`。临时路径用于追溯本轮运行，不保证跨机器存在；上面的环境、输入摘要和结果表保留独立可读的记录。

初次输入比较结束后回到 `dev`，普通 `lib/main.dart` APK已覆盖安装并启动，pid22980；MCP hot restart成功、runtime error查询为空。热重启时观察到两条FRB向旧isolate投递的failpost警告，未将其写作零告警。随后detach，普通应用仍运行。

普通APK仍为125,062,865字节、SHA-256 `ab5fcf9b9d796d53297c3e290573de132c489cae87f1cf06474b03a0ae853967`。已删除测试夹具、重复profile APK、过期build/Flutter与native hook单元输出和临时分析脚本，净清理1,417,018,559字节；保留普通APK、原始录像与测量回执，以及共享原生/Rust/Gradle/pub复用缓存。既有模拟器、其他调试资源未停止或清理。

继续定位阶段共18轮实际输入对照完成，其中最后4轮额外通过20ms诊断预算；该阶段不是生产AMediaCodec延迟修复。实验profile仍不支持hot restart，runtime error查询为空。结束再次回到 `dev`，普通APK覆盖安装、MCP hot restart通过、runtime error查询为空，detach后pid24365仍运行；APK摘要未变。清理该阶段重复profile包、过期build/Flutter/native hook单元输出和两份生成夹具，净1,305,212,943字节。保留原录像、逐轮回执及共享编译缓存，未停止既有模拟器。
