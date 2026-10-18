# 视频首帧、持续新像素与阻塞恢复

最新增量：首次MediaCodec分配复用候选在源端15次实测确认2→1，但完整Flutter
A/B/A没有稳定首帧收益，不采用生产，见下一节。实际Rust／Flutter完整编码前缀已逐帧验证；8输入中7项snapshot
选中最早新计数帧，input→firstRaw中位335.226ms，首帧与整体输入预算仍失败。
生产JAR不替换。此前普通Driver源时钟诊断与隔离服务端输入窗口实验：原双项→稳定
单项→双项返回输入P50／P95为691／852→581／810→686／925ms，首帧无稳定收益，
整体预算失败，生产JAR不替换。权威完成度见[当前状态](../../.scratch/interop/current-status.md)。
[Android显式异步解码](android-decoder-async.md)仍为生产默认；早期关闭诊断的60次
输入138／295ms属于当时测试路径，不能覆盖后续普通Driver的失败证据。
连接稳定性增量见[应用失活恢复](connection-health.md)。

2026-10-18。按用户最新优先级推进视频性能、首帧和连接稳定性；USB 等产品工作顺延。
仅实际改动被控捕获服务的隔离实验重建JAR，主控调优复用既有产物。
[产物与官方机制核查](../research/scrcpy-first-frame-performance.md)区分官方vendor文件和当前视频依赖的既有暂停补丁产物。

## 首次编码器分配复用：源端减少一次，完整首帧未通过

2026-10-18。仅`initial-codec`隔离补丁改服务端源码，未叠加bounded-input，未覆盖
生产JAR。基线暂停扩展创建编码器查询能力后释放，再为首捕获创建；候选初始gate
前移，用首次实例查询和捕获，codec选择、画质、约束与重试保持。控制对象必须在
构造时绑定到实际SurfaceCapture，避免Controller在init前丢弃pause/reset；flex
display初始暂停期间收到resize仅保留最新请求，实际init约束后应用。

真实编译`SurfaceEncoder.streamCapture()`接缝基线4项红：双分配、初始控制对象
为空、创建中pause未经历真实迭代清理、init失败缺少capture释放。候选5项全绿，
含清理中第二次pause的确认顺序。初版候选另由真实`NewDisplayCapture.requestResize`
复现null约束NPE，v2通过最新请求／真实Size约束／debouncer启动及释放。只替换
Android SDK接口，没有复制项目状态机。Python构建安全与协议／首包oracle／绝对
期限共15项通过；slow-trickle不会无限延长启动等待。对应源码及复现命令见
[候选说明](../../servers/scrcpy/experiments/initial-codec/README.md)。

同两台API36／2vCPU／2048MB SwiftShader AVD，构建全部结束、停止Gradle后测量。
官方ADB源端5组A/B/A共15次新进程：固定c2.android.avc.encoder、H2641280／60／8M、
repeat33334µs，每个首媒体包完整离线解码并核对计数0与576×1280。准确PID native
日志每次基线2分配、候选1分配。首包组中位370.494／358.573／345.836ms，候选减
前后基线均值的配对中位-26.611ms；五组差值-46.422、-61.466、-26.611、+27.115、
-1.861ms。排除部署、fixture启动与离线解码；该有限结果不等于Flutter可见收益。
原件`/tmp/connect-initial-codec-startup-aba`，脚本
[benchmark_startup.py](../../servers/scrcpy/benchmark_startup.py)。

实际候选生命周期验证：control连接后立即pause、静止首帧与唯一更新、3.5秒静止后
新计数2、动态→终值、再次pause/resume新计数、旋转和旋转后输入，共8阶段正确。
初始pause及后续pause确认后均静止，最终精确进程／临时JAR／forward／fixture／设置
清理通过。初次错误复用bounded-input的无限静态repeat断言失败，保留
`/tmp/connect-initial-codec-lifecycle`；原生GBS只有限重复，正确夹具要求静止后新计数
确实到达，最终原件`/tmp/connect-initial-codec-native-lifecycle`。不把合法静态停帧当
失活，也不删除失败证据。

普通Driver使用同代码、仅内嵌JAR不同的两APK，各1轮8输入，default解码、同目标质量：

| 观测（ms） | 基线A1 | 候选B | 返回基线A2 |
| --- | ---: | ---: | ---: |
| 首有效像素 | 2433 | 2356 | 2223 |
| Core启动 | 965 | 1045 | 1079 |
| 输出首帧验证 | 1455 | 1299 | 1133 |
| 输入P50／P95 | 1819／2127 | 1715／2007 | 1714／1911 |
| input→最早raw中位 | 1623.562 | 1483.765 | 1429.539 |
| drawEnd→raw条件区间的各端中位 | 1555.193–1628.207 | 1422.573–1469.443 | 1351.555–1412.613 |

候选无稳定优于返回基线的收益，三组严格exit1，**不替换生产JAR**。三份档案
658／599／647帧精确PTS全部解码关联，最早选帧分别6/8、7/8、6/8，全部最早onVideo
确实观察到；时钟区间73.014／46.870／61.058ms，drawEnd不是合成完成或物理扫描。
30张真实全屏窗口计数全部正确，部分超3秒仍失败；暂停／恢复ACK与新计数、逻辑
stop和fixture/App/driver清理通过。`disposeRequested`仍无native delete确认，不改称
删除完成。窗口已目视。相比先前bounded-input档案，这里是原生直接输入路径，不
直接把两次不同负载运行作该补丁的收益对照。

APK`/tmp/connect-artifacts/initial-codec-{baseline,candidate}-debug.apk`摘要
52bdcdd5…／93c542d7…，核验完整内嵌基线b46cd074…／候选23dc3f84…且另一JAR缺席；
构建74.1／54.5秒。原件`/tmp/connect-e2e/initial-codec-product-{a1,b,a2}`，汇总
`/tmp/connect-initial-codec-{product-summary,correlations,apks}.json`。
该轮缩小了首次分配假设，未解决源端持续积压或主控首呈现。下一步针对实际
callback／原sourceTimestamp／repeat／credit的等待关联；不再重复本项A/B/A。
收尾复用普通main APK89527f9a…，MCP热重载成功、无Dart运行错误，设备列表首页
已目视；没有追加main构建。DTD断开、精确forward清除、两自有AVD核名关闭且PID
消失，生产三JAR摘要未变。隔离JAR输入恢复生产，删除11项重复debug产物1310.7MiB，
空闲37.21GiB，保留实测APK／原始证据／有效缓存；清理回执见当前完成度。

## 实际播放器完整帧前缀与最早新像素

在已有`media.open`中显式启用`traceFrames:true, tracePackets:true`，默认关闭。
只为视频分配一份进程级诊断档案，最多32MiB编码body／8192帧；不增加第二消费者，
不在计时路径写文件，不增加录屏页面。保留现有Matroska头及完整发送chunk的body，
每帧保留sourcePts、重基PTS和既有Rust单调观测。音频／无逐帧观测请求明确拒绝。

`media.trace.seal(relayId)`封存完整前缀并返回字节数、代次及帧索引；继续播放。
封存与append共用锁，竞争时最后刚发送的一帧可能整体被排除，不会留下半帧或
中间缺口。未封存跨代／PTS重复或原点变化／容量超限将档案标失败并释放数据，
不影响播放。`media.trace.read(relayId,offset,limit)`只读已封存档案，每次1–65536
字节，返回Base64／nextOffset／eof，可重试；对应媒体关闭后不可读取。

普通Driver新编译开关`CONNECT_PERF_TRACE_PACKETS=true`要求同开traceFrames及
traceClock、仅1轮；8次输入和实际窗口结束后才封存和分页导出。Host将MKV及索引
放到/tmp唯一子目录，progress不保存Base64。每个计时输入之后另保存当时256条
raw transport窗口，离线最早新计数帧必须找到该窗口中精确唯一sourcePTS receipt。
不依赖全局ring保留整段，也不通过媒体PTS直接减主控时钟。

7组档案状态／预算／所有权测试通过；真实TCP／HTTP集成验证档案与实际发送body
逐字节相同且封存后继续播放，HTTP全17项通过。Rust clippy／定向Dart分析通过。
离线复用微秒时基解码，新增3组最早包／回调缺席／证据错误测试，同目录20项通过。
只读review未发现确定缺陷；不把未观察到的onVideo补成丢帧或呈现事件。

实际双2vCPU／2048MB／API36 SwiftShader AVD、普通Driver／默认AMediaCodec async1、
H2641280／60／8Mbps、既有单项候选1a3d2c82…；隔离APK562f7984…内核对完整
候选字节且生产捕获JAR缺席，未重建JAR。实际输出576×1280，381个包与381个解码帧
精确PTS全序列匹配，档案7185539字节，8次输入及暂停键日志完整、时钟区间68.849ms。
10张实际窗口全部计数正确、3张超3秒，暂停恢复／停止／App及fixture自动清理确认。
首像素3522ms，输入P50／P95=642／855ms；严格exit1，所有诊断禁止当生产性能绿灯。

| 同一实际输入对应的观测 | 中位 ms | 范围 ms |
| --- | --- | --- |
| invoke前观测→最早新计数raw完整接收 | 335.226 | 194.466–495.020 |
| 首次draw结束→最早raw条件下界 | 248.652 | 123.792–297.038 |
| 首次draw结束→最早raw条件上界 | 317.501 | 192.641–365.887 |
| 最早raw→首个onVideo | 133.274 | 71.946–333.103 |
| 首个onVideo→选中snapshot | 126.461 | 76.823–172.568 |

7/8次snapshot选中的就是最早新计数帧；另1次选中后一帧，raw晚123.745ms。
所有8次最早帧onVideo均实际观察到。raw接收后的两段也可逐输入相加核对，但表中
各段中位不能相加替代总分位数。draw跨端区间仍依赖无休眠／VM暂停／时钟跳变和
固定偏移，不把draw回调等同合成结束；onVideo→snapshot不是纯GPU耗时或物理屏
扫描时刻。最早raw帧的WRTE payload完成→raw中位0.030ms，payload开始→raw
1.313ms；前者不解释上游源端等待，后者不一定是精确帧在线路开始。

同一档案首尾mux跨度36.098秒、380个间隔平均10.527包/秒，body平均1.592Mbps、
最大mux间隔317.329ms。请求60fps／8Mbps没有被写成实际已达吞吐；此为AVD限定
软件编码／模拟图形负载结果，仍需真实ARM与无线资格。该组没有比较优化收益。
结论：此前快照选帧边界已补齐，当前实际路径确实同时存在首次draw之后和主控解码
呈现的等待；不能直接套入宿主直收156ms，也不应只换decoder或盲改ADB读buffer。

原件`/tmp/connect-e2e/product-packet-diagnostic/`包含实际窗口、完整MKV／帧索引、
逐帧计数、目标日志、早帧与raw／onVideo／snapshot关联。APK回执
`/tmp/connect-product-packet-apk.json`，构建日志`/tmp/connect-product-packet-build.log`。
隔离debug构建80.4秒，测量前停止Gradle，无并行编译；生产两份JAR不替换。

普通main恢复构建70.6秒，实际native库含完整原生产捕获JAR，两种候选均缺席；
MCP实际热重载成功、无Dart运行错误，首页／实际VIDEO1窗口／最早解码帧均目视。
Skipped32frames及SurfaceSync1000ms警告仍保留。两生产摘要未变，目标进程／文件／
fixture及精确forward均清理，两自有AVD核名关闭且PID消失，CLI／DTD／Gradle已
停止。清理22项大debug副本2680.2MiB，空闲39.37GiB，保留有效编译缓存、release、
测量APK和原件；回执`/tmp/connect-product-packet-{main-receipt,cleanup,debug-cleanup}.json`。
本轮为同路径归因进展，不声称优化收益或完整任务完成。

复现沿用前述普通Driver命令，构建与预编译APK运行两处同时设置default／1轮／8输入，
追加`CONNECT_PERF_TRACE_FRAMES=true`、`CONNECT_PERF_TRACE_CLOCK=true`及
`CONNECT_PERF_TRACE_PACKETS=true`三个dart-define。Host同开
`CONNECT_E2E_VIDEO_TIMELINE=true`并使用新/tmp输出目录；结束后执行：

```sh
rtk proxy python3 -B tool/e2e/video_fixture/analyze_player_archive.py \
  --run /tmp/connect-e2e/product-packet-diagnostic \
  --ffmpeg '<宿主FFmpeg可执行文件>'
```

## 普通Driver源端绘制关联与单项稳定输入实验

`15f795b`在默认关闭的`CONNECT_PERF_TRACE_CLOCK`下复用既有`session.clock.probe`，
不修改服务协议。每个真实输入（包括暂停中的输入）使用全局fixtureSequence，
host在卸载独立fixture前保存唯一run的input／首次draw日志。每轮前后各3次时钟
往返，为目标uptime和主控Rust单调时钟建立区间；快照PTS必须唯一关联onVideo、
relay和原始transport receipt，日志缺失、重复、Activity重置均失败。

此模型以区间而非点估计表达跨端时间，依赖校准期间偏移固定、无休眠／时钟跳变。
媒体PTS兼容是额外检查，不能把draw callback结束等同合成／编码完成。主控输入
时刻是在Dart invoke前观测，包含后续派发开销，允许条件下界为负；各段中位数
不能相加代替某一帧的全链路。traceFrames或traceClock开启均标记diagnosticOnly，
即使单项预算通过也不能把此组记作生产性能验收。

同原固定双项候选的3轮24输入：输入P50／P95=691／852ms，首像素3758／2647／
2906ms；27个真实key唯一匹配，三个时钟区间宽54.706／71.936／86.219ms。目标
input→drawStart中位0.463ms、draw callback0.632ms；首次新计数drawEnd→raw接收
完成的条件下／上界中位310.819／390.331ms，24样本下界均≥217.334ms。raw接收
完成→relay写入开始中位0.255ms，relay写入开始→onVideo98ms，onVideo→snapshot
128.957ms。这里关联的是快照选中的新计数帧，未证明它是最早包含新计数的包；
不能据此唯一归因于源合成／采集／编码，后续完整帧核查见下一节。

原件`/tmp/connect-e2e/source-clock-bounded/`及`/tmp/connect-source-clock-stages.json`。
30张实际窗口计数正确、16张超3秒，暂停恢复／停止／自动清理确认；严格exit1。
新增源报告3项、已有时钟3项及首帧3项共9项测试通过，定向Dart分析无问题。
诊断关闭另跑1轮2输入：无target-timeline文件／clockBounds，4张实际窗口正确、
暂停恢复／停止／清理确认，输入524／678ms、严格exit1；不与不同样本数trace组
比较收益。原件`/tmp/connect-e2e/source-clock-off/`。

源端实验因此将LatestInputWindow改为首个有效媒体output前最多2项，之后最多1项。
仅精确匹配reservation的媒体output才缩窗，CONFIG／空EOS不缩窗；保留静态重复、
唯一终值主动drain和3秒stall，不隐式扩容回退。新增状态断言在旧实现实际失败，
独立新JAR及CapturePause／7组状态测试通过。新JAR摘要
`1a3d2c82eefe420a36eab816f0557234141afa9c86763b92bc472dfdd3aeb881`，
构建于`/tmp/connect-bounded-input-steady-one-build/`；这次确实改了被控服务实现，
所以需要构建实验JAR。普通主控调优仍复用既有JAR，两份生产产物均未替换。

独立真实H264解码smoke通过静态冷启、唯一变化后完全静止3.5秒（媒体32→136，
终值仍1）、动态→静态终值、暂停恢复、旋转及横屏输入。pauseACK后媒体静止，
server正常exit0，进程／远端JAR／fixture／独立forward及旋转设置均清理。
`/tmp/connect-e2e/bounded-input-steady-one-smoke/`包含实际编码与解码证据；它不测
Flutter延迟。此候选仍只支持API36／主屏H264／c2.android.avc.encoder，不外推ARM。

将完整新JAR嵌入隔离APK（SHA`f5d1751380dcac4e9e51f46cdcfa705678bc6a82688d6509e1512a9d1ea49aae`），
核对旧候选与生产捕获JAR完整字节均缺席；A1／A2使用完全相同旧候选APK，
SHA`3f212e9646ccfb93cb7c7b341931ca774580810109d88d8b08124b5536435663`。
普通Driver／默认async=1、H2641280／60／8Mbps、traceFrames及traceClock开启，
3轮×8输入，同一双2vCPU／2048MB SwiftShader AVD；计时期间无编译或额外trace。

| 顺序 | 输入P50／P95 ms | 首像素3次 ms | drawEnd→raw条件下／上界中位 ms | 正确窗口／迟到 |
| --- | --- | --- | --- | --- |
| A1 固定双项 | 691／852 | 3758／2647／2906 | 310.819／390.331 | 30／16 |
| B 启动双项、稳定单项 | 581／810 | 2563／2381／2554 | 290.802／367.212 | 30／9 |
| A2 固定双项返回 | 686／925 | 2551／2553／2890 | 328.236／401.090 | 30／15 |

每组24输入、27键日志完整、3个时钟区间有效、所有实际窗口计数正确；暂停恢复／
停止／App及fixture自动清理确认。三组严格exit1，收集期限15秒仍保留3秒窗口预算。
输入P50相对两侧降低约15–16%，P95仅有限改善；源后段条件区间重叠，不承诺该段
确定缩短多少。首帧无稳定收益，继续保留隔离，不修改生产默认。relay→onVideo
中位98.000→88.023→97.149ms，onVideo→snapshot128.957→130.217→131.335ms；
后者包含呈现调度及readback，不能称纯GPU耗时。新候选仍有draw后数百毫秒等待。
原件`/tmp/connect-e2e/source-{clock-bounded,window-steady-one,window-two-return}/`，
汇总`/tmp/connect-source-window-aba.json`。

复现时在前述普通Driver构建与运行两处同时追加：
`--dart-define=CONNECT_PERF_TRACE_FRAMES=true --dart-define=CONNECT_PERF_TRACE_CLOCK=true`；
host另设`CONNECT_E2E_VIDEO_TIMELINE=true`，保留唯一输出目录。预编译APK直接安装
运行，不用热重启重编译混入其他defines。该诊断不替代关闭追踪后的生产验收。

收尾普通main构建21.2秒，实际native库含完整生产捕获JAR，旧／新候选均缺席，
两份生产摘要未变。MCP实际热重载成功、无Dart运行错误，首页及三组VIDEO1窗口
目视核对；Skipped33frames警告仍保留。两自有AVD核名关闭、PID消失，精确forward
移除，fixture与捕获进程／文件缺席，CLI／DTD／Gradle已停止。清理23项debug大
副本2737.2MiB，空闲40.11GiB，保留release、实测APK／原始证据及有效编译缓存。
回执`/tmp/connect-source-window-{main-receipt,production-jars,target-cleanup,avd-stop,
debug-cleanup}.json`。此批是诊断与隔离实验进展，完整性能目标保持开放。

## 最早新计数帧与快照选帧的区别

`_waitPixels()`成功后才读取snapshot PTS。此时选中的帧可能晚于最早已含新计数的
编码帧，因此前节drawEnd→raw区间本身不是“源端最早新像素延迟”。这不影响原
输入到snapshot总计时或有限A/B/A收益，但会改变下一步归因，不能继续盲目缩窗。

新增`tool/e2e/video_fixture/capture_first_counter.py`在独立授权目标上复用现有JAR，
连续保存完整H264包、精确PTS、文件偏移和宿主单调接收时刻。独立fixture记录每次
真实输入／首次draw，前后各3次`/proc/uptime`往返建立带10ms量化的时钟区间。
`remux_capture_packets`使用生产MatroskaMuxer保留微秒PTS；FFmpeg离线逐帧解码，
分析器要求完整的一包一帧、唯一精确PTS、计数连续且无重置，再选择计数第一次
出现的包。缺帧／重复／失败清理／错误校准不能输出完整报告。

首次实录251包与251帧、8键完整，时钟区间49.991ms。review发现旧工具在清理前
设置complete，分析器也未检查最终清理状态；修正为measurementComplete和最终
complete分离，并逐项拒绝reader／server／cleanup失败，各清理步骤独立容错。
初组原件保留于`/tmp/connect-e2e/first-counter-raw-steady-one/`，最终用修正版本
重新采集r2，不把初组当最终工具验收。

r2：308个完整媒体包对应308帧，8次计数和17条fixture事件完整、时钟区间47.629ms。
输入→最早新计数raw包中位156.400ms（110.144–248.309），首次drawEnd→该包条件
下／上界中位113.375／161.004ms。质量保持1280／60／8Mbps、576×1280实际输出、
同单项候选1a3d2c82…；双API36／2vCPU／2048MB SwiftShader AVD，主控AVD空闲。
宿主通过官方ADB forward直接接收，**没有经过产品Rust复用／Flutter解码呈现**。
因此不能从581ms减去156ms宣称某个模块耗时，也不能当实际产品或无线性能通过；
后续必须在同一实际产品路径留完整编码序列，才能比较最早raw包与snapshot选中包。

五组新增分析回归及同目录全部17项通过（含已有证据禁止覆盖），Rust示例编译／format／clippy通过。
r2采集结束13.6秒后才启动clippy；自动清理确认reader退出、server正常exit0、
远端进程／JAR／fixture及动态forward缺席。原件
`/tmp/connect-e2e/first-counter-raw-steady-one-r2/`包含完整流／逐包索引、MKV、
解码日志、逐帧PTS／计数、目标日志及首次计数报告。没有改动或重建任何JAR。

工具提交1fd7590。首次新计数帧59已离线导出目视，VIDEO1与色块正确，图片保存在
/tmp。没有Flutter或生产Rust路径改动，未重打同源APK；两生产JAR摘要不变。自有
AVD核名关闭且PID消失，目标进程／文件／fixture／forward缺席，空闲39.98GiB。
保留小型原始证据与有效缓存，无新增Android大debug副本；
`/tmp/connect-first-counter-cleanup.json`记录收尾。本轮为归因证据，不是性能修复。

复现需启动专用目标AVD，现有候选路径按实际构建目录替换；每次使用新输出目录：

```sh
rtk proxy python3 -B tool/e2e/video_fixture/capture_first_counter.py \
  --adb /home/xiankq/Android/Sdk/platform-tools/adb --target emulator-5556 \
  --jar /tmp/connect-bounded-input-steady-one-build/interop-scrcpy-server.jar \
  --fixture /tmp/connect-video-fixture/video-fixture.apk \
  --out /tmp/connect-e2e/first-counter-replay
rtk proxy cargo run -p interop-core --example remux_capture_packets -- \
  /tmp/connect-e2e/first-counter-replay
rtk proxy python3 -B tool/e2e/video_fixture/analyze_first_counter.py \
  --capture /tmp/connect-e2e/first-counter-replay --ffmpeg '<宿主FFmpeg可执行文件>'
```

转封装与解码都在测量结束后进行；工具拒绝覆盖已有MKV。被控端安装的fixture仅为
独立实验工具，不属于产品。禁止对用户已有同名fixture安装覆盖。

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


## 编码器对照与目标调度（2026-10-18）

现有性能入口增加显式`CONNECT_PERF_CODEC`与`CONNECT_PERF_ENCODER`，默认H264、
平台选编码器不变。三组串行运行，同一双AVD、动态夹具、实际576×1280、请求60fps/
8Mbps、经典ADB、原生AMediaCodec、逐帧trace开启，无额外snapshot压力或目标时间线。
每组2轮新连接/新会话、16次精确新计数、2次暂停恢复和实际Flutter合成验证；三组
`frameCorrelationComplete`/`fixtureCleanupConfirmed`均true，纹理分离/停止及fixture
卸载确认完成。两轮最终合成计数为9/2，三组首轮截图已目视，非黑屏。

| 配置 | 首像素两轮ms | 输入P50/P95 ms | 输入→relay中位ms | relay→onVideo中位ms |
| --- | --- | --- | --- | --- |
| H264，c2.android.avc.encoder | 2830 / 2520 | 1331 / 1592 | 1105.069 | 187.141 |
| VP8默认，c2.android.vp8.encoder | 2357 / 2308 | 973 / 1508 | 786.994 | 140.744 |
| VP8临时CBR=2，同编码器 | 2256 / 2253 | 1135 / 1546 | 937.767 | 181.067 |

onVideo→snapshot中位分别31.457/29.373/32.399ms。这里分段中位数不能相加解释
整体分位数。实际`video.frameTrace`codec为h264/vp8/vp8，VP8的CodecPrivate为空；
`decoder.video`均明确AMediaCodec，不能称模拟器物理硬解。编码器名称由显式参数
及既有枚举/服务端createByCodecName契约确认，没有新增实际encoder运行日志。

三组门槛保持首像素≤1000ms、输入P50≤200ms/P95≤300ms，均**exit1**，
`videoPerformanceComplete=false`。功能循环完成，性能未达标；完整
样本/清理见`/tmp/connect-e2e/video-codec-{avc,vp8,vp8-cbr}/`，命令输出分别
`/tmp/connect-video-codec-{avc,vp8,vp8-cbr}.log`。每组仅16次、固定顺序且没有交叉复测，
不把差异当稳定收益或跨设备推荐。动态色块不是文本/照片画质或稳定60fps吞吐验收。
历史MDK snapshot原生崩溃依然开放；本次未崩溃不代表已修复。

CBR候选仅在Rust构造scrcpy参数后、显式encoder参数前，对VP8追加
`,bitrate-mode=2`；不改JAR。原始源码已逐字节恢复，git diff为0。临时补丁保留
`/tmp/connect-vp8-cbr-candidate.patch`；该候选未胜过本次默认VP8，不进入生产默认。
固定AOSP的真实码控/CPUUSED分支和限制见[一手研究](../research/scrcpy-first-frame-performance.md#vp8实时编码与公开码控参数2026-10-18)。

复跑H264基线（apps/connect，沿用本文前面的双AVD/fixture构建及25556转发条件）：

```sh
CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
CONNECT_E2E_VIDEO_FIXTURE=/tmp/connect-video-fixture/video-fixture.apk \
CONNECT_E2E_VIDEO_MOTION=true CONNECT_E2E_VIDEO_TIMELINE=false \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/video-codec-avc \
flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/video_performance.dart \
  --target=integration_test/video_performance_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 --dart-define=CONNECT_E2E_PORT=25556 \
  --dart-define=CONNECT_PERF_CODEC=h264 \
  --dart-define=CONNECT_PERF_ENCODER=c2.android.avc.encoder \
  --dart-define=CONNECT_PERF_DECODER=native --dart-define=CONNECT_PERF_TRACE_FRAMES=true \
  --dart-define=CONNECT_PERF_MAX_SIZE=1280 --dart-define=CONNECT_PERF_MAX_FPS=60 \
  --dart-define=CONNECT_PERF_BIT_RATE=8000000 --dart-define=CONNECT_PERF_ADB_BURST=false \
  --dart-define=CONNECT_PERF_ROUNDS=2 --dart-define=CONNECT_PERF_TRANSITIONS=8 \
  --dart-define=CONNECT_PERF_PAUSE_CYCLES=1 \
  --dart-define=CONNECT_PERF_MAX_START_MS=1000 \
  --dart-define=CONNECT_PERF_MAX_P50_MS=200 --dart-define=CONNECT_PERF_MAX_P95_MS=300
```

VP8组仅替换codec/encoder和输出目录。CBR额外加上述临时参数，结束后恢复源码。
禁止为让命令变绿而放宽门槛或减小分辨率/帧率。

既有Perfetto `/tmp/connect-raw-drain-fbf1db6ec385/capture.perfetto-trace`继续只读分析，
不混入此次Flutter对照。真实软件AVC在`media.swcodec` PID639/TID14829，捕获进程
14802的CodecLooper接收完成回调。7.982333秒trace中，主编码线程已记录状态
7.656137秒，最初326.196ms没有其状态证据。

| 线程组 | on-CPU ms | 可运行等待R/R+ ms | 睡眠S ms |
| --- | --- | --- | --- |
| 主编码线程14829 | 4009.856 | 3595.733 | 50.548 |
| 另外303个同名编码线程合计 | 2548.586 | 2929.372 | 35.783 |
| 捕获CodecLooper | 99.896 | 188.023 | 7349.491 |

两目标vCPU的闭合sched覆盖7.647357/7.646336秒、非idle96.90%/96.53%。线程时间
合计不能当墙钟，主线程可运行等待不等于编码计算。trace每秒Surface queueBuffer
调用40/60/60/60/59/60/60/59，组件完成25/54/57/55/30/29/28/25；后段完成吞吐
下降而Surface调用仍约60/s。不同层没有逐帧身份映射，不能据此推断丢帧数、slots或
具体队列深度。已精确匹配的303项完成PTS首末跨度7.186644秒、完成回调跨度
7.604008秒，条件源年龄首末增长417.364ms；三段各101项年龄中位
290.313/285.255/590.659ms，保留原时钟和连续运行假设。

主线程状态复算（已有官方trace_processor，dur=-1裁剪到trace末尾）：

```sql
WITH w AS (SELECT start_ts lo,end_ts hi FROM trace_bounds), x AS (
  SELECT st.state, MAX(0,MIN(
    CASE WHEN st.dur=-1 THEN w.hi ELSE st.ts+st.dur END,w.hi
  )-MAX(st.ts,w.lo)) d
  FROM thread_state st JOIN thread t USING(utid)
  JOIN process p USING(upid) CROSS JOIN w
  WHERE p.pid=639 AND t.tid=14829 AND st.ts<w.hi
    AND (st.dur=-1 OR st.ts+st.dur>w.lo)
)
SELECT state,ROUND(SUM(d)/1e6,3) milliseconds FROM x GROUP BY state;
```

主代理独立复算R=2556.841、R+=1038.892、Running=4009.856、S=50.548ms。
证据支持目标调度竞争及源年龄增长，不能独证无竞争时软件编码算力仍不足。
下一步优先隔离目标CPU/合成竞争并观察实际输出吞吐，不继续盲加通用复杂度参数。
现有JAR摘要仍与manifest及vendor摘要一致；本批未修改/重建两个JAR。

性能入口严格Dart分析无问题、format/diff检查通过。普通main从恢复后的源码构建
59.7秒/安装576ms，实际热重载120ms且无Dart运行错误，设备首页已目视后detach；
启动Skipped34 frames警告仍存在，不计流畅度通过。Gradle停止后清理394项明确
Android debug输出，释放1493.4MiB、空闲51.3GiB；保留release/native hooks/Rust/
Gradle/CMake、Flutter hash缓存和全部原始证据。记录`/tmp/connect-video-codec-cleanup.json`。
目标无捕获进程/fixture，本批6个session逐项确认无遗留捕获JAR。


## 截图生命周期与暂停提交顺序（2026-10-18）

历史MDK renderer空`std::function`崩溃继续开放。本批处理审计中可证明的主控生命周期
问题，没有把它们认定为历史原生崩溃根因，也没有重建JAR或改默认编码/解码路径。

- Fvp的snapshot与setPaused通过同一个最多8项的操作队列。关闭立即拒绝新工作和
  尚未进入底层的排队工作，在途snapshot真实结果交付后才stop/detach/dispose。
  3秒未完成时返回`disposeDeferred`、`textureDetached=false`、`disposeRequested=false`，
  后台cleanup仍占已有最多8项retiring配额；不会因调用者超时释放原生handle。
- Rust诊断poll的`-4`改为非终态：超过5秒仍保留request/slot/token。Dart降低轮询
  频率继续等待实际callback，调用者期限由owner控制。没有MDK取消/排空回执时，
  不再删除请求并允许新snapshot。真实C ABI夹具原行为确实允许第二请求，回归先红
  后绿，覆盖迟到callback交付、消费和此后的新请求。
- textureSize的最后一次await后补关闭检查，防止release之后迟到open重新注册trace。
- 首个串行候选改变了静态暂停顺序：Portable原先在调用setPaused后立即refresh，
  排队时底层pause尚未提交。生产gate+Portable调用路径回归确实红，记录到
  `session.refresh`抢在阻塞snapshot之前。最终新增`onRequested`：
  PlaybackConfirmation在native request成功返回后执行hook；Portable先确认旧owner
  仍有效才刷新同一encoder。状态确认和hook以all-settled方式结束，提交失败不刷新，
  同步/异步hook失败也不提前释放仍运行的查询。已暂停候选reattach沿用同一路径。

操作边界5项测试覆盖snapshot→pause串行、调用者超时后仍占用、close拒绝排队/新操作、
原错误传播和队列上限。Rust槽位回归、Portable抢跑回归均有原始红日志：
`/tmp/connect-snapshot-admission-red.log`、`/tmp/connect-snapshot-refresh-red.log`；
边界直通语义的4项失败保留在`/tmp/connect-snapshot-operations-red.log`，不是MDK崩溃
复现。最终完整Bridge Dart123项、Rust17项通过，完整App275项86秒通过；
Bridge all-target严格clippy、fmt和严格Dart分析通过（修正一处测试大括号lint后复跑）。
只读review发现上述refresh回归并复核最终修复，未发现新的可证问题。

真实Android沿用双API36 AVD、576×1280、请求60fps/8Mbps、AMediaCodec和严格
首像素1000ms/输入P50 200ms/P95 300ms门槛：

| 运行 | 已完成循环 | 首像素ms | 输入P50/P95 ms | 结论 |
| --- | --- | --- | --- | --- |
| 原普通fvp公开snapshot，动态 | 30次暂停恢复、2次输入 | 2839 | 1240 / 1737 | 无崩溃，严格exit1 |
| 串行初候选，动态（提交hook修复前） | 30次暂停恢复、2次输入 | 2437 | 1229 / 1854 | 仅中间证据，严格exit1 |
| 最终普通snapshot，静态 | 10次暂停恢复、2次输入 | 1269 | 232 / 294 | 全部新像素/呈现/停止/清理完成，严格exit1 |
| 最终动态trace，200次串行snapshot | 10次暂停恢复、2次输入 | 2659 | 1234 / 1455 | 同PTS/新像素/呈现/停止/清理完成，严格exit1 |

静态组暂停146–295ms、恢复至新像素316–550ms，实际Flutter图案12；运行与主机App
测试有时间重叠，不能用于性能差异归因。动态两组图案0及fixture卸载确认完成。
原始目录`/tmp/connect-e2e/video-snapshot-lifecycle-{baseline,candidate}/`和
`/tmp/connect-e2e/video-snapshot-static-verified/`，同名`/tmp/connect-video-*.log`。
这些有限次数无崩溃不证明历史原生问题已解决。
最终动态组200次串行截图4319ms，暂停175–294ms、恢复至新像素451–618ms；
`frameCorrelationComplete=true`、Flutter图案12及fixture卸载均确认，截图已目视。
原件`/tmp/connect-e2e/video-snapshot-trace-verified/`；保留所有慢样本，未降低门槛。

复跑沿用上一节命令：ROUNDS=1、TRANSITIONS=2、PAUSE_CYCLES=10，codec=h264、
encoder=c2.android.avc.encoder、TRACE_FRAMES=false、MOTION=false。动态诊断压力
另设MOTION=true、TRACE_FRAMES=true、SNAPSHOT_STRESS=200；保持严格预算不变。
调用者Future完成只是结果交付证据，不能证明闭源MDK worker已完成所有收尾。
永久无callback时保留有界退役资源并报告未释放，不能凭超时伪造nativeDeleteConfirmed。

既有目标trace额外按进程累计CPU：media.swcodec6592.332ms、动态图案夹具2270.984ms、
SurfaceFlinger2202.809ms、ranchu composer1618.948ms、捕获进程370.357ms。
此为同一8秒记录中的线程运行时间合计，包含真实采集、合成和编码负载，非各进程的
墙钟时延；不据此将所有动态等待归因于ADB，也不通过削弱动态图案来宣称优化成功。


最终再跑真实ADB EOF视频恢复，17秒exit0：3534ms恢复到新session，真实Flutter
计数0→1，主动停止后不重建，代理接受2次/切断1次，fixture卸载、Settings恢复及
代理退出全部确认。证明新的截图/释放顺序仍能完成可控EOF后恢复；不外推物理
无线切网或小时级长稳。证据`/tmp/connect-e2e/video-snapshot-recovery-verified/`、
`/tmp/connect-video-snapshot-recovery-verified.log`，恢复截图已由图案断言验收。


普通main恢复：构建14.1秒/安装569ms，实际热重载125ms成功、无Dart运行错误，
设备首页与恢复后VIDEO1已目视后detach。SurfaceSync1000ms启动告警仍在，未计
启动流畅度通过。Gradle停止后清理395项明确Android debug输出及本批Rust测试
可执行文件，释放1670.1MiB、空闲51.0GiB；保留release、native hooks/Rust/Gradle/
CMake/Flutter有效缓存及全部原始证据。记录`/tmp/connect-snapshot-cleanup.json`。
目标无捕获进程/fixture，逐一确认本批6个session捕获JAR不存在；两个JAR摘要未变。


## fvp失败截图结果与仓库内补丁（2026-10-18）

延续前批NULL结果调查，已校验官方pub归档摘要并引入仓库内fvp0.39.1源码补丁。
仅五份MdkSnapshot源副本同步增加空结果判断，原Dart处理仍把空Uint8List完成为null；
不修改本机pub缓存、不引入新的Android呈现代码、不重建scrcpy JAR。路径依赖由根
pubspec统一覆盖，来源／许可证／归档SHA及SDK边界保留在
[CONNECT_PATCHES.md](../../third_party/fvp/CONNECT_PATCHES.md)。

可执行的真实源边界红绿命令（宿主C++20与Dart，不包含MDK renderer）：

```sh
python3 tool/fvp_snapshot_regression.py --package-root /tmp/connect-fvp-official-0.39.1
python3 tool/fvp_snapshot_regression.py
```

原版实际SIGSEGV（内部exit-11、脚本exit1）；修补后检查未知handle拒绝、空结果一次
完成、48字节含stride缓冲按原行为投递，exit0。再经动态库进入真实Dart VM，以
NativeApi.postCObject与ReceivePort确认空和填充Uint8List交付，不只测试C++假接收器。
原始日志`/tmp/connect-fvp-fork-regression-{red,green}.log`。全仓严格Dart分析无问题，
`pub get --enforce-lockfile`通过。只读review未发现额外可证问题。

实际Android CMake compilation input为仓库vendor callbacks.cpp；本批APK中的
libfvp.so SHA为`e4b997e9e27ae5116a0bacf219acb338c981fa29b7d2ead13b0dae8bfd653bae`，
libmdk.so仍为`72e5f6370f98a3a09755004a0c6be1c01d688c79d7b1f0a5cce3a2e7d49c8ad3`。
复用现有SDK归档并校验`70d9dffb289a26054567e51088786af730bb1ffc46bffdf2f09e10d7ebf7b012`，
本次构建通过环境FVP_DEPS_SHA256固定；并非已解决所有生产构建的SDK锁定。更换
插件源码路径后的首次assembleDebug43.9秒，未重新下载SDK或构建JAR。

仍为相同双AVD、1280/60/8Mbps、H264及AMediaCodec，实际576×1280：

| 普通公开snapshot路径 | 静态 | 持续动态 |
| --- | ---: | ---: |
| 首像素ms | 1469 | 2901 |
| 两次输入新像素ms（样本量2） | 188 / 381 | 1377 / 1319 |
| 串行压力截图 | 无额外压力 | 200次，4447ms |
| 暂停／恢复及新像素 | 10次完成 | 10次完成 |
| 实际Flutter最终计数 | 12 | 12 |
| 停止／texture分离／卸载 | 完成 | 完成 |
| 1000／200／300严格总门槛 | exit1失败 | exit1失败 |

结果及截图在`/tmp/connect-e2e/video-fvp-fork-{static,dynamic}/`，日志在
`/tmp/connect-video-fvp-fork-{static,dynamic}.log`。动态命令误用了不存在的
CONNECT_PERF_TRACE，真正开关为CONNECT_PERF_TRACE_FRAMES，实际回执
nativeFrameTrace=false；这批证明普通公开snapshot压力链路，不声称trace／同PTS
分段通过。不把无崩溃的一次短测试称历史MDK空std::function已修好，也不据此
声称首帧或稳态延迟有收益。每组仅两次输入不是生产P95分布。

同版本真实TCP EOF／正式页面自动恢复17秒exit0：3521ms出现新session，Flutter
图案0→1；主动停止后无重建，代理accept2次／切断1次，夹具卸载／代理关闭／
设置恢复均确认。证据`/tmp/connect-e2e/video-fvp-fork-recovery/`和
`/tmp/connect-video-fvp-fork-recovery.log`。仍不包括真实配对无线切网、半开新场景或
小时级长稳。NULL补丁只关闭依赖可证明的失败处理缺口，首帧／动态源年龄及
原MDK renderer内部空回调继续开放。


本批完整Bridge Dart123项通过，静态与动态Flutter图案12均已目视。恢复普通main
时发生实验宿主故障：assembleDebug最终611.3秒完成，但安装时报emulator-5554
不存在。内核09:17:25 OOM记录明确杀死目标QEMU6377，anon-rss9558884kB；
主控emulator日志随后报告signal11。两AVD均退出，不能将其记为App原生崩溃或
依据时间相近推断唯一因果。前述E2E在09:06前已结束且清理确认，原证据保留。
已停止Gradle，仅冷启主控AVD恢复普通App，不为环境重启重新构建JAR；后续
持续试验需监测宿主可用内存和AVD RSS，不在内存压力期间做性能归因。


普通main最终以已构建APK复用安装1584ms、热重载成功、无Dart错误，设备首页已
目视后detach。代码提交`7cbf010`。已按前批明确debug路径清单清理394项本批输出，
移除1484.6MiB、空闲50.4GiB；release／有效Gradle／CMake／Rust／native hooks／
SDK／Flutter哈希缓存及所有证据保留。目标AVD保持关闭，下一轮需重新启动并恢复
25556转发，先监测宿主／AVD RSS；不能将新冷启AVD与旧长寿命AVD直接作优化归因。

新增独立首帧研究候选见[重复编码器分配](../research/scrcpy-first-frame-performance.md#暂停补丁的正常首启重复分配候选2026-10-18)：
现有暂停补丁使正常首启create／release／create，先在同一JAR量化，再决定是否
调整暂停门及重建补丁JAR；尚无收益证据，不能解释关键帧后输出等待和稳态源年龄。
本批两JAR均不变。


## 首个验证画面的观测与隔离对照（2026-10-18）

生产播放器、码率与严格预算保持不变，两个scrcpy JAR均未修改或重建。目标AVD因上一批
宿主OOM后重新启动；本批先记录内存，再在同一目标生命周期完成下列五组，每组3轮、
每轮2次正常输入及1次暂停恢复。请求1280/60/8Mbps，实际576×1280/H264/AMediaCodec，
静态计数器夹具，trace开启，ADB burst关闭。不能和旧目标AVD直接比较归因。

入口在`outputs.start`返回后、64×64图案检查覆盖指标之前，保存第一次32×32验证截图
对应的native trace，并以Dart启动Stopwatch包围指标读取。独立review发现旧位置让
`startToDecodedMs`包含本次读取的2–6ms；最终代码先记录计时，再读指标。为公平比较，
下表全部用已保留的`startupFrameTrace.watchBeforeUs // 1000`，原始JSON未改写。

| 设置／顺序 | 读取前启动到可读像素ms（3轮） | 输出verified ms | 同PTS onVideo→32×32回调µs | 6次正常输入P50/P95 ms |
| --- | --- | --- | --- | --- |
| A0 默认 | 1318 / 1221 / 1111 | 712 / 444 / 439 | 289236 / 290804 / 330370 | 182 / 310 |
| B1 buffer_frames=1 | 1043 / 1076 / 1053 | 426 / 407 / 397 | 220106 / 258636 / 257820 | 212 / 226 |
| A1 恢复默认 | 1144 / 1147 / 1155 | 477 / 435 / 484 | 249249 / 287710 / 374063 | 194 / 306 |
| 单独请求profiler.gpu=0 | 1199 / 1126 / 1137 | 484 / 503 / 466 | 212783 / 324597 / 324908 | 235 / 329 |
| B2 buffer_frames=1复跑 | 1137 / 1122 / 1032 | 427 / 415 / 398 | 232843 / 230423 / 246877 | 211 / 261 |

五组全部因原1000/200/300预算exit1，不能算性能通过。共15次会话、30次正常新像素、
15次暂停恢复、Texture实际图案、停止／分离／夹具卸载完成。首轮A0有较大的主控首次
解码开销，不能把它与B1的差别全算作buffer设置收益；buffer1短组输出较小，但两次
输入P50均超过200ms，且全局设置会影响其他播放器，因此不保留产品默认改动。
B1曾临时在生产初始化处设置，随后按原字节恢复；B2使用最终隔离测试入口复现。
GPU参数仅记录requested，未读回SDK内部状态；本组没有显示收益，也不改产品配置。

**时钟与像素边界。** native事件E的Dart启动时刻条件括界为：

```text
[watchBeforeUs + E.elapsedUs - metrics.nowElapsedUs,
 watchAfterUs  + E.elapsedUs - metrics.nowElapsedUs]
```

同PTS回调差使用同一个native时钟，无须取跨时钟中点。onVideo观测在prepare及texture
之后才注册，是首次已观测回调，不能宣称最早解码时刻。该段包含调度、渲染、fence和
readback，不能称纯GPU或面板延迟，也不能从回调数量推断队列深度。B1首轮截图PTS为
0.033333，必须匹配它对应的回调，不能错用首个PTS0。本批各首截图对应PTS在保留窗口
均仅一项，但未来重复PTS仍须识别，不能默认唯一。32×32验证成功说明像素数据可读；
实际计数器内容由随后64×64断言及Flutter截图共同验证，不能单用trace证明内容正确。

复现公共命令（已有fixture APK、目标TCP转发25556；debug控制端与隔离测试adbd）：

```bash
cd apps/connect
PATH=/home/xiankq/.cargo/bin:/home/xiankq/flutter/bin:/usr/local/bin:/usr/bin:/bin \
ANDROID_HOME=/home/xiankq/Android/Sdk CARGO_BUILD_JOBS=2 \
FVP_DEPS_SHA256=70d9dffb289a26054567e51088786af730bb1ffc46bffdf2f09e10d7ebf7b012 \
CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
CONNECT_E2E_TARGET=emulator-5556 CONNECT_E2E_DEVICE=emulator-5554 \
CONNECT_E2E_VIDEO_FIXTURE=/tmp/connect-video-fixture/video-fixture.apk \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/video-startup-observed-baseline \
flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/video_performance.dart \
  --target=integration_test/video_performance_test.dart \
  --dart-define=CONNECT_PERF_DECODER=native \
  --dart-define=CONNECT_PERF_ADB_BURST=false \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 --dart-define=CONNECT_E2E_PORT=25556 \
  --dart-define=CONNECT_PERF_MAX_SIZE=1280 --dart-define=CONNECT_PERF_MAX_FPS=60 \
  --dart-define=CONNECT_PERF_BIT_RATE=8000000 --dart-define=CONNECT_PERF_ROUNDS=3 \
  --dart-define=CONNECT_PERF_TRANSITIONS=2 --dart-define=CONNECT_PERF_PAUSE_CYCLES=1 \
  --dart-define=CONNECT_PERF_MAX_START_MS=1000 --dart-define=CONNECT_PERF_MAX_P50_MS=200 \
  --dart-define=CONNECT_PERF_MAX_P95_MS=300 --dart-define=CONNECT_PERF_TRACE_FRAMES=true
```

单独对照追加`CONNECT_PERF_GPU_PROFILER=0`或`CONNECT_PERF_RENDER_BUFFER_FRAMES=1`
的`--dart-define`，并更换capture目录；两项默认值-1／0均不覆盖SDK配置，进程隔离，
不是用户设置或会话级全局竞争入口。B1历史临时补丁不必恢复，B2才是最终可复现方式。
严格分析无问题，指定文件format及diff检查通过；生产代码未改，未重复全仓测试。

原始证据：`/tmp/connect-e2e/`下`video-startup-observed-baseline`、
`video-startup-buffer-one`、`video-startup-observed-return`、
`video-startup-gpu-profiler-off`、`video-startup-buffer-one-repeat`，各有result、PNG和
cleanup。汇总`/tmp/connect-startup-observed-summary.json`；对应宿主drive日志为
`/tmp/connect-<目录名>.log`。A0实际Flutter VIDEO3图案已目视。

主控main已恢复、热重载成功、Dart无运行错误，设备首页已目视并detach；启动
Skipped34frames／SurfaceSync1000ms仍开放。15个session捕获JAR逐一确认不存在、
目标无捕获进程，再正常关闭目标AVD释放内存；主控保留首页。停止Gradle后按已有
精确清单清理394项debug输出1484.6MiB，空闲50.0GiB；release、有效编译缓存和原始
证据保留。清理记录`/tmp/connect-startup-observed-cleanup.json`及
`/tmp/connect-startup-observed-target-cleanup.json`，资源记录
`/tmp/connect-codec-allocation-resources.jsonl`。后续双机测量须重启目标并恢复TCP转发。


## 截图提交时间与测试帧调度边界（2026-10-18）

保留的代码为native trace成功snapshot元数据增加`submittedElapsedUs`：请求登记后、
调用MDK API前取同一native单调时钟，回调已有`elapsedUs`不变。它不是跨设备时间，
也不等于精确GPU开始时间。真实C ABI测试断言提交在调用前后观测括界内、提交≤回调
≤读取时刻；完整Bridge Rust17项／严格all-target clippy／fmt通过。测试回执另增加
binding及framePolicy名称，保留原默认策略。最终指定Dart分析／format通过。

**四组诊断均显式改为fullyLive，不能混入原默认基线。** 每组3轮，1280/60/8Mbps、
实际576×1280 H264/AMediaCodec、trace开启，严格1000/200/300预算未变。第一候选
仅提前挂载Texture，通过临时allocated事件驱动ValueNotifier；第二候选恢复挂载时机，
仅等首次已观测decode再snapshot（5ms轮询，4秒界限）。这两项都没有删除播放确认、
32×32有效像素或64×64计数器断言，均已按原字节撤回，不进入产品默认。

| 持续框架绘制负载实验 | 全启动可读像素ms | 输出verified ms | snapshot登记→回调ms | 正常输入P50/P95 ms |
| --- | --- | --- | --- | --- |
| A 默认调用顺序 | 2657 / 1287 / 1259 | 624 / 475 / 481 | 422.345 / 404.473 / 404.680 | 265 / 378 |
| 提前挂载Texture | 1896 / 1325 / 1442 | 693 / 548 / 548 | 496.300 / 515.732 / 531.538 | 311 / 471 |
| 等decode再snapshot | 2008 / 1334 / 1214 | 614 / 508 / 451 | 158.638 / 270.459 / 206.414 | 281 / 452 |
| 恢复默认顺序＋Perfetto | 1888 / 1337 / 1364 | 597 / 467 / 545 | 381.156 / 442.805 / 501.071 | 319 / 391 |

所有命令exit1，12会话／24次正常新像素／12次暂停恢复、真实Texture图案3/6/9、
停止分离及夹具卸载完成。提前挂载三轮`textureMountedWhenReady=true`，其余为false；
不是一个未真正挂载的空实验。A的请求登记早于对应decode约60/166/85ms，因此不能
把该组数百毫秒差解释为Dart迟交请求。等待decode使请求区间变短，但把等待移到了
提交之前，完整输出没有稳定改善；不将分段数字缩短冒充首帧收益。首轮目标冷开销
较大，末组有采集开销，三次短样本均不支撑因果优化结论。

原始结果位于`/tmp/connect-e2e/video-early-texture-baseline`、
`video-early-texture-attached`、`video-snapshot-after-decode`、`video-early-texture-return`。
宿主日志为`/tmp/connect-<目录名>.log`。复现请求参数沿用上一节公共命令，临时实验
源存`/tmp/connect-early-texture-test.candidate.dart`及
`/tmp/connect-early-texture-player.candidate.dart`；共同设置fullyLive，分别追加
`CONNECT_PERF_ATTACH_EARLY=true`或`CONNECT_PERF_WAIT_DECODE=true`的dart-define。
这些候选不在当前生产代码；不能只传flag就声称重现。用于历史核验的原始源码备份
另有`*.before.dart`，勿覆盖后续改动。临时汇总脚本
`/tmp/connect-summarize-startup-submission.py`逐次要求唯一同PTS并检查时间顺序。

**发现测试调度会改变负载。** Flutter3.47.6默认Live策略fadePointers会在无显式pump
等条件时跳过框架帧；fullyLive则放行。Live.handleDrawFrame在非pump／非benchmark时
又无条件scheduleFrame，形成持续框架帧循环；benchmarkLive也不消除该循环。
另一方面，当前SurfaceTexture会请求重建框架场景，原默认异步阶段又可能抑制实际
视频消费。因此默认与fullyLive都不能直接叫正常产品等效：原结果仍是实际readback
及阶段性Texture检查，但缺持续呈现负载证明，不能凭它关闭产品延迟验收。
[一手源码核对](../research/scrcpy-first-frame-performance.md#flutter测试帧策略与产品呈现边界2026-10-18)。

末组controller Perfetto长14.808651秒，PID7513 raster CPU6558.009ms，两个
JNISurfaceTextu线程795.436＋1440.490ms；整窗eglSwapBuffers约656次，视频Surface
约147次dequeue，trace无data-loss。不同SQL对dur>0的过滤会少计一个未完成/零时长
swap，不能混成严格逐帧对应。此处是强制框架绘制负载证据，不能把6.558秒全算正常
视频或首次snapshot的300ms。trace与采集日志在末组目录，SQL摘要保留
`/tmp/connect-controller-startup-{cpu,slices,surface-slices}.csv`。未加入无效的全局优化。

**普通产品页另验。** 恢复main后热重载成功、Dart无运行错误；通过真实UI手动TCP
表单添加隔离AVD、进入设备页及全屏远控。临时fixture显示0→1→2，变更由目标侧
ADB keyevent触发，主控截图0和2已目视；这不是输入往返延迟测试。保持正常
WidgetsFlutterBinding，在静态计数2阶段另采15秒trace：实际14.850150秒，PID7875
raster CPU378.232ms／6次swap，视频Surface59.458ms／11次swap，trace无data-loss。
已有产品偏好、实际576×1280，不宣称与上表逐参数/启动阶段一致；正常静态和强制
绘制试验不能直接相除当优化收益。第一次后台采集启动器退出导致录制进程已消失、
设备仅0字节文件，明确不计证据；确认终态后保持启动器存活重采成功并移除两份远端
临时文件。原件、SQL摘要、截图和清理记录均在`/tmp/connect-product-rendering/`。

代码提交`f4db3b6`。后续必须建立正常binding下、保留真实像素与Texture呈现的启动/
输入测量入口，再判断主控优化收益，不能通过切换测试帧策略制造性能通过。目标编码
积压及历史MDK worker崩溃继续开放。应用层失活亦须另验：已有TCP keepalive及
USER_TIMEOUT覆盖网络黑洞，但内核仍ACK而adbd不处理请求不触发此机制，当前可显式
断开再连；不重复实现已存在的TCP检测，也不把静止视频视为失活。

普通App临时设备记录已通过页面移除、首页目视，额外fixture已卸载。12个session的
JAR逐项确认不存在，匹配捕获JAR与捕获进程均为空；证明
`/tmp/connect-early-texture-target-cleanup.json`。两个scrcpy JAR摘要不变、未重建。
主控AVD RSS升至8846412KiB后不继续堆测，detach、停止Gradle、正常关闭两台AVD；
精确清理394项debug输出1484.6MiB，空闲49.6GiB，保留release／有效缓存／原始证据。
资源及清理记录`/tmp/connect-early-texture-resources.jsonl`、
`/tmp/connect-early-texture-cleanup.json`，当前无在线AVD，下轮需冷启并恢复25556转发。

## 普通调度基准与解码路径对照（2026-10-18）

`afa4943`新增独立开发入口`apps/connect/benchmark/live_video_performance.dart`及host
`test_driver/live_video_performance.dart`，不改普通产品入口或既有集成门禁。入口先调用
`enableFlutterDriverExtension`构造`_DriverBinding`；它使用普通Scheduler／Renderer／
Widgets混入，没有Live测试绑定的draw/pump循环，回执记录实际binding和模式。
它仍有Driver服务扩展和测试messenger，不将其类名写成`WidgetsFlutterBinding`，
也不把此debug基准等同于完整产品UI、profile或release。

连接、捕获、媒体、输入和暂停走真实Rust ADB／PortableVideoOutputs／FvpVideoPlayer／
VideoPresentation。Flutter只在Texture分配和移除时更新widget；视频不逐帧setState。
每次真实按键后，先等待64×64 snapshot识别新的4 bit计数，再由host经ADB截取主控
实际窗口PNG，传回App按Texture实际矩形验证。窗口抓取在输入计时之外，不调用
`RepaintBoundary.toImage`、WidgetTester pump或主动重画Texture；允许最多3秒／8次
实际窗口检查，旧计数不能通过。它测量输入到解码像素可读上界，窗口检查是另外的
正确性要求，仍非逐帧面板扫描延迟。实际截图也会消耗资源，不能称基准零干扰。

与前批相同双API36 x64 AVD、Flutter3.47.6 debug、H264／1280／60fps／8Mbps、
burst关闭、原生trace开启。严格门槛保持首帧≤1000ms、输入P50≤200ms／P95≤300ms。
首帧从`session.start`前到真实首像素验证后读取，不含Flutter进程启动及此前的
`devices.connect`；另存core、output和首次widget帧耗时。输入样本不剔除冷操作。

| 路径／每组3会话 | 输入数 | 首帧 ms | 输入P50／P95 ms | 严格结果 |
| --- | ---: | --- | --- | --- |
| 原生首次运行 | 6 | 1564 / 1108 / 1139 | 268 / 481 | 失败，另有清理错误 |
| 原生修正后复测 | 6 | 979 / 1168 / 1146 | 303 / 449 | 失败 |
| FFmpeg slice初测 | 6 | 837 / 908 / 890 | 85 / 231 | 通过 |
| FFmpeg slice扩量 | 60 | 947 / 837 / 886 | 108 / 153 | 通过 |
| 原生扩量 | 60 | 1184 / 1148 / 1196 | 256 / 359 | 失败 |

原生必须收到实际`decoder.video=AMediaCodec`，软件必须收到`FFmpeg`；候选列表不当
运行证据。两个扩量组共132次实际窗口检查、6次暂停恢复、6次停止纹理分离及自动
fixture／设备记录清理均完成。原生输出首帧仍慢，不能把软件通过写成产品默认路径
已经达标；本批没有改变生产解码优先级。AVD的goldfish MediaCodec路径不是实体
手机硬解，高分辨率动态内容的吞吐、功耗、热和真实无线仍待验证。

同PTS匹配relay与native回调，并以共享Rust单调时钟计算：

| 扩量段，60次 | 原生 min／median／max ms | 软件 min／median／max ms |
| --- | --- | --- |
| relay开始write→onVideo | 69.078 / 134.373 / 218.592 | 0.552 / 1.414 / 14.198 |
| onVideo→相同PTS snapshot回调 | 13.073 / 42.870 / 174.428 | 6.630 / 32.678 / 132.675 |

第一段含socket消费、demux、decoder输入输出和原生图像获取，不叫纯解码时间；第二段
含请求时机、调度、渲染和读回，不叫纯GPU时间。小样本先用了`writtenUs`；消费者可
在write Future完成前已收到包，扩量统一从`writeStartedUs`描述该边界，不删除负值
以制造收益。控制回执两组通常1ms、最大3ms／2ms；继续定位平台播放器路径。

首次运行误用`devices.remove`，`deviceRemoved=false`；原失败结果完整保留。之后
改用真实`devices.forget`，反查列表确认没有本轮记录；数据目录与普通产品分开，
残留记录默认阻止新测，仅显式`CONNECT_PERF_RECOVER_RECORDS=true`才清理本基准
目录。原生复测显式开启该选项时实际既有记录数0，不宣称执行了旧记录恢复。
首次释放未确认状态在远端await前保存，不能被重试的空输出列表洗成成功；启动失败
保守保留未确认。host超时不等于App操作取消，清理会排在实际操作后、拒绝新业务。
公开SDK仍不能确认原生delete完成，`nativeDeleteConfirmed=false`保持原义。

host进程超时先TERM再必要的KILL、确认退出并有界排空管道。安装前保存尝试状态；
结果未知时有界查询，只在白名单包路径且安装APK与本轮fixture字节完全一致时认领
卸载，未知结果仍使验收失败。三个/tmp宿主探针通过：忽略TERM、安装已提交但回执
卡死后同APK清理、不同APK拒绝删除。这不是目标设备断网或Android安装事务可取消
的证明；超出15秒恢复窗口仍按未知失败。App清理并发与释放分支另经只读复核。

复现：专用双AVD启动、目标tcpip5555和宿主25556转发建立，构建独立fixture后，在
apps/connect运行（ADB与APK为测试宿主工具，不进入产品分发）：

```sh
CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
CONNECT_E2E_VIDEO_FIXTURE=/tmp/connect-video-fixture/video-fixture.apk \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/video-normal-binding-native-60 \
FVP_DEPS_SHA256=70d9dffb289a26054567e51088786af730bb1ffc46bffdf2f09e10d7ebf7b012 \
flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/live_video_performance.dart \
  --target=benchmark/live_video_performance.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=25556 \
  --dart-define=CONNECT_PERF_DECODER=native \
  --dart-define=CONNECT_PERF_ROUNDS=3 \
  --dart-define=CONNECT_PERF_TRANSITIONS=20 \
  --dart-define=CONNECT_PERF_MAX_SIZE=1280 \
  --dart-define=CONNECT_PERF_MAX_FPS=60 \
  --dart-define=CONNECT_PERF_BIT_RATE=8000000 \
  --dart-define=CONNECT_PERF_MAX_START_MS=1000 \
  --dart-define=CONNECT_PERF_MAX_P50_MS=200 \
  --dart-define=CONNECT_PERF_MAX_P95_MS=300 \
  --dart-define=CONNECT_PERF_TRACE_FRAMES=true
```

仅将decoder改成`software`、证据目录改成新目录即可对照；`default`使用正式候选优先级。
每次必须使用新证据目录以保留失败数据。本入口固定burst关闭、每轮一次暂停恢复，
不支持旧集成入口的PAUSE_CYCLES等参数。上述五组原始结果分别为
`/tmp/connect-e2e/video-normal-binding-{baseline,final,software,software-60,native-60}/`，
对应`/tmp/connect-video-normal-binding-<组名>.log`。每组有逐命令progress、实际PNG、
result及cleanup；不是仓库版本资产。

完整workspace严格Dart分析通过。普通main恢复构建25.5秒／安装588ms，工具热重载
169ms成功、无Dart运行错误，设备首页已目视后detach；启动Skipped34frames与
SurfaceSync1000ms告警仍在，不计流畅度通过。代表原生新图案VIDEO9也已目视。
15个已知session JAR逐项确认不存在，另查捕获JAR／进程与fixture均为空，证明保留
`/tmp/connect-normal-binding-{session-cleanup,target-cleanup}.json`。两个scrcpy JAR
摘要与前批一致，未构建服务端。停止Gradle并正常关闭两台AVD，按已有精确清单清理
394项debug输出1484.9MiB，空闲48.74GiB；保留release、有效Flutter／Rust／Gradle／
CMake／SDK缓存及原始证据，记录`/tmp/connect-normal-binding-cleanup.json`。


## 应用失活恢复与解码路径辨认（2026-10-18）

代码`8c55b84`补齐TCP正常但adbd不再响应时的空闲探测与既有重连。10秒无入站
读取进展后异步OPEN sync:，3秒期限、连续两次无进展才关闭精确旧Client；活动和
主动替换会取消旧探针。独立review发现完整帧计数误断合法慢大帧，真实回归先红，
现按每个非空header／payload读取批次记录进展，原协议校验和trace计时边界保留。
[行为、所有权、测试与限制](connection-health.md)。

3项公开Runtime真实TLS回归宿主及Android普通shell均通过，完整ADB72／Core169项
通过，另13／49项ignored；clippy、fmt、Core iOS／macOS／Windows交叉check通过。
它们不替代实际adbd故障、真实无线切网、视频活动恢复或小时级长稳。普通main已
实际连接AVD、全屏进入Settings并触控Network页、悬浮退出，热重载133ms成功，
无Dart错误；启动长帧告警保留，不能称严格首帧达标。

同一默认播放路径的LLDB回执已把AImageReader窗口、MediaCodec成功配置及该reader
的成功异步latest acquire按指针关联；实际已经启用异步图像获取，不再重复该调参
候选。[探针原始证据与回调错误边界](../research/scrcpy-first-frame-performance.md#实际aimagereader异步路径确认2026-10-18)。
不从调试器期间的首帧推导收益，继续拆解原生输入／输出和图像获取等待；默认播放
策略和JAR均未修改。本任务及整体目标保持开放。


## Android显式异步输出（2026-10-18）

`53bcf10`补实际系统时钟的onVideo标记及保守离线配对，`24379bb`将Android默认
首选改为AMediaCodec:async=1。同参数A/B/A的输入P50/P95为277/392→153/204→273/389ms，
workDone→onVideo中位147.174→20.841→133.510ms；每组30/30输入系统标记关联。
显式选项有真实async成功日志／467次输出callback；此前AImage异步acquire不是
codec异步证明。未猜测固定SDK缺省选择的内部原因，未改JAR。

最终共享default配置、关闭诊断，60次输入138/295ms通过200/300ms预算，首帧
1197/1157/1122ms仍未过1000，完整严格exit1。66次实际窗口检查、3次暂停恢复／
释放和清理完成；真实RemotePage五编码功能通过，不能当五编码延迟或物理ARM证明。
[完整场景、失败、命令、源码与原始证据](android-decoder-async.md)。

Python分析器独立review发现跨会话误配、重复decoded及错身份统计，4项实际红后
修复并8项全绿；不把不完整覆盖伪装成有效配对。首个新marker运行的PTS唯一性失败
保留，清理后才重测。Bridge19项Rust／123项Flutter、严格分析和clippy／fmt通过。
首帧、真实无线、物理硬解／profile／热及长稳均继续开放，完整目标未完成。

## 冷启动清理往返与首次绘制（2026-10-18）

`15c8919`把冷编码器枚举和正常JAR清理合为一次shell，保留原退出码及失败／取消
的owned fallback。真实wire边界和实际shell先红后绿，Core lib61 passed／2 ignored，
clippy／fmt及Core三未来端交叉check通过。A/B/A validated中位354→269→311ms，存在
样本重叠，不承诺固定收益。最终关闭追踪60输入148/221ms通过输入预算，首帧
1142/1064/1000ms仍失败；66次真实窗口及暂停／释放／清理完成。

Perfetto与原生栈把首次输出额外开销缩至renderer／模拟器图形代理初始化；首窗口
27个栈样本不足以断言宿主shader编译耗时或真机瓶颈。服务端与JAR未改、未重建。
[完整对照、清理边界、CPU观测、签名产物和下一步候选](video-cold-start.md)。


默认主屏直启后续（2026-10-18，`f331dfd`）：精确连接 catalog.peek 不启动探测也不等
进行中的初始化；默认主屏／有效 H264／未指定编码器在目录未知时直接尝试实际捕获，
已有不支持目录仍拒绝，其他 codec／named encoder／独立应用仍严格预检。未知能力
没有改成 available，质量选项仍实际枚举。真实首个 SEND 红回归先失败后通过，完整
Core180 passed／49 ignored；另真实 Android app-launch／unknown 四项通过，clippy／
fmt 及 Core iOS／macOS／Windows check 通过，不等于未来端 Flutter 整包通过。

同参数直启→强制枚举→返回直启三组首帧为1102/927/782→1044/1041/1070→896/935/941ms。
首组1102ms失败保留。最终正式default关闭追踪，3轮60次输入严格通过：首像素
903/877/875ms、P50/P95=147/225ms，66次真实窗口与暂停恢复／释放／清理完成。
双API36 x64 AVD／debug结果，不是物理ARM／Wi-Fi／持续60fps或面板延迟证明。

原样正式 RemotePage 五编码23秒通过，实际像素、Texture、原生截图、悬浮退出、
暂停／停止清理断言均保留。首跑47秒像素超时仍保留；随后两次是已过首帧后截图
插件未注册，去掉 --no-pub 重新生成插件后通过，没有放宽断言。普通main全屏触控、
拖拽吸附退出也实际验证。两份JAR未改／未重建。完整证据与失败边界见
[冷启动记录](video-cold-start.md)。


## 最新普通调度持续动态图案复核（2026-10-18）

`f331dfd`／`dd334a3` 后先复核现状，不把旧 integration binding／同步 codec 的动态
结果直接视为当前默认值。双 API36 x64 AVD 冷启、SwiftShader、各3072MiB，普通
Driver、正式default（Android async codec），H2641280／60／8Mbps、burst关闭，
`CONNECT_E2E_VIDEO_MOTION=true`。无逐帧或系统追踪。未修改产品、预算、帧率或 JAR。

两次均未完成第一轮实际窗口检查，不能生成输入分布：

- `/tmp/connect-e2e/dynamic-normal-default/`：start请求3709ms完成，控制端
  `adb screencap` 在独立3秒窗口没有返回。host发送TERM、确认exit−15并有界排空；
  没有任何实际窗口PNG，不能把它叫Texture缺失或MDK截图原生崩溃。
- 同配置热重启后的 `dynamic-normal-default-r2/`：core1012ms、首像素2429ms，
  输出verified1399ms。真实控制端PNG约2289ms返回，但余下718ms不足以完成App内
  PNG验证，组合3秒门槛失败；未进入输入循环。保存PNG已目视为远端持续动态图案
  VIDEO0／166。实际呈现不等于本轮完整性能通过，2429ms已超过1000ms首帧预算。

两次App输出释放／设备移除、driver关闭、fixture卸载／缺席和最终目标截图均确认。
原始progress保留start响应与失败阶段；result不伪造P50／P95或完整round。相应日志
`/tmp/connect-dynamic-normal-default{-r2}-host.log` 与
`/tmp/connect-dynamic-normal-default-app.log`。失败保留，不抬高门槛求绿。

只读复核现有代码：WRTE消费后即ACK、run_video逐包转发，未发现可解释旧一秒等待
的新转发缺陷；此前303个源PTS／CCodec完成／host匹配和2vCPU runnable等待仍支持
优先看目标负载。不能由本轮不足的窗口数据算持续输入延迟，也不能把模拟器CPU
或宿主图形代理问题直接外推物理手机。下项独立验证实际adbd连接停止应用数据但
保持TCP打开时，当前失活检测与可见主屏自动恢复是否闭合。


独立连接验证已完成：`3771d44`在实际adbd旧连接保持TCP但双向discard、无注入EOF时，
两组正式RemotePage自动恢复新session／实际图案0→1（19850／19082ms），默认EOF
控制1603ms也通过。两个方向真实drop及controller先EOF、随后新accept均在cleanup
前核验；首组静态入站0的失败保留，后续只增加fixture画面挑战。并非物理Wi-Fi漫游
或长期稳定性。[故障边界、命令、回执与清理](connection-health.md#实际adbd与可见视频的应用停转故障2026-10-18)。
下一项先分开动态输入取样与慢窗口抓取，在诊断模式保留严格失败以取得当前分布；
没有本轮动态输入数据前，不从静态通过外推完整性能，也不重复盲调ADB缓冲。

后续 `6547f2c` 已取得当前分布：普通Driver可选原始实际窗口与强制失败的扩展诊断，
2→4→2目标vCPU三组各24输入，P50／P95为1866／2202、1584／1865、1793／2145ms，
全部严格失败；90次窗口计数与暂停恢复／清理完成，冷返回失败另保留。默认静态PNG
控制24输入严格通过，但不替代动态低延迟验收。本批未改生产策略或JAR。详见独立的
[高动态取样、资源对照与原件](video-dynamic-measurement.md)，本节“尚无分布”是当时
状态，当前完成度以该后续和权威状态页为准。SDK后续正式版本与snapshot修复的
[核查](../research/mdk-sdk-snapshot-followup.md)没有提供已验证的升级修复候选。


## 有界采集候选的首帧主控分段（2026-10-18）

`c1ec73e`为普通Driver补齐**首次32×32验证图片**的relay／onVideo／snapshot关联。
它不是最早解码回调或首次显示的证明；trace在prepare和texture创建后才注册，缺失
早期callback必须保留缺失。先保存该次snapshot metadata，待Texture自然挂载并记录
widgetFrameMs后才查询media.status，避免诊断查询推迟挂载或污染两项启动计时。
后续64×64新计数与真实窗口截图检查保持，未更改严格预算。

每次PTS只能唯一匹配一个decoded callback及一个relay包，允许既有1µs浮点截断。
PTS仅为帧身份，不当时钟。三段使用：

- relay→onVideo：clockOriginUs + decoded.elapsedUs − relay.writeStartedUs；
- onVideo→snapshot：snapshot.elapsedUs − decoded.elapsedUs；
- snapshot请求→回调：snapshot.elapsedUs − snapshot.submittedElapsedUs。

消费者可能先于write Future完成，因此不使用writtenUs代替writeStartedUs。
缺失、歧义、非有限PTS或时间倒序输出complete=false，不挑最近帧，不把缺失记成0。
三组定向测试及Dart分析通过；新增测试最初因helper尚未实现编译失败，不能把该失败
写成产品慢帧红测。只读review发现初始接入会推迟挂载，修正后才测r2；初始APK虽
构建／启动，但没有运行性能组，不能纳入结果。

保持同一34294a6a…有界候选JAR、两个API36 AVD各2vCPU／2048MB／SwiftShader、H264
1280／60／8Mbps、动态fixture、普通_DriverBinding、trace开启、每组1轮8次输入，
只切换default→software→default。default使用正式Android async=1优先级；实际
decoder.video分别AMediaCodec／FFmpeg／AMediaCodec。返回组直接重装同一份default
APK，无热重启重编译。所有setup字段及样本数逐项核对，计时前停止Gradle且没有并行构建。

| 观测 | default A1 | software B | default A2 |
| --- | ---: | ---: | ---: |
| Core累计关键帧ms | 2069 | 1411 | 1345 |
| output playing累计ms | 193 | 124 | 190 |
| output verified累计ms | 1772 | 451 | 1358 |
| 完整首像素ms | 3868 | 1878 | 2725 |
| 首验证帧relay→onVideo ms | 775.718 | 50.614 | 317.448 |
| 首验证帧onVideo→snapshot ms | 920.412 | 336.262 | 983.494 |
| 首snapshot请求→回调ms | 1553.208 | 318.887 | 1110.283 |
| 输入P50／P95 ms | 654／891 | 630／879 | 647／812 |
| 输入同帧relay→onVideo中位ms | 103.967 | 6.923 | 114.459 |
| 输入同帧onVideo→snapshot中位ms | 144.494 | 111.191 | 119.547 |
| 真实窗口有效／超过3秒 | 10／5 | 10／2 | 10／4 |

三组均完成暂停／新像素恢复／停止、App清理和独立fixture卸载；严格exit1，
videoPerformanceComplete=false。源图案每个窗口计数正确，各组一张实际原始RGBA
无损转PNG作目视检查；不是同一动画帧的画质对照。原件：
`/tmp/connect-e2e/first-frame-stages/`、`first-frame-stages-software/`、
`first-frame-stages-default-return/`，匹配回执`/tmp/connect-first-frame-stages-aba.json`。
实际测量APK保留在`/tmp/connect-artifacts/first-frame-stages-r2-debug.apk`和
`first-frame-stages-software-debug.apk`，均验证native库内完整候选JAR字节，未重建JAR。

**结论与下一项：**软件后端在本次AVD上缩短解码及首帧图像交付等待，但稳定输入
没有相应端到端改善。不能把onVideo→snapshot全算成GPU工作，也不能将各阶段中位
相加解释完整输入。首snapshot提交早于所配onVideo，排除了Dart等decode后迟发请求；
native callback时间先于像素复制／Dart轮询，也不支持删除应用层等待来节省同量级。
本批不改生产decoder选择，不据模拟器软件实现推断实体Android硬解性能。继续定位
剩余源端draw／采集→媒体写出和主控图像交付的实际关联；不重复已否定的probe、
提前Texture、buffer_frames及AImage async参数，不因主控实验重建JAR。此轮是诊断
进展，仍未通过1000ms首帧、200／300ms输入及3秒实际窗口预算。trace会切换snapshot
实现，因此不能把本组与上轮关闭trace的有界输入A/B/A混成同一性能对照。


收尾普通main构建21.2秒、安装971ms，APK确认完整原捕获JAR且候选缺席；MCP热重载
124ms／无Dart运行错误，设备首页目视正常。Skipped33frames与SurfaceSync1000ms告警
仍保留，不称启动流畅度合格。两生产JAR摘要不变，目标捕获／枚举JAR与进程为空，
fixture缺席，精确forward移除，自有两AVD核名关闭、PID消失。CLI／DTD／Gradle结束。
清理24项大体积debug输出与未测初始APK共2841.5MiB，空闲41.91GiB；保留实际测量
APK／原件、小型Gradle编译与资源产物以及有效Rust／Flutter／CMake／MDK缓存。
原有五项用户未跟踪文件未改／未stage。下一任务是在普通Driver复用已有目标draw及
前后clock probes，将已验证新计数与源采集→relay关联；必须保留跨端区间和重复PTS
假设。此任务尚未运行，不用研究计划替代源端延迟结论。


## 普通Driver提前挂载纹理的单变量复验（2026-10-18）

旧实验只在fullyLive负载下成立，因此重新用普通Driver复核。实验仅在隔离树
`PortableVideoOutputs._prepare`校验合法纹理后发独立allocated事件，由benchmark在
启用时挂载；不提前返回ready，不删32×32有效像素、64×64新计数或真实窗口断言。
一次编译、同一个APK通过setup参数切换A/B/A，生产代码未采用候选。

构建21.2秒，APK`/tmp/connect-artifacts/early-normal-driver-debug.apk`，SHA256
`d5bc7f2f1e8fb40e40f50bf3aca560ea695bd1dd56ff7c949978386c81f9ec53`。
嵌入完整既有1a3d2c82…候选JAR、生产捕获JAR缺席；不重建JAR。各组1轮8输入、
H2641280/60/8M、实际576×1280／AMediaCodec async1、traceFrames/Clock/Packets开启。
两个API36无头AVD均2vCPU/2048MB/SwiftShader；测量期间无编译，Gradle已停止。

| 普通调度 | A1默认 | B提前挂载 | A2返回默认 |
| --- | ---: | ---: | ---: |
| 全启动可读像素ms | 5740 | 3005 | 2779 |
| Core启动ms | 3899 | 1465 | 1415 |
| 输出验证ms | 1823 | 1051 | 1349 |
| playing→验证ms | 1565 | 640 | 1117 |
| 首onVideo→snapshot ms | 911.391 | 604.303 | 910.278 |
| 正常输入P50/P95 ms | 828/1214 | 661/822 | 608/700 |
| ready前实际挂载 | false | true | false |
| 完整档案帧数 | 219 | 357 | 359 |
| 正确窗口／超过3秒 | 10/3 | 10/4 | 10/3 |

每组暂停恢复、停止、App/fixture/driver清理及目标时间线完整，离线逐帧精确PTS
关联全部通过。最早计数帧input→raw中位578.212／364.263／287.157ms；raw→onVideo
113.263／124.375／147.699ms，onVideo→snapshot147.402／127.267／137.464ms。
这些不同样本中位不相加或拿来推断纯模块耗时。A1有明显源启动冷开销；B虽然缩短
播放器验证阶段，完整首帧和稳定输入未优于返回组，因此不改变生产挂载默认，不将
这个短组说成确定端到端优化。三组严格exit1，trace仍不作生产性能验收。

原件`/tmp/connect-e2e/early-normal-{a1,b,a2}/`；逐组host/app/analysis日志前缀
`/tmp/connect-early-normal-`，汇总`/tmp/connect-early-normal-summary.json`。完整
实验Dart源码、相对当时生产源码补丁、driver/host及摘要回执在
`/tmp/connect-early-normal-source/`；候选运行后已将隔离树两项Dart输入恢复生产原文。
真实B组VIDEO1窗口已目视，图片`/tmp/connect-early-normal-window.png`，未进入Git。
本次不再沿单一挂载方式追加微调，转向已复现的控制流单独失活及排队旧指令问题，
其修复与真实Android回归见[连接健康](connection-health.md)。
