# 当前完成度与下一步验收

更新：2026-10-18。目标状态：**active，未完成**。本页是当前完成度的权威入口；[目标契约](goal.md)定义完成门槛，[重新核查](completion-reassessment.md)保留U01–U44／R01–R62／C01–C32逐项追溯和A01–A60发现，[需求审计](requirements-audit.md)保留原需求来源。后续证据须先更新本页，再回填对应既有任务；历史快照不覆盖本页。

## 本轮：首次配对候选修复与输入队列追踪（2026-10-18）

上一轮`6547f2c`／`3b74fbf`为progress：补齐当前持续动态分布，未带来生产收益。
当前结论：`bb0b339`修复A52首次配对只取首地址及提前保存失败端点；真实DNS-SD／
TLS反馈循环先红后绿，安全AVD正式配对撤权链路通过。`403c5a6`增加严格离线slot
分析并复现当前默认视频输入驻留，尚未带来视频性能收益。完整目标继续active，
不把协议端夹具写成物理换网或整机性能完成。
两个JAR输入不变，原有五项未跟踪文件不改。

首次多地址回归在旧实现真实失败：connected=false，坏地址192.168.0.0被写入记录。
候选改用Required TLS候选遍历、成功后落库，浏览器保留至TLS／metadata发布并推进
代际；发现等待也注册同一操作token，disconnect可取消且不被重试自取消。
最终5项实际协议边界48.51秒通过（含4项显式multicast、1项无网络alias检查），
覆盖fallback、取消发现／无后续TCP、拒绝明文且不写端点、真实更新／goodbye后拒绝
旧TLS client发布。中间两次测试泛型推断编译错误保留，修正后通过；不是产品红测。
只读review未发现新增确定问题。最终Core181 passed／53 ignored（38 suites）、既有
7项真实mDNS回归显式串行执行及Core all-targets clippy -D warnings均通过；ignored默认
数量不当设备证据。安全AVD正式App／FRB／Rust链路69秒完整通过：未授权拒绝、错码
拒绝、真实PAKE、Required TLS连接、按精确产品身份撤权后拒绝旧身份及清理均确认，
hostErrors为空。原件 `/tmp/connect-e2e/pair-candidates-product/`，两个状态截图已目视。
该AVD NAT实验在配对后手动连接，不是物理Wi-Fi多地址首次连接；多地址由上述真实
DNS-SD／TLS边界测试覆盖。

视频离线新增证据：旧隔离raw-drain目标trace无data-loss、唯一捕获进程下，309次acquire／
303次release重建293个完整buffer持有周期，末墙钟1/3有99.913%时间同时acquired16个，
后段持有中位583.259ms。根代理复跑保存 `/tmp/connect-source-slot-analysis.json`；
这是旧trace新分析，不是当前默认路径测量，也不等同精确component work队列长度。
普通codec参数不能修改该consumer输入槽数。下一项先在当前入口采trace验证驻留；
只有实际改采集／提交逻辑的候选才需要隔离重建JAR，不因主控实验重建现有产物。
新增严格离线slot分析器及9条测试已通过，保留所有事件／完整周期／墙钟加权占用，
拒绝data-loss、歧义、未闭合slice及非法状态序列。当前入口首次诊断完成8次输入、
P50／P95=1859／2090ms、首像素3038ms，10张实际窗口计数吻合但10张迟到、整体exit1；
采trace的外围进程查找失败，未取得该次trace，不能将旧数据当当前证据。第二次因未
重启一次性benchmark入口被setup拒绝，保留失败。hot restart后第三次完成：输入
P50／P95=1929／2405ms、首像素2349ms、10张窗口计数吻合，整体仍严格exit1；App／
fixture清理确认。Android ps NAME只展示路径末尾，改为按精确会话JAR定位PID，再从
/proc读取完整nice-name，取得8秒／32MB实际trace并清除远端原件。严格分析data-loss0、
唯一捕获进程下735事件／87 acquire／87 release／71完整周期，末墙钟1/3同时持有16个
的时间99.951971%，后段完整周期中位1318.763ms。当前默认路径的输入驻留已复现，
原件 `/tmp/connect-e2e/current-source-slots-r3/`；追踪有观测开销，不作为无追踪性能
A/B或收益。下一项限定已有GL接缝的最新待提交帧＋有界在途候选；尚未改JAR。

生产修复`bb0b339`／追踪分析器`403c5a6`已分批提交。Core三交叉check分别iOS2.33秒、
macOS2.14秒、Windows MSVC2.28秒通过，非对应宿主Flutter整包。新的同签名arm64
release61.33秒完成，46,937,374字节，SHA-256
`cf23f8100f5166517cb299629a0c1cc0f412f4866463da56d5d406eccd64e577`，ZIP／manifest／
arm64 ELF／16KB ZIP对齐及签名独立校验通过，保留
`/tmp/connect-artifacts/connect-arm64-pair-candidates-release.apk`；未冒称物理ARM运行。
vendor／捕获JAR摘要仍为764eb6f7…／b46cd074…，均未改未重建。

收尾已完成：普通main构建8.5秒／安装1577ms，MCP热重载成功／无Dart运行错误，空
设备首页实际截图已目视；Skipped40frames／SurfaceSync1000ms／1407ms启动帧仍保留，
不计启动流畅度通过。目标捕获JAR／捕获进程为空，fixture缺席，trace远端原件移除；
forward精确按serial删除后缺席，两台自有AVD核对名称关闭且PID消失，安全target-b
前序已恢复无线关闭并结束。CLI detach、Gradle停止；精确清理394项debug及92项本轮
已结束的非视频Core测试输出／incremental，逻辑10962.6MiB、空闲46.33GiB。保留release、
视频／连接反馈程序、有效构建缓存及原始证据，五项用户原未跟踪文件未改、未stage，
无push。回执`/tmp/connect-pair-candidates-{target-cleanup,forward-cleanup,avd-stop,
build-cleanup}.json`。下一项是隔离采集提交候选，不能无界阻塞GL或丢失唯一静态终帧。
只读设计进一步确认原生repeat-previous-frame-after会绕过GL提交ledger；隔离候选
必须由同一模块管理静态重复与限帧，精确输出PTS归还credit，并保留原始源时间戳，
不把重绘PTS变新冒称源年龄改善。限定主屏API36 H264／c2.android.avc.encoder、窗口2，
无输出时有界失败；先纯Java状态／生命周期回归，再实际终帧／旋转／暂停及A/B/A。
这是下一批实施约束，尚未构建或测过候选，生产JAR保持不变。



## 本轮：高动态窗口取样路径（2026-10-18）

当前结论：`6547f2c`实现原始实际窗口取样和强制失败的扩展诊断。限定2→4→2vCPU三组各3轮24输入全部完成，P50／P95分别1866／2202、1584／1865、1793／2145ms；各30次窗口计数匹配，迟到21／30／20次，暂停恢复、停止与App／fixture清理确认。全部严格exit1，没有生产性能收益，也未证明唯一瓶颈；新启动目标返回组首跑输入超时另保留。当前持续动态分布已取得，不再沿用上一轮“尚无当前输入分布”的缺口；首帧、高动态低延迟、native崩溃及完整目标仍未完成。两个JAR未改、未重建。[结果、失败与复现](../../docs/implementation/video-dynamic-measurement.md)。

默认路径兼容已实际通过：不设置raw／扩展期限，静态夹具3轮24输入、30个PNG实际窗口完整exit0，首像素921／903／828ms、输入157／210ms，所有硬窗口预算及暂停恢复／清理通过；`/tmp/connect-e2e/raw-window-default-png-control/`。这仅确认新工具保留默认严格路径，不外推为持续动态图案通过。4文件严格分析、格式、协议回归及只读review通过；本批不改产品源码，不重打相同release。

本批收尾：普通main实际构建8.4秒、安装1133ms，MCP热重载137ms成功／无Dart运行错误，空设备列表真实截图已目视。启动Skipped35frames／SurfaceSync1000ms／1445ms长帧告警仍保留，不称启动流畅度通过。目标捕获／枚举JAR与捕获进程扫描为空、fixture缺席。结束本轮CLI、停止Gradle，两台自有AVD核对名称后关闭且PID消失，forward关闭后缺席；未指定serial的remove尝试exit1不计成功。精确白名单清理394项debug输出1486MiB，空闲40.87GiB，保留release／有效缓存和必要原始证据。回执 `/tmp/connect-raw-window-{target-cleanup,avd-stop,forward-cleanup,debug-cleanup}.json`。原有五项未跟踪文件未改／未stage，无push。后续继续源采集／编码与relay、呈现分段及实际ARM／无线证据，不重复已被否定的ADB参数，也不继续增加AVD资源当修复。

上一轮3771d44／58aed15为progress。为取得当前普通调度的持续动态输入分布，先隔离实际窗口PNG压缩／校验成本：同3秒门槛增加可选screencap原始RGBA路径，旧PNG保留；按AOSP格式校验16字节头、RGBA8888、精确长度及实际Texture矩形和精确计数，继续保存原始实际窗口字节，不跳过呈现检查。尚无收益或本轮输入分布结论；不改生产参数／JAR，原有五项未跟踪文件不动。

原始路径首次动态仍红：raw抓取／落盘1961ms、base64编码118ms、验证请求1256ms，3411ms组合窗口超时；App／fixture清理确认，原件 `/tmp/connect-e2e/dynamic-raw-window/`。没有本轮输入分布，不宣称去掉PNG已解决。下一步只加显式诊断继续模式：收集期限独立延长但硬门槛仍3秒、逐次记录迟到，诊断整次始终videoPerformanceComplete=false，保留完整真实窗口／输入／暂停／释放证据，避免反复卡在首张而丢失数据。

原始窗口诊断已完成3轮24输入，P50／P95=1866／2202ms，首像素2229／1978／2549ms，30次实际窗口计数、3次暂停恢复／释放与App／fixture清理均确认；21个窗口超过硬3秒预算。measurementLoopComplete=true但diagnosticOnly=true／videoPerformanceComplete=false、严格exit1。原件 `/tmp/connect-e2e/dynamic-raw-diagnostic/`。仅收集期限允许15秒、硬门槛和最终判定未放宽；没有生产收益。下一项限定目标2→4→2vCPU资源对照，保持同一画质／动态画面／主控配置，不能据增加模拟器资源称产品优化。

官方SDK核查完成：最新正式MDK仍0.39.0（2026-09-30）、fvp仍0.39.1（2026-10-15），没有可直接安排的后续正式升级版本；旧snapshot／async修复都已在当前基线或之前，不能当作当前renderer空回调的已证修复。保留显式async=1及已有NULL／生命周期补丁，历史native崩溃继续开放；[版本核查与来源](../../docs/research/mdk-sdk-snapshot-followup.md)已落盘，不盲目换latest。

4vCPU组3轮24输入完成，P50／P95=1584／1865ms，30窗口全部匹配但全部迟于3秒，整体仍严格exit1。返回2vCPU首跑首像素4243ms、第一次输入未在3秒内出现，未完成分布，App／fixture清理确认；保留 `/tmp/connect-e2e/dynamic-raw-return2cpu/`，不能据候选一组认定因果。返回组保持参数复跑一次，以分别记录新启动目标的失败和暖运行分布。直接启动qemu曾因其动态库路径缺失而退出，改用同参数的官方emulator启动器后boot／cpu0-1已核实；不将该启动失败当视频性能数据。

## 本轮：普通调度持续动态复核与应用停转验收（2026-10-18）


当前结论：`3771d44` 新增真实应用停转故障验收，双向drop／无注入EOF的两组正式视频恢复通过（19.850／19.082秒），默认EOF恢复1.603秒；真实TCP四场景、严格Dart分析及只读review通过。高动态性能仍未通过，新普通调度动态首像素2429ms且窗口抓取校验超过3秒，尚无本轮输入分布。完整目标保持active。

本轮收尾：普通main恢复构建7.5秒、安装540ms、MCP热重载130ms成功，无Dart运行错误，空设备首页及恢复后VIDEO1均目视；Skipped31frames／SurfaceSync1000ms／1404ms启动帧仍保留，不计流畅度通过。目标捕获／枚举JAR与捕获进程扫描为空、fixture缺席；两AVD核对名称后关闭，forward移除、Gradle停止。清理394项明确debug输出1486.0MiB，空闲42.0GiB，保留release／有效缓存／原始证据，原有五项未跟踪文件未改。回执 `/tmp/connect-application-stall-{target-cleanup,avd-stop,debug-cleanup}.json`。下一项把持续输入取样和慢窗口抓取分段，诊断运行也保留严格失败，以补齐当前动态分布，再决定目标队列或呈现的改进；不复跑已被否定的ADB缓冲参数。

上一轮 `f331dfd`／`dd334a3` 为 progress。当前先重跑最新默认异步解码、普通 Driver 调度、1280／60／8Mbps 的持续动态夹具；旧动态数据包含已修复前的调度／解码差异，不能直接视为现状。保留原门槛、实际窗口、暂停恢复与清理断言，先测量再决定编码／传输／呈现改动。两份 JAR 输入不变，不因主控侧实验重建；原有五项未跟踪文件不改。

普通调度持续动态首跑未完成：start请求完成约3709ms，随后的实际控制端 adb screencap 在独立3秒窗口中没有返回，host有界终止该进程并确认退出／排空；未进入输入循环，不产生P50/P95。App／fixture清理均确认，`/tmp/connect-e2e/dynamic-normal-default/`保留失败。不能将其称解码首帧或截图原生崩溃；同配置复跑以区别冷宿主／持续图形负载。

动态同配置r2仍未进入输入循环：实际首像素2429ms、core1012ms／输出verified1399ms；adb截图约2289ms已返回，但余下718ms不足以完成App内PNG验证，3秒组合门槛失败。实际PNG已目视显示动态远端画面，不能归为“没有Texture”或视为性能通过。两次均完整清理；保持失败记录、不改预算，先继续独立应用停转后的真实视频恢复验证。

稳定性下一项：扩展既有真实视频恢复driver，默认EOF保持不变；blackhole模式仅对唯一旧ADB连接丢弃双向数据并继续排空，不主动关闭socket，新连接正常转发。拟以真实TCP回归锁定没有注入EOF、实际drop、controller先关闭与新accept次序，再跑实际adbd／正式RemotePage。尚未计通过，不把它称物理Wi-Fi切换或内核丢TCP ACK。

实际应用停转首跑：正式RemotePage约19440ms恢复新session，真实像素0→1、主动停止、设备／fixture／代理清理完成；但严格driver拒绝，因为只丢到controller→upstream108字节，静态画面upstream→controller为0。`/tmp/connect-e2e/video-application-stall/`保留exit1，不计完整通过。接下来只增强故障夹具：黑洞注入后经独立ADB使本轮独占图案变化一次，等实际旧连接丢到视频字节，再重置同fixture计数0，证明双向停转；不放宽回执，不改产品。

带实际画面变化的应用停转E2E首组32秒完整exit0：约19850ms恢复新session，Flutter计数0→1；旧连接实际drop为controller108／upstream6724字节，注入关闭操作0，controller首EOF时尚无新accept，此后新连接连到实际adbd，回执errors为空。fixture改变／复位均成功，52ms取得实际入站drop；停止／设备／设置／fixture／代理清理均确认。原件 `/tmp/connect-e2e/video-application-stall-frames/`。最后增加fixture挑战完成的显式门禁后正在复跑，不将已通过组替代最终源码验证；生产源码和两个JAR均未改。

最终driver版应用停转完整通过（约31秒用例）：19082ms恢复新session，图案0→1、停止后不重建、完整清理；双向drop108／6659字节，53ms取得入站drop，注入close0／controller先EOF／newaccept顺序均满足，faultEvidenceErrors为空。故障注入至旧controllerEOF17768ms、至新adbd连接17784ms，和从host ack起算的19082ms首像素回执分别保留。原件 `/tmp/connect-e2e/video-application-stall-verified/`。同版默认EOF控制14秒完整通过，恢复1603ms，清理确认，`video-application-stall-eof-control/`。三driver文件严格分析无问题、真实TCP四场景通过；无产品或JAR改动，不重打相同release。

## 当前视频性能增量（2026-10-18）

当前结论：`f331dfd` 已实现默认主屏 H264 自动编码器的冷目录直启，已有不支持目录／其他 codec／指定编码器／独立应用仍严格预检。关闭诊断的普通 Driver 3 轮 60 次输入严格通过：首像素 903／877／875ms，输入 P50／P95=147／225ms；66 次实际窗口、暂停恢复及释放清理完成。首组冷样本 1102ms 保留，不称所有冷启动稳定达标。

正式 RemotePage 五编码重新生成插件注册后，原测试未改、原像素／Texture／截图／退出及清理断言未放宽，23 秒完整通过：H264／H265／AV1／VP8／VP9 均 rendered，mediaAcceptanceComplete=true。目录 `/tmp/connect-e2e/auto-capture-product-five-plugins/`。首次 47 秒超时仍保留；r2/r3 是约 6 秒截图插件缺失，不能并记成三次首帧超时。普通 main 实际连接、全屏 Settings、远端触控、拖拽吸附／展开退出及设备移除也已走通。以上为 x64 AVD／debug，尚非物理 ARM、真实 Wi-Fi 切网、小时级长稳或全部场景性能验收。

本轮签名 arm64 release 60.38 秒完成，46,920,990 字节，SHA-256 `64c5cf58d20ef6eaa45c12a630c14dd0f7bad8b4789898404dbc469972278a14`，稳定证书、manifest、ZIP 完整性、16KB 对齐及 arm64 ELF 验证通过。保留 `/tmp/connect-artifacts/connect-arm64-direct-capture-release.apk`，尚未在物理 ARM 设备安装运行。捕获／枚举 JAR 与对应进程扫描为空，fixture 已卸载；其他旧 companion／audio-fixture 命名文件不属于此处捕获清理证明，未批量删除。回执 `/tmp/connect-auto-capture-{release-receipt,target-cleanup}.json`。

本轮收尾：普通 main 恢复构建7.6秒，MCP热重载128ms成功、无Dart运行错误，设备首页空态目视确认；启动Skipped32frames、SurfaceSync1000ms及1505ms长帧告警保留，不计应用冷启动流畅度通过。五codec原图均目视，H265明显低清仅计可播放，不计画质通过。两台本轮AVD核对名称后关闭，Gradle停止、forward移除；精确debug白名单394项／1506.9MiB已清，空闲42.25GiB。release、有效构建缓存与原始证据保留，原有五项未跟踪文件未修改。下一项继续高动态上游积压与截图原生崩溃，以及活动视频断网恢复，不以本组静态夹具通过关闭完整目标。

以下为逐轮过程记录，当前结论以上段及最新收尾为准。

继续默认主屏冷启动：上一轮15c8919／dfd1763为progress，首帧1142/1064/1000ms仍
失败。当前验证主屏／有效H264／自动编码器在目录未知时直接捕获；不是把未知标成
可用。已有不支持目录、非默认codec、named encoder、独立应用窗口保留严格验证。
先补真实ADB SEND路径回归，再测默认及独立应用失败／清理，最后关闭追踪扩量；
目前尚无新性能收益或直启验收，JAR输入未改，沿用已有产物。
默认首个SEND路径回归在旧实现实际失败，确认先上传interop-encoders；新实现已补
精确连接只读peek及默认直启，Core lib67 passed/2 ignored、clippy all-targets通过。
回归保留strict探测／清理，并覆盖有效偏好／覆盖、休眠不上传、不支持缓存仍拒绝，
peek进行中不等待／连接关闭与替换。只读review未发现新增缺陷。正跑真实应用unknown
四项及双AVD性能，当前仍不能宣布首帧达标。
完整Core回归180 passed/49 ignored（37 suites），另外真实Android应用启动四项
45.26秒通过；ignored不当设备通过。默认直启首组3轮30输入，validated44/44/45ms、
Core471/481/438ms、首像素1102/927/782ms，P50/P95=141/214ms。36次窗口、3次暂停
恢复／释放及清理确认；首个新AVD样本仍超1000ms、整体exit1。正在只把
requires_enumeration强制true构建对照APK，再恢复候选重复；不将冷绘制波动抹掉。
强制枚举对照首帧1044/1041/1070ms、validated252/272/269ms，P50/P95=137/243ms；
同样36窗口及暂停／释放／清理完成、严格exit1。现已恢复候选源码并构建返回组；
正式RemotePage直接请求session.start，枚举仅在质量页显式请求，故不是只优化基准
的旁路。候选Core iOS/macOS/Windows交叉check均通过，不代表对应Flutter整包。
返回直启组3轮30输入首次严格exit0：首像素896/935/941ms、validated50/51/49ms，
输入P50/P95=144/267ms，36次实际窗口、暂停恢复／释放及App／fixture清理均确认。
结果/tmp/connect-e2e/auto-capture-return/。首组1102ms冷样本仍保留，不能据返回组
通过宣称所有冷启动已达标；正在关闭追踪扩到60输入并补正式RemotePage五编码回归。
最终生产default、关闭native及系统追踪，3轮60输入严格exit0：首像素903/877/875ms，
输入P50/P95=147/225ms；validated46/44/44ms，Core400/447/433ms，连接另计49/51/51ms。
66次实际窗口、3次暂停恢复／释放及App／fixture清理确认；原件
/tmp/connect-e2e/auto-capture-final-60/。不是面板扫描或物理ARM／release性能，不删除
首组1102ms失败。源码已提交f331dfd；正在正式RemotePage五编码回归。
正式五编码首跑失败：H264在47秒用例中等待像素／Texture超时，结果无任何codec
成功项、mediaAcceptanceComplete缺失；/tmp/connect-e2e/auto-capture-product-five/
及对应日志保留，不计五编码通过。正恢复普通main以区分实际播放与集成绑定调度、
Surface初始化及状态残留，尚未归因于某一项，不以benchmark绿替代正式功能验收。

本轮继续首帧专项，未宣称完成：先用新启动的双AVD重复现有默认路径，再验证冷编码器
枚举和正常清理合并为一次shell是否减少启动往返；上传失败、超时、调用方取消的独立
清理所有权仍须保留。输出阶段约0.44秒另按既有原始追踪排查，不重试已否定的参数。
上一段末尾“校验约0.24–0.31秒”不是最终默认组数值；最终默认组validated实际为
312/350/313ms，Core为734/715/673ms，首帧1197/1157/1122ms。当前未改服务端源码、
补丁、版本或工具链，沿用已提交JAR，不因主控侧性能实验重建。新实验尚无收益结论。
新双AVD基线3轮2输入首帧1587/1176/1222ms、validated413/303/354ms；合并候选为
1068/988/1147ms、validated263/269/276ms。每组12次实际窗口、3次暂停／恢复／释放及
App／fixture清理确认，整体严格均exit1。基线包含首次模拟器冷负载，不能将差值
全部归因于一个shell；正在切回旧流程复核。旧wire边界5项及真实shell删除测试先红，
新Core lib61 passed/2 ignored、clippy通过，另有只读review未发现新增问题。
既有异步输出Perfetto中，onVideo(PTS0)至首swap之前，renderer实际CPU Running约
131/132/135ms，首swap55/71/106ms；尚无CPU栈，不能直接称shader编译，正在补采样。
旧流程返回组首帧1261/1088/1148ms、validated365/231/311ms，方向支持候选但存在重叠，
不把中位354→269→311ms当固定收益承诺。返回组6输入P50/P95=163/398ms，仍保留失败。
另复核renderer首个视频输出窗口CPU约131–135ms，而紧邻后两次通常1–3ms；此处首
swap是该视频输出之后的第一笔，不是线程生命周期首swap。正采同钟Perfetto与
simpleperf原生栈，诊断样本不参与候选收益统计。恢复候选源码后还需无追踪扩量复测。
候选生产default关闭native及系统追踪，最终3轮60输入P50/P95=148/221ms，输入预算
通过；首帧1142/1064/1000ms，完整首帧仍失败、严格exit1。validated264/316/272ms，
66次实际窗口检查、3次暂停恢复／释放及App／fixture清理确认。结果在
/tmp/connect-e2e/startup-shell-final-60/，不把它与前组trace开启的6输入作控制对照。
新30秒原生CPU采样719样本无丢失，整体renderer热点主要在模拟器GL状态查询及
QemuPipe同步读写；正按首输出窗口与实际clock_snapshot转换过滤，尚不能据此称真机
同样受限或已找到shader编译问题。详见[本批证据](../../docs/implementation/video-cold-start.md)。
`15c8919`已提交合并清理。采样按同线程首release→swap过滤为27样本（7/13/7），
含GL2Encoder::updateProgramInfoAfterLink及GL shader／uniform／状态查询，经QemuPipe
同步读写；由clock_snapshot校正MONOTONIC与trace时间，偏移49–124ns，最近样本距
边界431934ns。样本有限，不把代理调用解释为宿主shader编译耗时或真机瓶颈。
Core iOS/macOS/Windows交叉check全部通过；只证明Core构建，非四宿主Flutter整包。
更新签名arm64 release60.40秒完成，签名／manifest／ZIP完整性／16KB对齐／arm64
ELF检查通过，身份不变；原件/tmp/connect-artifacts/connect-arm64-cold-start-release.apk，
46920990字节，SHA-256=d7b15c2e31dcb4d8526e2385e11368332e6bcf152f23a636c0ddbba580b040f6。
尚无物理ARM运行证据。正恢复普通main并清理本批调试输出，保留有效缓存和原始证据。
普通main已恢复并MCP热重载成功、无Dart错误，设备列表空态目视通过；启动Skipped39
frames及SurfaceSync1000ms告警保留，不称应用启动流畅通过。目标本批15个捕获JAR、
进程及fixture确认无残留；额外扫描发现1个早于本批的官方枚举JAR，mtime为
2026-10-17T21:29:50Z（本批首次实验03:17:40Z），摘要为固定官方JAR。保留首次失败
清理回执，确认无scrcpy进程后仅删除该精确旧路径，复扫为空；不是本批正常清理遗漏
的证据。最终回执/tmp/connect-startup-shell-target-cleanup-final.json。新trace、配置及
采样远端副本已删除，host原始证据保留。
本轮收尾：普通main构建8.4秒／安装599ms、热重载123ms；两AVD核对名称后正常关闭，
Gradle停止、仅清理精确debug白名单394项／1486.0MiB，空闲49.67GiB；release及有效
缓存保留，五项原有未跟踪文件未修改。整体目标仍active。下一段优先实测默认主屏
H264自动编码器在冷目录未知时直接捕获的窄路径：固定scrcpy默认不先list_encoders；
不能伪造available，已有明确不支持的目录仍拒绝，非默认codec／named encoder／
独立应用窗口保留strict probe、睡眠与未知启动账本保护。本段只完成只读契约审查，
尚未实施或取得该直启路径收益；不能重复削弱现有验证来换取门槛通过。

上一轮连接健康修复与实际解码路径确认已提交，判为progress。本轮双AVD冷启后，
普通Driver原生默认3轮30输入首帧1552/1152/1114ms、P50/P95=283/439ms，严格门槛
仍失败；36次实际窗口检查、3次暂停恢复／释放及App／fixture清理确认。同步60秒
video/gfx/hal/sync系统追踪（首个配置路径被SELinux拒绝，改perfetto-configs成功）
取得455个唯一queue/workDone对；首两次输入在录制前，其余28个按PTS及codec匹配，
组件合段中位4.586ms，而同PTS relay→onVideo中位153.703ms。两者只比较区间长度，
Rust相对时钟不能直接减系统绝对时钟；正补optin Android ATrace onVideo短标记以
区分组件完成后的等待，未改默认播放参数或JAR，尚无性能收益或新增验收通过。
原始追踪、JSON与截图均在/tmp/connect-decoder-boundary*及/tmp/connect-e2e/decoder-boundary-r1。
新ATrace版本首次R2在第一次input因snapshot PTS不能唯一对应native回调而拒绝，
不计成功样本；App／fixture清理确认，正在保留失败后复跑。分析器独立review找出
跨token重复PTS可复用旧pair、重复decoded取min和错身份先入统计，4项实际红后修复；
8项回归全绿并只读复核闭合，显式本次PID、唯一decoded与marker及pair独占后才纳入。
R3复跑3轮30输入完成，首帧1150/1137/1189ms、P50/P95=277/392ms，严格仍失败；
36次真实窗口、3次暂停／释放与清理完成。系统marker覆盖30/30输入，显式PID4367、
token及PTS唯一关联；queue→workDone中位3.600ms、workDone→onVideo中位147.174ms，
同PTS relay→onVideo中位151.589ms。主要额外等待已定位在组件完成之后，不能再把
它笼统归为AVD codec处理慢；SDK回调／输出调度／图像交付仍合在后一段，尚非单独
fence等待证明。工具require-markers真实exit0只表示覆盖完整，严格性能仍exit1。
系统标记与保守分析器已提交53bcf10（Bridge19项、Python8项／clippy／fmt通过，
Android arm64 check通过；Apple／Windows bridge整包仍在既有宿主SDK依赖处失败）。
进一步实测同onVideo线程有同步dequeueOutputBuffer且无输出async callback事件，
正在单变量benchmark显式async=1并检查实际系统路径；AImage异步获取不能当codec
异步证明。生产默认未改，不将文档默认值当生效证据。
显式async=1三会话取得3条真实async日志和467条onOutputBufferAvailable，无持续
同步dequeue；30/30系统marker配对，组件完成→onVideo中位20.841ms（原147.174），
relay→onVideo34.123ms（原151.589）。输入P50/P95=153/204ms（原277/392），但首帧
1170/1107/1165ms仍超1000，整体严格exit1，未宣称全门槛通过；36次窗口及暂停／释放
清理通过。关闭后media.metrics operation-mode=1可能受stop清async flag再flush影响，
不作为运行期同步证据，实际async日志／事件为依据。正切回原参数进行A/B/A复核。
A/B/A返回原生缺省后P50/P95=273/389ms，首帧1227/1150/1154ms；30/30标记，
workDone→onVideo中位133.510ms，relay→onVideo140.512ms，劣化可重复。故已将生产
Android默认显式AMediaCodec:async=1，原软件回退及其它平台优先级保留；当前正跑
真实RemotePage五编码及正式default路径无trace扩量，尚不宣称最终验收通过。
共享播放器变更经MCP热重载成功、无Dart错误，未改服务端／JAR。
真实RemotePage五编码24秒通过：H264/H265/AV1/VP8/VP9全部rendered，悬浮退出后
capture暂停、逐session停止与设置恢复检查通过，mediaAcceptanceComplete=true；
不是五编码性能验收。结果/tmp/connect-e2e/decoder-async-product-five/result.json。
全workspace严格Dart分析无问题；正在关闭trace的生产default路径3轮60输入复测。
最终生产default、关闭native trace及系统追踪，3轮60次输入P50/P95=138/295ms，
首帧1197/1157/1122ms；输入预算通过、首帧仍失败，整体严格exit1。
每轮实际decoder=AMediaCodec；66次窗口检查、3次暂停／停止分离、App与fixture清理
确认。结果/tmp/connect-e2e/decoder-async-default-60/result.json；不是物理ARM或发布
模式性能。Bridge Flutter123项通过。正在构建更新后的签名arm64 release并恢复普通main。
生产配置及隔离候选已提交24379bb；系统观测及配对工具提交53bcf10。
首次release在集成测试后直接--no-pub，76.2秒因GeneratedPluginRegistrant仍引用
release未包含的integration_test而失败；这是模式切换准备问题，非Rust/ATrace链接。
失败日志保留，正先离线pub准备再复建，未将失败APK宣称可交付。
改用现有tool/android.py build后47.36秒完成（Gradle45.9秒），签名、manifest、
ZIP完整性／16KB对齐及完整arm64 ELF检查通过，证书身份不变。新原件
/tmp/connect-artifacts/connect-arm64-decoder-async-release.apk，46920990字节，SHA-256=fc6db347d819e42abaa630b452f5a7f32edab8b82b2ed37b6ed39aa951f9d022。
这是ARM构建证据，未在物理ARM运行；x64 debug E2E独立记录。普通main正在恢复。
普通main已实际恢复：构建16.9秒／安装692ms，MCP热重载119ms成功、无Dart运行
错误；设备首页空态已目视并detach，未留下新增设备记录。启动Skipped34frames及
SurfaceSync1000ms告警保留，不计应用冷启动流畅通过。代表图/tmp/connect-decoder-async-main-before.png。
目标捕获JAR／进程／fixture确认无残留，远端本批trace与配置删除，Gradle停止，
两AVD正常关闭。按精确debug白名单清理394项、1506.8MiB，空闲50.18GiB；
release、有效Flutter／Rust／Gradle／CMake／SDK缓存及/tmp原始证据保留，原五项未
跟踪文件未修改。完整产品目标及视频任务继续开放。下一步拆首帧Core约0.7秒
（含校验约0.24–0.31秒）和输出约0.4秒，不能用此次持续输入改善代替首帧达标。
收尾增加分析器空结果门禁：有效空rounds会使all(empty)误通过的单元先红，现9项
回归通过；实际R2缺rounds报告也改为明确拒绝而非KeyError，R3完整30输入仍exit0，
数值不变。提交0e7198b，只改宿主分析工具，不改变已验证APK内容。

上一轮普通调度基准与扩量对照已提交，判为progress。本轮继续实际decoder路径定位，
并新增真实TCP/TLS的ADB应用失活回归：对端保留socket且消费TLS字节，但不回复ADB
请求；实际40秒未恢复、整项44.84秒红。现补空闲10秒sync: OPEN、3秒期限、两次
无入站超时才close精确Client，交既有重连；不启动shell／进程、不操作文件、不持
Runtime、不阻塞其它设备。正常OKAY／CLSE及其它流量均证明响应，显式断开仍停止。
独立review发现完整帧计数会误断慢大帧；真实1MiB分段WRTE已先红，改为每个非空
header／payload读取批次记录进展，新增慢header回归，8项wire行为测试通过且再次
只读复核闭合。既有read_trace及协议验证通过，未改trace时钟边界或协议校验。
最终3项真实TLS回归宿主36.35秒、Android x64普通shell30.97秒均通过，覆盖应用
失活恢复／同ID、健康拒绝保持连接、旧probe期间主动替换不误断及主动断开不复活。
它们不是丢TCP ACK／EOF／真实Wi-Fi切网或实际adbd故障注入的证明。
decoder路径探针成功附加实际App，关联AImageReader_getWindow成功返回的窗口、
相同窗口的MediaCodec成功配置及同reader成功acquireLatestImageAsync，均有libmdk
调用栈；所以异步AImage acquire已启用，不重复该候选。首次30秒窗口等host构建
而无事件，第二次取得3条关联回执，另有LLDB脚本回调KeyError，全部原样保留；
只辨路径，不把debugger期间1474ms首帧作性能对照。两次fixture／App清理均确认。
生产播放器及两个scrcpy JAR未改；JAR未重建，平台持续延迟仍开放。
详见[连接健康实现](../../docs/implementation/connection-health.md)及
[实际decoder路径](../../docs/research/scrcpy-first-frame-performance.md#实际aimagereader异步路径确认2026-10-18)。
代码提交`8c55b84`。完整ADB72 passed／13 ignored、Core169 passed／49 ignored通过；
两包all-target clippy -D warnings／fmt及Core iOS／macOS／Windows交叉check通过，
非对应宿主Flutter整包或运行证据。普通main构建74.5秒／安装1514ms，热重载133ms
成功、无Dart错误；真实UI手动TCP连接→全屏Settings→远端点击Network页→悬浮退出
已操作并目视，随后通过页面移除测试记录，设备首页空态已目视。启动SurfaceSync
和HWUI长帧仍有，不算启动流畅或严格首帧通过；未声明真实无线切网／长稳完成。
两个诊断会话及普通会话无捕获JAR／进程残留，fixture和自带LLDB／Android测试程序
已移除；LLDB模块缓存408.9MiB删除，原始事件／失败回调日志保留/tmp。
Gradle停止并正常关闭两AVD；按精确清单清理472项debug输出／26个非视频测试程序
及其incremental，共11871.9MiB，空闲52.35GiB；release、有效Flutter／Rust依赖、
视频／health反馈循环及Gradle／CMake／SDK缓存保留。原有五项未跟踪文件未修改。

上一轮已提交native计时并定位Live调度偏差，判为progress。本轮新增独立的普通
Driver binding基准，沿用实际Rust ADB／共享PortableVideoOutputs／真实Texture，
不构造Live测试绑定；host经ADB抓实际窗口，在延迟计时之外检查图案。首轮三会话
和12次窗口检查完成，但严格性能失败，且清理误用devices.remove；原失败证据保留。
现已改用devices.forget，保留首次未确认释放状态，host超时后App清理等待在途操作，
adb客户端超时会终止／排空；安装结果未知仅按APK字节证明归属后卸载，未知仍失败。
修正后原生AMediaCodec三轮首帧979/1168/1146ms、输入P50/P95=303/449ms，严格失败；
单变量FFmpeg slice三轮837/908/890ms、85/231ms，严格通过，两组窗口／暂停／清理均
完成。扩到各60次后，原生首帧1184/1148/1196ms、P50/P95=256/359ms，严格失败；
软件首帧947/837/886ms、108/153ms，严格通过，两组共132次实际窗口检查／6次暂停
恢复／6次释放和自动清理均通过。默认播放策略未改，不能宣称物理硬解或真机达标。
同PTS同主控时钟的relay开始写→onVideo中位134.373ms与1.414ms；这包含socket消费、
demux及decoder路径，不是纯解码耗时。此前小样本用write完成时刻，消费可先于write
Future完成，所以扩量统一用writeStartedUs描述该边界，不裁掉负值再统计。
新入口及host严格分析通过；宿主三项故障探针验证强制终止、未知安装的同APK认领
与不同APK拒删，App清理并发及释放状态已独立只读复核。15个已知会话JAR逐项无
残留，额外全局捕获JAR／进程和fixture均为空；两个JAR摘要未变，未构建服务端。
普通main构建25.5秒／安装588ms，热重载169ms成功，无Dart运行错误，设备首页已
目视后detach；启动Skipped34frames和SurfaceSync1000ms告警仍有，不计启动流畅通过。
完整workspace严格Dart分析无问题；新基准提交`afa4943`，默认入口／播放策略未改。
停止Gradle并正常关闭两台AVD，精确清理394项debug输出1484.9MiB，余量48.74GiB；
release、有效Flutter／Rust／Gradle／CMake／SDK缓存及/tmp原始证据保留。
下一步继续拆解平台decoder输入／输出与图像获取等待，并补真实ARM／profile证据；
网络层黑洞已有期限；当时待补的adbd应用失活现已修复并完成TLS夹具验收，见本页最新增量。

上一批五组对照与提交判为progress，严格性能仍开放。本轮先补native snapshot提交
时间，区分onVideo之前／之后提交及实际callback等待，再隔离测试纹理提前消费；
同时只读核查静止视频下TCP半开／网络黑洞健康检查。尚无新的优化收益或验收通过。
native提交计时与真实C ABI边界通过，完整Bridge Rust17项／clippy／fmt通过。
四组三轮真实会话均完成像素／暂停／呈现／清理，严格性能全失败；提前挂载及等待
decode再snapshot未有稳定整体改善，临时Dart/Fvp改动按原字节恢复。额外发现本批
fullyLive会与测试绑定无条件scheduleFrame形成持续框架帧负载，不能当生产等效；
Perfetto光栅高CPU只说明该负载实验，原默认门禁不变。正转普通App实际页面核验。
只读确认TCP黑洞已有keepalive及USER_TIMEOUT，应用层adbd仍ACK但不处理请求则
缺主动探测，显式断开重连可恢复；不重复已有网络层实现，另留应用失活验收。
普通main真实表单→设备页→全屏远控已操作，目视目标图案0→2；正常绑定静态15秒
trace中raster CPU378.232ms／6次swap、视频Surface59.458ms／11次swap、无data-loss，
对比fullyLive的6.558秒只澄清负载边界，场景不同，不是性能收益或冷首帧测量。
普通main热重载成功、无Dart错误、测试记录移除后设备首页已目视；两个JAR未变。
12个已知session JAR逐项无残留、全局匹配捕获JAR与捕获进程均为空，额外普通App
夹具已卸载，Perfetto临时文件已从设备移除。主控AVD RSS增长至约8.44GiB，停止
Gradle并正常关闭两台AVD释放内存；精确清理394项debug输出1484.6MiB，空闲49.6GiB。
源码仅保留native snapshot提交时刻及测试回执binding／framePolicy，不改播放器策略。
代码提交`f4db3b6`，详见[本批证据](../../docs/implementation/video-performance.md#截图提交时间与测试帧调度边界2026-10-18)。
下一项采用正常WidgetsFlutterBinding入口测冷启动／实际输入至新像素／持续Texture，
保留严格预算及暂停清理；不再仅靠调整Live测试策略判断产品优化收益。

本轮继续重复编码器分配候选：上一轮完成了实际依赖修补与设备验证，判为progress。
先在同一捕获JAR、重新冷启的目标AVD上采集codec创建／释放系统时序，不将新旧
AVD生命周期差异当优化收益；保持门槛、码率／分辨率／帧率及原协议。对照将记录
宿主可用内存和模拟器RSS；尚未改服务端补丁或重建JAR。
同JAR三次系统日志均证实两次c2.android.avc.encoder创建，两次Created事件相隔
39/34/33ms（包含必需能力查询／初始化，不是纯冗余耗时）。首个临时raw诊断误将
静态流下一包当必需而超时，未计编码首帧测量；改为首个完整媒体包即结束后两次
完成，三次fixture／进程／JAR逐项复核均已清理。尚无足够证据为该候选改变暂停
所有权／重建JAR；转向更大的关键帧后输出等待，继续保留完整性能门槛。
性能入口已保存首个32×32验证snapshot被后续readback替换前的native指标，并以
同一Dart启动Stopwatch前后包围读取；不把注册后首个回调当整个解码器最早回调。
同JAR／1280/60/8Mbps／AMediaCodec／trace开启三轮读取前首帧1318/1221/1111ms，输出
712/444/439ms；首个已观测解码PTS0到同PTS截图回调289236/290804/330370µs，
各有7个解码回调，严格1000/200/300仍exit1，三轮新像素／暂停／呈现／清理完成。
已完成默认→buffer_frames=1→恢复默认，再单独profiler.gpu=0与buffer_frames=1
复跑，共五组15会话／30次输入／15次暂停、新像素／呈现／停止分离／夹具卸载均完成，
每组仍严格exit1。恢复默认后输出477/435/484ms，GPU0为484/503/466ms；buffer1
复跑427/415/398ms，但6次输入P50/P95=211/261ms，未满足200/300组合门槛，
且短样本不能确定整体收益，不写入产品默认。临时Fvp改动已按原字节恢复，两个JAR
未变；GPU和buffer实验仅保留隔离E2E参数，默认不覆盖SDK配置。
独立review指出新增原生指标读取会给首帧计时带入2–6ms；已将startToDecodedMs
取值移到读取前，跨组比较统一使用已存watchBeforeUs，不把这项计时修正当性能收益。
首次观测onVideo与snapshot间隔包含调度／渲染／readback，不是面板或纯GPU耗时；
同PTS重复回调及注册前缺失不能忽略。最终入口严格分析无问题，普通main已恢复，
热重载成功／Dart无运行错误，设备首页已目视后detach；启动Skipped34frames、
SurfaceSync1000ms告警仍在，未计流畅度通过。Gradle已停止，按已有精确清单清理
394项debug输出1484.6MiB，空闲50.0GiB，release／有效缓存／原始证据保留。
目标AVD先确认15个session的JAR无残留及无捕获进程，再正常关闭释放内存；
主控AVD保留普通首页。原始五组数据、修正计时汇总、资源及清理证明保留/tmp。
固定Android16源码还否定无条件drop-input-frames脉冲能“保留最新帧”的假设：
GBS清空全部待输入buffer，包括最终变化，且不更新重复源；可能永久显示旧画面。
此API不清已送入组件的工作，另有实现无效／错误被吞路径；不引入生产补丁或重建
JAR。后续主控渲染/readback与目标编码积压分别定位，严格性能及长稳继续开放。
入口提交`9b5c42d`；完整对照见[视频测量](../../docs/implementation/video-performance.md#首个验证画面的观测与隔离对照2026-10-18)，
分配与清队列的依据见[研究](../../docs/research/scrcpy-first-frame-performance.md#同jar双分配实测与首帧sdk选项2026-10-18)。

本轮已修补公开snapshot的null失败结果：校验官方pub归档SHA-256后，将不含示例／
SDK／构建产物的fvp0.39.1源码置于third_party/fvp，根path override统一两处依赖，
保留许可证／原API及全部平台源码；仅五份MdkSnapshot副本增加null保护，空结果
发送空Uint8List以完成原Dart Future。真实源函数体回归在官方原版SIGSEGV exit-11，
修补后未知handle／null／带stride成功结果通过，另经真实Dart_PostCObject及
ReceivePort确认空与非空Uint8List交付；不是MDK renderer实机崩溃复现。
严格全仓Dart分析无问题。Android实际CMake输入来自vendor；APK libfvp已改变、
libmdk仍为72e5…9c8ad3，两个scrcpy JAR摘要不变，未重建JAR。
静态普通snapshot完成10次暂停恢复／新像素／Flutter图案12／停止分离／卸载，
首帧1469ms、两次输入188/381ms；动态普通snapshot完成200次串行截图4447ms
和10次暂停恢复／新像素／图案12／停止分离／卸载，首帧2901ms、两次输入
1319/1377ms。两组仍严格exit1，不计性能达标；动态命令误传TRACE而真实开关为
TRACE_FRAMES，回执nativeFrameTrace=false，故不声称同PTS trace验证。历史MDK
空std::function崩溃仍开放；本修补不是其根因结论。真实ADB EOF恢复17秒exit0：
3521ms恢复新session、实际图案0→1、主动停止不重建，代理2次accept／1次切断，
夹具／代理／偏好清理均确认；不扩大为真实无线切网／小时级稳定性已验证。
完整Bridge Dart123项通过；静态与动态实际Flutter图案12均已目视。
恢复普通main时assembleDebug611.3秒后安装因设备离线失败；内核09:17:25明确
OOM杀掉目标QEMU6377（RSS约9.1GiB），随后两台AVD均已离线。此前E2E已结束且
清理完成；环境故障单独记录，主控日志另有signal11，不能推断唯一因果。停止
Gradle后仅冷启主控，复用已构建main APK安装1584ms；热重载成功、Dart无运行错误。
只读源码核查还确认暂停补丁使正常首启也create→release→create编码器；先保留为
待量化的首帧候选，未测真实收益前不改JAR，不能解释关键帧后722ms或稳态源年龄。
普通main设备首页已目视并detach；目标AVD暂留关闭，后续同场景测量需重启目标
并恢复25556转发，同时记录宿主内存／AVD RSS，不能与长寿命旧AVD直接作收益归因。
本批精确清理394项已有清单中的debug输出，移除1484.6MiB，空闲50.4GiB；
release／native hooks／Rust／Gradle／CMake／已校验SDK／Flutter哈希缓存及证据保留。
代码提交7cbf010，完整目标及严格性能门槛保持active／未完成。

本轮转向仍开放的原生截图稳定性：普通fvp公开snapshot、动态1280/60/8Mbps
完成30次暂停恢复及实际Flutter图案0，本次无崩溃；首像素2839ms，输入P50/P95
1240/1737ms，保留严格门槛exit1，清理已确认。不能据此关闭历史崩溃。
只读审计确认截图与播放状态/释放未统一排队，诊断snapshot超时会删除仍在途的
请求并重开槽位。Rust真实C ABI槽位回归先红后绿，Dart操作边界4条红后5条通过；
新增有界队列统一snapshot/播放状态，关闭拒绝新操作并将真实stop/detach/dispose
推迟到在途结果交付，3秒后仅报disposeDeferred并保留退役配额。诊断-4改非终态，
不因调用者超时重开native槽位；textureSize await后补关闭检查。
只读review发现初候选会让refresh先于排队的native pause，新生产调用路径回归确实
红；已增加原生提交后的onRequested hook，并等待状态确认与刷新双分支结束，
失败提交不触发刷新。完整Bridge Dart123项、Rust17项、完整App275项（86秒）通过，
严格Dart分析修正1处大括号后无问题，Bridge all-target clippy及fmt通过。
最终普通snapshot静态真实10次暂停/恢复/新像素/呈现/停止/卸载完成，首帧1269ms、
2次输入232/294ms，严格门槛exit1；与App主机测试时间重叠，不用于性能差异归因。
最终动态trace实际200次串行截图（4319ms）及10次暂停恢复完成，暂停175–294ms、
恢复至新像素451–618ms，同PTS关联/Flutter图案12/停止/卸载确认完成，本次无崩溃；
首帧2659ms、输入P50/P95=1234/1455ms，仍严格exit1。两组图案12均已目视，
历史MDK空std::function崩溃继续开放。最终真实ADB EOF恢复17秒exit0通过，3534ms
恢复新session及实际图案0→1，主动停止不重建，接受2次/切断1次，夹具/代理清理完成；
仅证明可控TCP EOF与新释放顺序可共存，非物理无线切网/小时级长稳。
另核实锁定fvp公开snapshot失败路径仍无null结果保护，而MDK头允许失败回调null；
这是独立的依赖缺陷；上批当时尚未触发或修补，现已由上文仓库内补丁及源边界
红绿回归补齐，但仍不等同历史worker空回调。
普通main已恢复，构建14.1秒/安装569ms、热重载125ms、无Dart错误，首页及恢复后
VIDEO1已目视后detach。SurfaceSync1000ms启动告警仍在，不计流畅度验收通过。
Gradle停止后清理395项明确debug输出/本批Rust测试可执行文件，释放1670.1MiB，
空闲51.0GiB；release/有效缓存/原始证据保留。目标无捕获进程/fixture，本批6个
session逐项确认无捕获JAR残留，完整目标继续active。

本轮回到动态源年龄：性能入口补显式codec/encoder实验参数（默认仍H264），
同双AVD1280/60/8Mbps、同AMediaCodec、trace开启且无额外截图压力对比软件AVC/VP8。
AVC基线两轮16次正常新像素、暂停恢复、实际Flutter呈现与夹具清理完成；实际解码
回执H264/AMediaCodec、576×1280。首像素2830/2520ms、输入P50/P95=1331/1592ms，
严格性能失败exit1，不计通过。VP8默认VBR两轮同样16次新像素、暂停恢复、呈现及
清理完成；实际VP8/AMediaCodec、576×1280、无CodecPrivate，首像素2357/2308ms、
输入P50/P95=973/1508ms，仍exit1；不预先切换产品默认。固定AOSP源码确认VP8的
CBR分支会设置CPUUSED=-8。仅临时改变VP8码控的两轮对照完成，尺寸/60fps/8Mbps
和JAR一致，首像素2256/2253ms、输入P50/P95=1135/1546ms，仍exit1且未胜过VP8
默认VBR；16次新像素、暂停恢复、实际呈现及清理完成。临时候选已按原始字节撤回，
补丁仅保留/tmp；不把码控影响全部归因于速度值，不改产品默认编码或帧率。
既有8秒Perfetto继续只读拆分：真正编码在media.swcodec PID639，主线程14829
on-CPU4009.856ms、可运行等待3595.733ms（已观测7656.137ms）；两个目标vCPU
已记录sched均约96.5%以上非idle。后段Surface队列调用约60/s而组件完成25–30/s，
同303个PTS匹配事件首末条件源年龄增长417.364ms。支持调度竞争和完成吞吐退化，
不能把经过时间全算编码CPU或从不同层调用数量推断队列深度。当前JAR无需重建。
三组首轮Flutter动态图案9已目视；两个JAR摘要和manifest保持一致。普通main恢复，
热重载120ms成功、无Dart运行错误，设备首页已目视后detach；仍有启动Skipped34
frames警告，未宣称启动流畅度通过。性能入口严格分析无问题、format和diff检查通过。
Gradle停止后精确清理394项Android debug输出，释放1493.4MiB，空闲51.3GiB；
release、native hooks/Rust/Gradle/CMake及模式不明Flutter缓存和原始证据保留。
目标无捕获进程/fixture，本批6个session逐项确认无遗留捕获JAR，完整目标继续active。

本轮继续MDK读帧稳定性：动态1280/60/8Mbps、trace开启、2轮各200次串行
截图及10次暂停恢复的原路径基线完成（共400截图、20次暂停、8次正常新像素），
同PTS关联及Flutter实际呈现完成，本次无崩溃；首帧3146/2766ms、输入1360/1478ms，
严格性能失败。历史同栈崩溃继续开放。固定MDK头核实to结果按delete回收，Surface
转换能力未有保证；单次next-frame候选实际输出四点全黑，新像素断言失败，已按原字节
恢复源码，候选仅存/tmp。继续真实网络恢复：现有页面只冻结，不自动重建主屏；新
TCP代理E2E初次误省略显式RemoteLaunchIntent，停在路由保护页，属于夹具错误，
不算断网红证据。修正后的真实红阶段确认：代理切断原ADB连接后新accept成功，
设备offline→connecting→connected，但30秒内无新视频会话，初始合成图案0已证实；
清理完整。正在补仅主屏、前台可见且用户未停止的恢复意图；独立应用／unknown
启动不自动重放，显式停止先撤销意图。首个修复候选真实运行又被旧view向已结束输出
发pause的未处理错误打红；改为仅撤销已结束绑定，并补跨await的停止／后台守卫、
迟到提交结果清理、成功reconcile后恢复与activities.stop撤销。新增5项缺陷回归实际
红后绿，最终相关52项widget／SessionViews通过，完整App 275项通过（46秒）；
只读review未发现新增可证问题。最新真实运行3.028秒恢复新session，合成图案0→1
通过，随后测试在清理前卸载了App根组件，导致Bridge已关闭，整条命令仍exit1，
不能算通过。调整夹具顺序且complete置于清理后，原样复验命令exit0、17秒通过：
3.965秒新session，实际Flutter图案0→1，停止后不重建，socket接受2次/仅切1次，
fixture卸载、代理退出和Settings恢复均确认。第二次同版17秒、exit0通过，恢复3831ms，
新会话及合成新像素、停止与清理再次通过。严格静态/动态性能和MDK崩溃仍未关闭；
此次仅证明真实adbd+视频在可控TCP EOF后恢复，非物理无线切网。
普通main已恢复，热重载148ms成功且无Dart运行错误，首页与恢复后VIDEO1全屏已目视；
Gradle停止，清理382项debug输出释放1489.4MiB，空闲51.6GiB，构建缓存/release保留。
目标无本批捕获进程、fixture已卸载；逐一检查本批回执sessionId，没有遗留捕获JAR。
代码`39f62ca`、真实恢复E2E`9c42aff`。后续继续动态上游采集/编码排队和MDK安全读帧，
独立应用任务接续及实际无线切换不由本次主屏EOF通过代替。

最新目标侧分段：同目标AVD、既有JAR、宿主快速排空采集8秒Perfetto，303个实际
`CCodecBufferChannel::onWorkDone(c2.android.avc.encoder#252@ts=...)`逐项匹配收到的原始PTS，
这些已捕获回调无匹配缺项或trace data-loss（原始媒体466包，非全帧完整性证明）。条件源年龄在该回调前全体中位299.213ms、最后1/3为590.659ms；
后者回调→宿主首payload中位区间−5.496至41.228ms（负下界来自校准不确定性）。
原始BOOTTIME／MONOTONIC snapshot差约−0.191至−0.052µs，非严格同步括号；仍保留
源PTS同MONOTONIC和连续运行假设，不叫纯编码CPU或Android呈现时延。
C2Node逐次fence等待最长7.405ms、queue调用11.187ms，本次主要年龄已在CCodec完成回调
之前，不能据此唯一断言具体队列占用。可复跑分析器及三项时钟／缺失数据校验已补，
原始`/tmp/connect-raw-drain-fbf1db6ec385/`。软件AVC没有通过complexity暴露libavc快速档，
不添加无效旋钮；冷阶段并行已落地及复测，完整目标和严格性能门槛保持开放。

冷阶段候选四轮真实Android新像素完成：校验中位399→281ms，完整首像素
1244.5→1097ms，仍超1000ms；16次正常输入及4次暂停恢复／停止／卸载每组均通过。
宿主默认2MiB栈真实应用窗口在HEAD与候选均复现stack overflow／SIGABRT；GDB
定位嵌套启动状态重复内联，生产入口Box::pin后Future由40512B降为160B，同一真实
应用窗口测试已通过，未调整线程栈。最终代码四轮Android复测首像素1247/1198/1166/1074ms（中位1182ms），校验中位330ms；
16次正常新像素及4次暂停／恢复／呈现／停止／卸载完成。输入P50/P95=190/310ms，
首帧及输入P95仍超严格门槛，命令exit1，不能写成全通过。Core lib48通过2忽略、
all-target严格clippy、fmt及只读review通过；Core iOS/macOS/Windows交叉check通过
（非三宿主Flutter整包）。普通main恢复，热重载127ms／无Dart错误，设备首页已目视。
Gradle已停止，精确debug产物清理436项，释放5730.4MiB，空闲52.3GiB，保留缓存及
release／原始证据；目标无捕获进程且夹具已卸载。两项官方探测JAR按摘要及本批崩溃
时间关联精确清理，另一个较早、归属未明的探测JAR保留，不扩大删除。

最新传输批次：Rust ADB新增默认关闭的`delayed_ack`完整字节信用流控，
Core设置`adbBurstMode`仅影响新连接，连接／诊断回执保留实际协商状态；不重建JAR。
完整ADB测试72通过／13忽略、Core153通过／49忽略，工作区all-target严格clippy及fmt通过。
协议回归覆盖协商、正反向流、信用与有界内存、慢流隔离、TLS及关闭尾包；忽略项不计
真实设备证据。双AVD经典／Burst动态新像素对照各两轮16次完成，实际模式均按请求协商。
P50／P95为1224／1493→1324／1670ms，首帧3014／2876→2521／2768ms，严格门槛均失败。
绘制结束→首payload两轮中位界998–1055／893–960ms→933–971／1022–1082ms，
没有消除上游主要等待；Burst保留可选能力、默认关闭，不宣称视频优化成功。
每组两次暂停恢复、真实AMediaCodec新像素／Flutter呈现、纹理分离和夹具卸载通过；
nativeDeleteConfirmed仍false，MDK截图崩溃未因本次通过关闭。原始结果
`/tmp/connect-e2e/video-burst-{classic,credit}/result.json`。

独立宿主快速排空经典ADB视频、移除解码与Flutter后，源PTS→首payload的条件中位界
仍为462–495ms；第二次带目标video线程strace为514–553ms。后者417个媒体头全部按
原始PTS对应857次write，单次最长9.505ms，没有100ms以上写调用。这仅适用于宿主排空
诊断，依赖连续时钟及目标BOOTTIME／nanoTime近零差假设；不是Android真实呈现延迟。
支持继续查采集／Surface输入／fence／编码排队，未证明唯一根因或实际16帧积压。
资料核查及原始路径见[本轮研究](../../docs/research/scrcpy-first-frame-performance.md)。

本批代码`b391cac`；三宿主Rust Core交叉check通过，不代表Flutter整包。
普通main首次构建8.6秒／安装590ms后主控QEMU退出，管理会话exit143，仅见退出流程，
未确定触发源；不将其计热重载通过。恢复同一AVD原数据／SwiftShader后构建6.5秒、
安装1134ms，实际VM热重载124ms成功、无Dart运行错误，设备首页已目视后detach。
性能对照全部来自该次恢复之前，未把恢复后数据混入。SurfaceSync和1504ms启动帧
告警仍在。停止Gradle、精确清理436处debug／非视频测试产物，释放5740.1MiB，
空闲54.9GiB；保留release／native hooks／构建缓存／当前视频与ADB测试／原始证据。
被控无本批捕获／trace进程、实际夹具包不存在；未重建JAR或签名ARM包，原五项用户
未跟踪文件未动、未push。下一段查Surface／fence／编码排队与冷创建，目标继续active。

最新时钟括号批次：默认关闭的`session.clock.probe`用同一主控Rust媒体时钟包住
`exec:cat /proc/uptime`完整响应，独立目标夹具以BOOTTIME／nanoTime／BOOTTIME三读数
夹住输入和绘制。每轮前后三次探针，保留10ms量化和完整往返的不确定区间；仅在本轮
无休眠／VM暂停／恢复／时钟跳变／显著速率差的条件模型下解释，区间相交不证明这些前提。
源PTS同nanoTime原点与速率是额外假设，主结论使用夹具实际绘制结束。

同双AVD默认1280／60／8Mbps、AMediaCodec动态16次及18项目标时间线完整匹配：
绘制结束→主控首payload读取两轮中位下／上界962–1013ms、957–1009ms，区间宽约52ms。
主要等待在已观察到的主控payload读取之前，仍不能单独定位编码器／adbd／更早网络缓冲。
仅覆盖Surface输入上限为15fps、保持max_fps=60及repeat33334µs的临时实验，P50／P95
由1301／1701变为540／1567ms；第二轮绘制→payload中位界161–203ms，第一轮563–626ms。
支持负载／排队方向，未达严格门槛，也不证明编码器为唯一原因；临时覆盖已撤回，
默认60fps和JAR均不变。完整首帧基线3042／2606ms、候选2685／2634ms，均失败。
两组均完成实际新像素、呈现、暂停恢复、纹理分离和夹具卸载，不关闭已有MDK snapshot
崩溃项。原始结果`/tmp/connect-e2e/video-clock-{brackets,input15}/result.json`。
下一项沿Surface／编码输出／adbd边界继续区分排队，并验证能兼顾静态跟手与动态负载的策略；
不能直接把15fps实验设为产品默认或将这批观测记为性能修复。

本批代码`424c40a`。Core真实exec括号2项、Dart区间3项先红后绿，严格Flutter分析4.2秒、
Core all-target clippy／fmt及iOS／macOS／Windows Rust核心交叉check通过，非三宿主整包。
最终分析代码重读两组原始结果，各16个区间及额外PTS相容检查通过。普通main重新构建
55.7秒、安装601ms，实际VM热重载124ms成功、运行错误查询无Dart错误；设备首页和
两组最终VIDEO2纹理已目视。SurfaceSync／跳帧及1441ms启动帧告警仍保留。
停止Gradle后清理380处debug输出及2个APK文件，释放1488.8MiB、空闲60.3GiB；
保留release／native hooks／构建缓存／原始数据／崩溃证据。被控无本批捕获进程或夹具，
两个JAR摘要不变、未重建，原五项用户未跟踪文件未动，未push。

主优先级仍为视频传输、首帧和连接稳定性。`bf4262a`已增加默认关闭的Rust原生同PTS/同主控单调时钟分段，`c058957`补实际Flutter合成面新像素有界校验；`a694b78`使用现有scrcpy重复帧参数和视频Player尽快呈现。没有新增Android呈现代码或重建JAR。

固定双API36 x64 AVD、H264、640/30fps/2Mbps、音频关闭，正常播放观测关闭的4轮80次实际变化：P50 **359→186ms**，P95 **452→241ms**，相同200/300门槛先红后绿。四轮新像素、实际AMediaCodec回执、暂停恢复、释放请求/纹理分离、夹具卸载通过；最大352ms样本保留。该指标为输入到snapshot可读，含轮询/readback，不能当面板扫描时间。每轮静止2秒观察包量保留，不能证明功耗无代价。

冷首帧未改善，默认高清/高动态吞吐、真实ARM硬解/功耗/热、长稳、实际配对adbd切网及视频活动恢复仍开放。先前TCP黑洞及同ID恢复证据仍仅适用于其已测范围。完整研究、失败实验、命令与边界见[视频性能记录](../../docs/implementation/video-performance.md#原生路径分段与持续交互优化2026-10-18-后续批次)。本条不关闭领域05/11或任务07。最终正式RemotePage五编码24秒、Bridge114项、Core lib39/2 ignored及严格分析通过；DTD实际热重启1642ms，关键截图已目视。签名ARM64包63.53秒、增量22.59秒且摘要一致，未物理ARM上机；清理1379.4MiB后空闲63.0GiB，保留release/native依赖缓存。

后续冷启动批次：`67d6fb9`增加可选画质与独立预算，`657990c`复用launcher starttime并在metadata后并行核验完整进程身份与首关键帧。真实同配置三轮的关键帧后Core等待93–97→47–48→0–1ms；两次真实进程STOP/CONT、错误starttime拒绝及断线解冻/退出通过。完整冷首帧没有得到明确改善证据。默认1280/60/8Mbps、实际576×1280与AMediaCodec最终80次P50/P95=**201/248ms**，P50高于200ms、完整首帧1122–1234ms高于1000ms，整体验收仍失败，未调门槛。四轮呈现/暂停恢复/停止/夹具清理完成，不能外推高动态60fps或物理硬解。约16.667ms重复超时试验出现暂停控制超时，已撤回，仍沿用33.334ms超时与原JAR。后续先补冷阶段首次输出及高负载暂停背压回归，任务07继续开放。正式五编码页24秒、真实应用窗口4.37秒与Core40/2 ignored通过；当前签名ARM64构建59.50秒/增量2.40秒、摘要一致，未物理ARM上机。清理1373.8MiB后空闲62.6GiB，被控无残留捕获进程/JAR。

暂停压力后续（2026-10-18）：新增持续变色夹具和每轮1–50次暂停／恢复；默认高清原JAR静态20次通过，动态负载第5／6次暂停确认超时。确定性JVM复现gate打开后暂停请求被consumeReset吞掉的窗口；补pending队列检查后真实动态仍超时，未把局部修复记为整体通过。超时前目标栈显示video仍在dequeueOutputBuffer(-1)，主控最长raw写447µs；再给合作暂停增加100ms输出轮询与完整packet交付后的pending检查，保留清理后ACK、新session/config/keyframe恢复。真实encode无EOS回归先红后绿。仅捕获扩展JAR重建为`b46cd074600c33802dc764df8a9e056271725cb9b51daf4a3494dfffadbbac89`，官方JAR及普通APK不重建JAR的规则不变。最终同APK两轮各20次动态暂停完整通过（40次），暂停148–306ms，恢复新像素410–869ms。

本批提交`5a6cfda`（真实压力）与`91ae381`（合作暂停修复）。捕获JAR可复现校验／JVM、严格Flutter分析5.8秒、正式五编码页24秒及真实应用窗口保留任务4.25秒通过。普通main实际DTD热重启2729ms、运行错误查询无错误，关键截图已目视；启动SurfaceSync和两条旧isolate投递告警仍保留。签名ARM64构建62.74秒／热构建2.50秒、摘要一致，包内嵌入当前JAR已逐字节核对，未物理ARM运行。清理1488.5MiB后空闲62.5GiB，目标无本批捕获进程／JAR／夹具。

**稳定性／性能仍未通过整体验收**：该候选第一次动态运行出现MDK `JNISurfaceTextu`线程SIGABRT，tombstone已留存，后两次通过不能消除该问题；须继续定位，未归因为物理设备或AVD固有限制。动态完整首帧2753–3091ms，输入到新像素1049–1769ms，明显超过既有严格预算；本批40次使用的是功能压力门槛，不能当性能通过。目标夹具自身gfx中位25ms也不支持宣称稳定60fps；全链路吞吐、资源／热、物理ARM、实际配对切网与冷onVideo阶段仍开放。复现、失败和范围见[暂停压力记录](../../docs/implementation/video-performance.md#动态负载下的合作暂停与jar重建2026-10-18)。

原生崩溃定位后续（2026-10-18）：同动态配置额外60次暂停／恢复完整通过（暂停149–343ms，恢复新像素467–850ms），2,000次无暂停串行截图34.475秒全部返回正确计数，但均不关闭崩溃项。匹配BuildId的MDK二进制反汇编已定位到renderer snapshot队列读出空完成回调、在线程入口触发`bad_function_call`主动abort；30fps动态同PTS对照再次出现完全相同地址／BuildId，且本次走Rust C snapshot，不能把问题仅归于fvp Dart完成槽或暂停扩展。此失败没有性能结果。60fps动态16次完整同PTS关联显示输入→relay中位1002ms、relay写0.051ms、relay→onVideo262ms、onVideo→snapshot35ms，主要等待在relay之前；不是已定位网络、目标编码或绘制中的具体一项。JAR与生产播放参数本批未改，仍需安全读回方案与上游进一步分段，严格门槛仍未通过。

30fps同一测试APK复跑16次同PTS关联完成，P50／P95为1335／1613ms，输入→relay中位1035.756ms，没有降低主要等待；首次同栈崩溃仍保留。未改变默认帧率，也未据此宣称只需降画质即可解决。下一项以被控实际输入／绘制时间与原始源PTS关联，继续分清采集、编码和传输，不增加主控原生媒体实现。

本批测试提交`c65105e`。严格Flutter分析5.1秒无问题；普通main构建10.5秒、安装607ms，DTD实际热重载131ms成功，设备首页及动态计数2最终纹理已目视。启动仍有SurfaceSync与跳帧告警，不称启动性能通过；生产源码／JAR未改，无需重打相同release。停止Gradle并清理382处明确debug输出，实际释放1488.5MiB、空闲61.8GiB，保留release／native hooks／Gradle／CMake缓存；新tombstone已复制核对后从设备精确移除。目标无本批捕获进程，夹具已卸载。原五项用户未跟踪文件未动。

目标输入／绘制分段后续（2026-10-18）：`aa9330e`在默认关闭的有界媒体trace中保留原始`sourcePtsUs`，真实HTTP回归先红后绿、16项通过；`e99d4b6`补独立夹具输入／onDraw单调时间、跨轮sequence及驱动完整性校验。60fps动态16次新像素和2次暂停输入均匹配，按键处理→onDraw开始中位0.902ms、回调CPU0.393ms，绘制结束→所观察源PTS间隔67.483ms；后者不是编码完成时刻。报告P50／P95为1308／1707ms，relay前中位1012.366ms。只请求15fps的实验（重复超时随配置变为66.667ms）得到P50／P95=566／911ms、relay前227.061ms，首帧2914／2802ms仍失败，不更改默认画质或外推物理设备。支持负载／排队方向，尚不定位编码输出或ADB各段。MDK截图崩溃未修复。驱动新增采集错误不覆盖原失败：真实故障注入已先红后绿，双故障时原截图错误与卸载成功均保留；仅时间线失败也先保存完整16次视频结果再报错。严格分析8.1秒、Core all-target clippy及fmt通过；本批下一项为默认关闭的Rust ADB读取／raw写出／relay同PTS分段，无需重建JAR。

本批收尾：普通main首次安装因原主控QEMU进程已退出而失败，未计通过；恢复同一AVD／原SwiftShader后端及原数据后，热构建6.7秒／安装979ms、实际DTD热重载123ms成功，错误查询无Dart运行错误，设备首页及实际动态计数2截图已目视。原生启动仍有SurfaceSync／跳帧告警，未视为首帧达标。所有性能数字均来自恢复之前，恢复后未做可混比的性能采样。临时故障代理已删；停止Gradle，清理382处debug输出，释放1488.5MiB、空闲61.4GiB，保留构建缓存／release／崩溃证据；被控无本批捕获进程或夹具，原五项用户未跟踪文件未改。

传输分段后续（2026-10-18，`b2c2993`）：新增默认关闭、最多256条的Core `transportTrace`，按原始
source PTS关联完整scrcpy包读完、raw写入及relay时钟；配置包不占条目，captureSegment
只表示捕获分段，不冒充renderer代次。真实分段ADB→生产run_video→TCP回归先红后绿，
同组4项含既有超时／取消通过；严格Flutter分析4.8秒、Core all-target clippy及fmt通过。
关闭观测没有逐帧取时钟、分配记录或新增写锁，仍有少量条件／flags解析开销。

恢复后的同一双AVD、1280／60fps／8Mbps持续动态请求，AMediaCodec与FFmpeg各2轮16次
真实新像素、2次暂停恢复、实际Flutter呈现／纹理分离及18项目标输入绘制匹配完成。
严格门槛仍失败：AMediaCodec P50／P95=1310／1699ms、首帧3636／2814ms；软件对照
1098／1549ms、首帧2102／1848ms。relay→onVideo中位233.155→4.025ms，但输入→relay
均约1067ms；没有修改默认后端。原生路径完整包读完→relay中位0.123ms、raw写0.049ms，
不支持在该段继续堆缓冲参数。**ADB整WRTE收齐后才向AdbStream交字节**，新读区间遗漏
首WRTE先前接收／排队，不能由其较小排除网络或ADB积压；下一项补该实际接缝观测。
只读复核发现的收据异步发布竞争已改为计时结束后最多1秒等期望PTS，重复仍失败。
数据与后续最终代码复跑见[传输分段记录](../../docs/implementation/video-performance.md#adb消费raw转发与解码后端对照2026-10-18)。
这是诊断增量，未解决高动态性能或已有MDK snapshot崩溃。两个JAR摘要均未改变，
本批没有重建；普通Flutter／Rust打包继续嵌入既有产物，完整门禁的显式可复现重建另算。
最终有界等待／命名版AMediaCodec再跑2轮16次及18项时间线均匹配、暂停／实际呈现／卸载
完成；P50／P95=1259／1968ms、首帧3256／2862ms仍失败，未把功能完成当性能绿。
普通main构建9.2秒、安装620ms；DTD发现未找到CLI App，改用真实VM WebSocket连接后
热重载241ms成功、运行错误查询无Dart错误，设备首页及最终计数2实图已目视。
SurfaceSync与1421ms启动帧告警仍在，不称启动流畅度通过。停止Gradle后清理382处debug
输出，释放1488.6MiB、空闲61.0GiB，保留release／native hooks／构建缓存／原始证据；
被控无本批捕获进程，夹具已卸载，原五项用户未跟踪文件未动。

ADB整包接收观测后续（2026-10-18，`2f54b91`）：独立Rust库补逐stream、默认关闭、恒定收据存储的
`set_read_trace_clock`／`read_trace`，Core记录首／末WRTE的payload读取、路由及首次消费，
沿用主控同一单调时钟。订阅token隔离换时钟／停用后的在途及排队收据，字节和ACK语义
不变；无订阅时新WRTE不采时钟或加路由查询锁，仍有原子检查和可选字段开销。真实协议
回归先红后绿，完整ADB52项／13 ignored、Core同组4项、all-target clippy与fmt通过；
只读review未发现确定问题，三宿主Core交叉check结果另见记录，不等于整包链接验收。

同环境1280／60／8Mbps动态请求，2轮16次新像素与18项目标时间线完整匹配，2次暂停、
实际计数9／2呈现和卸载确认完成。20个实际首末WRTE的payload读中位0.256ms、最大
9.252ms，路由→首次消费0.014ms、最大0.034ms；首WRTE已读完→scrcpy首字节中位
0.019ms。输入→relay仍1002.445ms，报告P50／P95=1268／1584ms、首帧3138／2840ms，
严格失败。这组证据不支持该一秒花在已测的整包读取或消费队列，但起点在ADB头读完后，
仍不能区分编码输出、adbd排队与更早的传输／头等待。下一项建立带误差界的目标源PTS
与主控时钟关联，不能直接相减未同步的两端时钟。已有MDK snapshot崩溃未修复。

只读研究复核AOSP Burst仍需显式启用、双方协商及完整有符号字节credit；本库尚未支持，
继续经典模式，不只改feature或扩大队列。固定一手来源和必要回归回填
[ADB研究](../../docs/research/adb-host-and-connectivity.md#24-burst-mode复核与当前实现差距2026-10-18)，
新实测及边界见[整包记录](../../docs/implementation/video-performance.md#逐wrte接收与消费实测2026-10-18)。
本批无Dart／Android主控原生呈现改动，没有重建或改动两个scrcpy JAR；这是诊断与研究
增量，完整目标／性能／稳定性继续开放。
Core对aarch64 iOS／macOS及x64 Windows交叉check分别3.94／3.86／3.87秒通过，仅编译
检查，不冒充三端Flutter整包链接。普通main构建9.1秒／安装592ms、实际热重载134ms及
运行错误查询完成，设备首页及最终计数2图片已目视；SurfaceSync、跳帧及1432ms启动帧
告警仍保留。停止Gradle，清理382处debug输出，释放1488.7MiB、空闲60.5GiB，保留
release／native hooks／构建缓存／原始性能及崩溃证据；被控无捕获进程／夹具。

## 状态口径

- **已落实**：只对列明的实现与已通过证据成立，不外推整个领域完成。
- **部分**：已有实现或真实证据，仍有明确交付缺口。
- **进行中**：本轮存在改动／复现，尚未完成相应验收。
- **未实现**：源码或产品链路缺失；不能用“设备不支持”代替。
- **未验**：已具备实现或候选路径，但指定环境／故障／产品步骤尚无通过证据。默认忽略的真实用例不计通过。

## 12个领域逐项现状

| 领域／需求与流程 | 当前已落实的范围 | 未闭合范围与下一次可执行验收 | 既有任务 |
| --- | --- | --- | --- |
| 01 设备与首次设置；R02/R19/R53–R54，C01–C05/C30 | **部分**：固定设备列表、连接表单和真实诊断；隔离secure=1 API36上真实表单错码拒绝→PAKE→独立端口TLS→系统接口撤权后旧身份拒绝，两轮64秒 | **未验**：QR／发现／USB、码过期／切网／后台、旧系统USB转无线、量产OEM。直接Settings Forget持久化仍失败；设备最近信息时间、同物理设备USB／无线身份归并及工作台功能分级入口仍未闭合；A52后台候选遍历、更新／撤销与ABA代际保护已接通并有七项真实DNS-SD／TLS证据；首次配对快速发现仍取首地址，物理切网等仍未验，首次步骤／用时也须实测。**已落实的局部**：中文授权／配对验证／中断提示和实际重新配对入口经本轮真实安全AVD完整66秒通过；保留同设备、清空端口／码、错码无GUID、fresh码PAKE／TLS及精确撤权拒绝，关键截图已目视。其他首次设置矩阵继续开放 | [04](issues/04-compatibility-capabilities.md)、[05](issues/05-ordinary-user-onboarding.md)、[15](issues/15-identity-trust-and-transports.md)、[20](issues/20-android-validation-bench.md) |
| 02 Rust ADB与信任；R08–R11/R40，C04/C06 | **部分**：独立库不调用外部adb，主要协议／服务、无线互通、Required TLS和发现→表单→Core类型保留及拒明文负例；安全AVD首次正负例已有证据 | **未实现／未决**：完整公开服务契约；README排除typed forward／包管理／delayed ACK／incremental／5037与任务01边界未闭合（A47）。可运行协议fuzz入口尚缺；当前TLS provider为alpha且上游明确不供生产，RSA时序风险尚未解除；纯Rust实现不能等同生产安全。A58旧mDNS解析器panic已按上游修复锁定0.21.2，离线回归及新锁版真实DNS-SD／TLS七项通过；daemon异常关闭后的清理／重建仍缺。**未验**：Wi-Fi2、成熟生产密码链、锁定OEM／重装／四端密钥保护。下一步逐服务给API／参考／差异／关闭条件，区分实现缺失与合理范围 | [01](issues/01-adb-contract-and-wireless.md)、[02](issues/02-pure-rust-crypto-dependencies.md)、[15](issues/15-identity-trust-and-transports.md) |
| 03 四端与工程；R06–R07/R13–R15/R55–R59 | **部分**：monorepo、FRB、Hooks／生成Riverpod、typed路由与严格分析；Android armv7／arm64／x64整包已有本地通过，生成及部分JVM门禁存在 | **未验**：iOS／macOS／Windows宿主整包和最终链接、平台资格、干净检出。**部分**：A46已配置--android，三ABI APK、两份JVM runner及实际打包manifest／ELF本地通过，损坏arm64 ELF负例被精确拒绝；远端job／分支保护未验。FRB／companion／MDK原生产物闭包仍缺。下一步在干净远端job复验并推进四宿主产物 | [03](issues/03-workspace-bridge-platform-builds.md)、[19](issues/19-dependency-license-and-updates.md) |
| 04 手机远控与真实应用；R03/R12/R20/R23–R25/R51，C07–C09/C32 | **部分**：全屏、触控、三真实会话保留／切换／精确关闭、窗口工具和可见设备归属。**部分**：主屏应用接续复用原会话，双AVD主屏＋两应用窗口51秒／9个独立进程与任务checkpoint及实际Settings像素／截图通过。A49已在未断链的已测路径补固定unknown身份、只读检查、核验入口及阻断主屏绕过该独立窗口记录，10项应用widget／38项生命周期回归与2项真实Runtime通过；副屏失败主屏回退的真实UI与实际解码故障仍未验；A49／A50本批已补私有持久操作账本、断开保留、Runtime重建转unknown、主屏独立操作身份与恢复核验门禁；真实Android公开Runtime四项50.17秒通过，含丢ACK、排队关闭后迟到ACK、写盘失败及deviceId精确关闭。主屏页面核对／关闭不等待旧输入清理，49项应用／生命周期／会话窄回归通过。Android杀进程现场、实际解码故障和完整恢复仍未验 | **部分修复／进行中**：A43退出pause拒绝／挂起实际先红，非阻塞离页修复后32项生命周期／会话视图回归通过，悬浮退出／系统返回×失败／挂起4组合通过；旧挂起队列可能阻塞同session重进，真实故障UI仍待验。**部分**：本机IME焦点／composing-only提交与emoji已修，43项远控／通信回归和实际原文插入30秒通过；A59已按目标先绘制＋750ms后主控／延迟两次实截图复验，31秒通过且原文已目视；实际中文键盘候选／密码／选区／横屏仍待验。**未实现／未验**：真实迁回／多实例、最近／常用与真实应用标签／图标、系统分屏／大屏并排。A45已修向内拖开保持展开／最近侧边／安全区，8项组件与真实产品25秒回归通过；下一步继续挂起／拒绝／系统返回及未知启动不重发的真实故障验收 | [06](issues/06-server-orchestration.md)、[08](issues/08-mobile-input-and-windows.md)、[18](issues/18-complete-design-state-coverage.md) |
| 05 媒体、声音与资源；R16/R22/R26/R39/R60，C10/C25/C28 | **部分**：共享fvp／MDK五编码、PCM／双设备焦点、HOME／旋转／同UUID恢复；按官方首帧文档修复；真实页选择1080后HEVC486×1080通过实像素门槛 | **未决／未验**：1280低清根因／默认策略、冷启动总耗时、触控到像素P50/P95/P99、丢帧、长期／热／功耗、物理声音／路由。**未实现**：共同音画时间基／同步调度（当前音视频各自取首PTS、独立Player），以及新／非焦点窗口资源降载完整策略；下一步固定设备与场景测端到端延迟和资源不足，保护已有活动 | [07](issues/07-fvp-media-pipeline.md)、[12](issues/12-calls-and-audio-arbitration.md)、[16](issues/16-glass-and-performance-budget.md)、[20](issues/20-android-validation-bench.md) |
| 06 通知与原应用；R33–R37，C18–C21 | **部分**：免APK listener、持续观察／独立停止、原PI／清除／失效保护、主屏复用；跨页回复有界保护及独立receiver原文count1；API36真实后台OS发布／精确撤回／通知栏点击后当前内容呈现 | **未实现／未验**：完整锁屏／应用认证后重取并重验、拒权／渠道／冷启动／系统停止／OEM及真实来电提醒、真实聊天服务一次接收／进程死亡恢复。下一步实际关闭渠道／撤权与认证完成后重验，不能重放未知回复 | [11](issues/11-notifications-continuation.md)、[14](issues/14-background-and-recovery.md)、[18](issues/18-complete-design-state-coverage.md) |
| 07 通话；R26/R32/R39，C22–C24 | **部分**：聚合状态与受限提示、危险全局动作明确拒绝；已补当前系统通话界面接续，实际Runtime9.94秒及正式CallsPage→来电提醒→当前界面→全屏原通话像素16秒均通过，同一呼叫仍ringing，未新增逐call控制或通话音频 | **未实现**：安全绑定具体呼叫的接听／拒接／挂断与真实双向通话音频。**未验**：PSTN／VoIP、同设备多呼叫／多SIM、耳机／麦克风／转手机／结束恢复；下一步固定具体call身份及物理HAL对照，安全拒绝不能算功能完成 | [12](issues/12-calls-and-audio-arbitration.md)、[20](issues/20-android-validation-bench.md) |
| 08 文件与传输；R28–R30/R38，C11–C14 | **部分**：目录／基础管理、双向传输、三选一远端冲突／本批策略、无覆盖发布、有界搜索；A44已实施精确原件／操作的持久保存账本，13项Runtime重开／并发／限额／落盘失败及跨页unknown回归通过。双AVD取消→保存→离页重进恢复saved→分享43秒通过，独立63字节／hash／grant及重进截图已核验 | **未验**：Android实际写入中杀进程／unknown恢复及切设备迟到回执；Runtime重开不替代此证据。**部分**：已有批量选择、目录扫描／导入／导出与批次进度代码，最终交付和异常闭环未验。**未实现／未验**：浏览分类完整体验、provider／非seek／云盘／空间／撤权、恢复意图及外部分享打断系统选择器（A55）。A48系统provider冲突已迁到共享协调器与Flutter页面，按operation／conflict身份决定并支持本次后续策略；多USB设备选择仍由Kotlin产品AlertDialog决定。系统目录冲突真实E2E最终r5完整3分02秒通过并核验文件／零成果标题，前几轮夹具及第四轮目视发现的误报均保留记录；下一步继续实际中断与USB共享选择 | [09](issues/09-file-endpoints-and-recovery.md)、[14](issues/14-background-and-recovery.md)、[19](issues/19-dependency-license-and-updates.md) |
| 09 相册与预览；R31，C15–C17 | **部分**：缩略图／旋转／单项大小和并发限制；真实网格JPEG／MP4→原件预览→准备→系统取消／保存／分享，字节／hash／授权／双MIME；视频时钟／暂停／定位／静音 | **部分**：A51已接512MiB预算／淘汰、正式清理页和活动原件租约，真实Core与正式双AVD页面13秒通过、独立字节／删除核验全true；持久外部分享保留、预算调整入口及大文件／长稳仍待闭合；A53本批已接动态共享目录扫描、权限空DONE复核、部分结果、冻结快照分页和mtime；10项公开Runtime协议fixture、7项公开页面测试及真实105原件双AVD85秒链路已通过；目视新发现A57已补共享调度／精确取消／有限重试，9项公开测试及真实15＋21张可见网格解码通过，完整异常／长稳仍待验，持续增量／其他用户和卷等仍独立说明；持续增量及实际大原件准备进度／取消、批量、全格式／损坏／缓冲／结束／断线／源变化／空间矩阵；无音轨MP4不证明物理音频。下一步大原件中断／离页取消，先验证准备活动与残留 | [10](issues/10-gallery-video-and-content.md)、[09](issues/09-file-endpoints-and-recovery.md)、[18](issues/18-complete-design-state-coverage.md) |
| 10 剪贴板与分享；R27–R28，C26–C27 | **部分**：文本跟随／固定／隔离与普通主控后台停读、专用页返回正确跟随；外部九模式导入／取消；出站文本／JPEG／MP4真实Sharesheet和独立receiver | **部分**：外部PNG→显式选A→切全局焦点B→一次提交，实际三AVD14秒通过，独立核验A字节／hash且B不变；两次刷新不重传。**未实现／未验**：图片／文件剪贴板URI授权生命周期、系统本机打开、批量／大原件、授权撤回／中断。下一步继续撤权／中断及同型号设备区分，不把单PNG外推完整分享 | [13](issues/13-device-targets-and-sharing.md)、[09](issues/09-file-endpoints-and-recovery.md)、[20](issues/20-android-validation-bench.md) |
| 11 后台、恢复与活动；R21/R38–R40，C28–C29 | **部分**：不可见视频协作暂停、主动声音／Activity重建、同runtime水位快照校准和过期播放器清理、主标签核验重试；回复跨页保护；A44系统保存持久账本及重开pending转unknown，真实saved离页重进通过 | **未实现／未验**：断网／换网／进程死亡／系统Stop／重启的完整活动意图与恢复资格；A23已接设备音源活动投影、精确sourceId独立停止与本地Player释放；真实播放→确认停止→连接／观察保留9秒通过。任务仍需按具体活动核对。Android写入中杀进程的unknown恢复仍未验。下一步活动×中断原因矩阵逐格注入并核对主动停仍停／未知副作用不重放 | [14](issues/14-background-and-recovery.md)、[15](issues/15-identity-trust-and-transports.md)、[20](issues/20-android-validation-bench.md) |
| 12 设计、易用性与研究；R01/R41–R50/R52，C01–C32 | **部分**：同一pen **93独立页／12类／26母组件／588实例／153变量**，保存重开核对；新tch6A／qTeGO；浅色／黑中性／小彩色／Lucide、全屏共享组件；实时背景折射已实现并有实际视频截图 | **未实现／未验**：全部状态与实际UI闭环、可打断液态形变、独立光学／视频性能／大字／读屏／高对比／减少动态矩阵、token全覆盖；A45内拖已通过组件与真实远控验收，TalkBack／完整无障碍仍未验；OPPO／vivo地区与端角色操作证据，Apple自身连续互通官方流程研究（A54）已补，实操未验；当前实际依赖的逐库契约／版本差异未闭合（A56）。下一步按coverage逐流程补入口→操作→失败→恢复并对照真实UI；相册范围面板短内容高度／灰色材质仍有实际视觉差距，93页静态完整性不等于实现验收 | [16](issues/16-glass-and-performance-budget.md)、[17](issues/17-manufacturer-mobile-flows.md)、[18](issues/18-complete-design-state-coverage.md)、[19](issues/19-dependency-license-and-updates.md) |

## 证据入口与优先顺序

1. **按用户最新要求渐进交付**：每批完成一条可用产品链路及对应必要验收，再推进下一条；尚未覆盖的边界明确留账，不围绕同一项反复扩展细节。新增明确的数据安全／重复副作用或崩溃问题优先处理，普通视觉细化不长期阻塞功能推进。
2. **下一批顺序**：A23活动列表的音源独立停止已完成本批链路，入站分享指定设备PNG真实链路也已通过，本机IME已提交文字和当前系统通话UI接续也已有本批证据；A59本批限定时序实截图已通过；正式通话页接续16秒E2E及release签名／实际安装已完成本批验证，接着推进A51缓存与USB共享选择，继续其余完整目标。各批保留精确对象、操作结果及失败出口；物理设备或其他宿主专属证据单独登记。
3. **按风险验收并阶段汇总**：局部改动先跑相应公开边界回归和可运行真实链路；完整工程门禁用于阶段汇总／依赖与打包变更，不把每个低影响细节都展开成新一轮全量测试。A43／A44／A49恢复、A48 USB共享选择、A51缓存、动态视觉／无障碍／性能、生产密码与四宿主等未闭合项继续按原任务推进。

| 证据 | 可复现入口／实际边界 |
| --- | --- |
| [首次安全配对](../../docs/implementation/first-pairing.md) | 真实产品表单、系统API精确撤权；直接Settings Forget失败原样保留，不称量产安全验收 |
| [总验收记录](../../docs/implementation/validation.md)、[状态恢复](../../docs/implementation/state-recovery.md) | 命令、失败、完成回执与截图路径；同runtime校准不等于断网／进程恢复 |
| [内容交付](../../docs/implementation/content-delivery.md)、[搜索](../../docs/implementation/file-search.md) | 单项文本／JPEG／MP4与搜索已有真实结果；A44新增持久账本与真实saved页面重进，Android杀进程unknown仍未验；首次重进夹具失败未计通过 |
| [系统提醒](../../docs/implementation/system-notifications.md) | 真实OS投递／撤回／点击；仍保留权限／认证／冷启动等矩阵 |
| [主屏应用widget](../../apps/connect/test/app_launch_test.dart)、[公开Runtime真实测试](../../crates/interop_core/tests/app_launch_android.rs) | 10项应用widget／38项生命周期回归；真实Runtime两项及双AVD51秒通过，独立display0／9个进程checkpoint、主屏同ID与实际Settings截图；旧宽松截图不计视觉通过，跨进程unknown与真实失败回退仍未验 |
| [Pencil覆盖](../../designs/prod/coverage.md)、[交互规则](../../designs/prod/interaction-rules.md) | 当前95页静态结构与产品规则；实际实现和动态验收逐项单独核对 |

## 历史与更新规则

[重新核查第12.1节](completion-reassessment.md#121-可见会话的每一次输入如何落到要求)保留逐指令追溯；A01–A42、最初R/C表及历次批次是历史证据。持续观察、系统提醒、共享折射、单项系统保存、搜索、首次安全码配对已有后续成果，读取旧缺口时必须回到本页判断。A43–A49是本轮新增发现，编号回填原20任务，不另造平行任务。

当前本地Android整包通过与CI持续门禁、静态设计与动态产品、AVD授权与生产密码、同进程恢复与进程重建分别判断。只有所有[完成门槛](goal.md#完成门槛)满足后才可把目标改为complete；本轮继续active。

本轮复验：应用195项测试通过（15秒，`/tmp/connect-full-audit-app-tests.log`）；严格分析先发现5处缺少花括号，修正后无问题；build_runner生成一致性143输入通过（10秒）。退出修复本地提交`0bf9cb1`；设计补页本地提交`6d00d71`。普通main重新构建安装，实际R热重启1,401ms并截图检查设备列表空态；仍有两条FRB旧isolate告警及SurfaceSync／跳帧日志。该启动检查不代替真实断线退出E2E或全页面视觉验收。

后续本轮验收：A44批次`e75bf60`、A45批次`2045d1a`、应用接续／A49批次`a4f5fd6`。真实系统交付43秒、内拖远控25秒、主屏接续＋两窗口51秒已通过并目视最终关键截图；此前路由／pause时序失败及HOME／空白启动面宽松截图均未计通过。整条`tool/check.sh --android`最终退出0，`/tmp/connect-lifecycle-all-gates-final.log`：应用212／Bridge102／设计系统3、Rust176 passed／49 ignored、生成143输入／严格分析／clippy／DESIGN lint、三ABI APK／4组native main／实际manifest和ELF均通过。损坏arm64 ELF负例另行精确拒绝；DESIGN保留31警告／1信息。远端CI和其余三平台整包没有通过证据，中文连接提示在该历史批次仍属在途，后续结果见本批实施复验。

本批普通main另行实际安装启动并R热重启1,417ms，设备列表空态截图`/tmp/connect-lifecycle-main-restarted.png`已目视后detach；保留两条FRB旧isolate及SurfaceSync／跳帧日志。未夹带原先未跟踪的clipboard／documents／input测试与examples，也没有push。


## 本次全会话再审计结论（实施前快照）

12领域仍均属部分交付，不能用测试总数或89页代表完整目标完成。本次补回A49同runtime断链丢失unknown，新增A50主屏启动结果、A51媒体总缓存、A52发现备用端点、A53相册假完整范围、A54苹果自身互联研究、A55新分享打断系统picker、A56实际依赖契约及版本／fuzz缺口。A48范围还包括原生USB产品选择，A23独立活动缺口收窄到实际尚缺的音源，音画同步明确为尚缺共同时间基／调度实现。

完整证据、每项关闭条件及全部领域剩余交付见[重新核查第22节](completion-reassessment.md#22-用户再次要求逐指令逐文档逐设计核查)，已回填原20任务中的13项，并补回任务04的兼容分级映射。ADR／路由所有权／SAF研究的错误当前指导、规格与prod计数及遗漏覆盖条件已纠正。

本次通过Pencil对象API重新核对89页／12类／26母组件／557实例／153变量；可见裁切、页重叠、断链ref和非Lucide节点无命中，全部页面按组查看概览，预览仅在临时目录。静态结构符合不代表真实UI逐页／动态液态玻璃／无障碍／性能通过。没有修改仓库pen，没有新跑测试／构建／AVD故障，也没有修复上述新增代码缺陷；既有未提交连接提示与未跟踪文件保持原样。

下一批优先修A49／A50的未知启动证据丢失和重放风险，连同A43退出重进、A44真实中断覆盖；随后闭合发现／内容／音源／共享选择界面。完整ADB、生产密码、四宿主、通话、IME、动态设计和性能继续独立推进，不因本轮审计结束停止完整目标。

## 本批实施复验（继续 active）

- **A49／A50**：新增私有启动操作账本、主屏独立操作 UUID、断开保留和 Runtime 重建核对；真实 Android 四项 50.17 秒通过，包含真实 ACK 丢失／阻塞、排队取消、写盘失败、设备级关闭。主屏页面 49 项窄回归覆盖先断开再返回 unknown，以及 key-up／pointer-cancel／pause 挂起时仍可核对和精确关闭。细节与未验边界见[应用打开恢复](../../docs/implementation/app-launch-recovery.md)。
- **A52**：已接候选遍历、更新／撤销及代际保护，缓存只留可信 GUID／每 GUID 八个活动服务；真实 DNS-SD／TLS 七项最终 89.08 秒通过，cached 旧连接发布错误先红后绿。仍缺首次配对快速路径候选遍历、物理换网、IPv6 scope 和 Wi-Fi2；见[无线重连](../../docs/implementation/wireless-reconnect.md)。
- **A48**：共享系统保存冲突已实现，USB 产品选择仍待迁移。真实 E2E 第四轮完整通过 3分02秒，独立核验原件／副本／空目录、跳过／取消／离页及旧决定隔离；此前入口识别和回执字段夹具错误未计通过。目视又发现全部跳过却显示“部分已保存”的真实文案问题，先红后绿修复；r5完整3分02秒通过，实际零成果标题已目视。

本批最终整条tool/check.sh --android退出0（/tmp/connect-oct17-all-gates-r3.log）：应用230／Bridge106／设计系统3、Rust176 passed／58 ignored、146输入生成一致性、严格分析／clippy、三ABI整包及四组native／实际manifest和ELF检查通过。DESIGN lint仍31警告／1信息，Kotlin有原先非空断言警告，不称零告警。中文连接真实配对UI已通过；普通 main 已实际重新构建安装并R热重启1,982ms，设备列表空态已目视后detach。新增Rust核心对iOS／macOS／Windows交叉check通过（/tmp/connect-oct17-core-cross-checks.log），不是宿主Flutter链接。其他十二领域与二十任务继续开放。

A54已补[Apple自身连续互通工作流](../../docs/research/apple-continuity-workflows.md)，区分Mac镜像、通知、Handoff、内容发送、独立通话及FaceTime移动端获允远控；引用十二个Apple一手页面，未实操Apple设备，不改变既有免APK／主控不开调试／短信原应用等范围。

- **中文连接反馈**：`82a8fb8`，16项公开表单／组件测试及严格分析通过。实际安全AVD首轮暴露auth失败英文遗漏，修复后完整66秒通过，`/tmp/connect-e2e/connection-feedback-r2/result.json`所有必需项为true／hostErrors为空／独立清理完整；真实重新配对与撤权中文截图已目视。直接Settings Forget与OEM、切网等范围仍未验。

最终普通入口截图`/tmp/connect-oct17-main-restarted.png`：设备列表固定首屏、浅色黑色主动作、紫色小图标与玻璃底部导航可见。普通启动16.4秒构建／683ms安装；CLI实际R热重启1,982ms，随后detach。仍有两条FRB旧isolate投递告警及SurfaceSync／启动跳帧；该首页检查不替全部设计／光学／无障碍／性能。没有push，也未夹带原先未跟踪的真实测试／examples。

## 本批相册、缩略图与实际锁版复验（2026-10-18）

- **A53部分交付**：代码`513fb38`接动态当前用户主共享存储、read／execute复核、部分结果、mtime稳定快照分页、精确取消和换设备隔离。10个公开Runtime fixture及7个公开页面测试通过；目录溢出丢空、fallback失败漏预算、64issues后预算panic均先红后绿。真实105原件目录／分页／刷新及独立字节核验通过。持续增量、总磁盘预算A51和真实大原件／拒权／回收等仍缺。[契约与证据](../../docs/implementation/gallery-index.md)。
- **A57局部修复**：`7654619`共享有界串行队列、UUID取消、keepAlive重进防重叠及有限busy恢复。8cell并发8的公开红测已修，9项新公开测试及严格分析通过，独立review无新证实问题。真实第四轮1分59秒，首屏15张／滚动后21张每个可见缩略图均解码；105原件范围／分页／刷新／宿主原文与全部大小／精确路径清理全true、hostErrors为空。关键网格已目视，不再用单张证明网格可用；低内存／长稳／实际中断继续待验。
- **源稿与实际视觉**：设计`f264bf1`同一pen补四个相册代表状态；保存关闭重开核对93页（91手机＋2大屏）／12类／26母组件／588实例／153变量，无断引／缺变量／重叠／可见越界，预览只在/tmp。实际范围面板零未读仍接近全屏，空白及灰色材质层次尚需优化，未称该状态整体视觉通过。
- **A56／A58部分处置**：`e776065`将生产及测试mdns-sd从实际0.17.2统一精确0.21.2修复HINFO越界panic，无发现适配源码变更。上游离线原回归1项、窄编译、新锁版实际DNS-SD／TLS七项77.36秒通过。未向共享5353注入坏包、未声称本地旧版红测；Core发现daemon关闭后的清理／重建、其他新版本修复和其余直接库契约继续开放。[实际锁版研究](../../docs/research/locked-mdns-contract.md)。

当前完整`tool/check.sh --android`退出0：`/tmp/connect-gallery-mdns-final-gates.log`。应用246／Bridge106／设计系统3、Rust186 passed／58 ignored、152输入生成一致／208文件格式零修改、严格分析／clippy／lint负例／capture JAR与JVM、三ABI APK184.1秒／四组native main／实际manifest和ELF均通过。默认ignored不计通过；新锁版真实七项另行显式执行。DESIGN仍31警告／1信息，原有Kotlin警告保留。

新锁版Rust核心对iOS／macOS／Windows交叉check分别4.24／4.18／8.26秒通过（`/tmp/connect-mdns-safe-core-cross-checks.log`），不是对应宿主Flutter链接或整包。普通main实际构建15.2秒、安装881ms、R热重启2,929ms，`/tmp/connect-gallery-mdns-main.log`；设备列表空态截图`/tmp/connect-gallery-mdns-main-restarted.png`已目视后detach，保留两条FRB旧isolate告警，不以首页代全页／光学／无障碍／性能验收。

本批仍无任何领域整体完成；十二领域与二十原任务继续开放。原先未跟踪的clipboard／documents／input测试与examples没有夹带提交，没有push。

## 渐进交付：设备声音独立停止（A23）

设备声音按精确sourceId出现在当前活动，确认只停止该音源，Core发状态事件并移除捕获，本地fvp输出释放完成才回复；旧活动不能停止替代音源。Bridge同时纠正activities.stop参数名，合并事件与请求并发触发的同音源close。公开Runtime两设备协议fixture与Flutter活动页／音频输出窄回归通过；播放状态中文漏映射先红后绿修复。

真实主控＋被控AVD第三轮9秒通过（`/tmp/connect-audio-activities-r3.log`、`/tmp/connect-e2e/audio-activities-r3/result.json`）：实际PCM及fvp时钟前进，页面确认停止后Core源和本地输出均消失，连接／通知来电观察及基线媒体保留，精确清理全部true。播放／确认／停止后三张截图已目视。首轮误把异步starting当终态、第二轮普通main构建遗留的测试插件注册缺失均未计通过；离线pub get恢复自动注册后通过，无生产原生代码改动。

只验收本批链路，不冒称物理声音、双向通话、进程死亡恢复或新一轮完整门禁。前一批三ABI留存APK和全门禁属于A23之前的源码。本批通过后即推进入站分享，剩余活动中断矩阵继续保留。

## 渐进交付：外部PNG送到指定设备（2026-10-18）

新增独立入站分享目标E2E：外部provider pipe／read grant／ClipData导入→页面显式选A→公开全局焦点切B→确认提交。实际三AVD首轮14秒通过，构建52秒／安装745ms；`/tmp/connect-incoming-share-target-r1.log`、`/tmp/connect-e2e/incoming-share-target/result.json`。宿主以不同AVD名与两端独占marker核对端点映射，独立读取A的68字节和SHA-256、确认B同路径不存在、消费后两次刷新仍只有原传输，清理全true。截图已目视；本批沿用已有页面和固定目标实现，未新增产品平台代码。

视觉仍有边界：两台同型号默认名称一致，当前选项只显示名称／连接状态，实际使用需要改善区分线索；现有灰色平面和玻璃层次亦不能因此算完整视觉通过。批量、大小／媒体组合、撤权／断线、picker被新分享打断仍留原任务，下一批转IME。

## 渐进交付：本机输入与当前通话界面（2026-10-18）

本机IME修复composing-only漏提交、明确焦点请求和失效缓存清理，实际系统Settings精确接收你好🙂一次、组合中不泄漏、延迟不重复和查询清理30秒通过；43项远控／通信回归、最终严格分析通过。**完整视觉未过**：A59主控截图尚未反映提交文本，被控原件已更新，需要对齐实际绘制时刻／媒体PTS，不能以原件文字通过代替动态画面跟随。[范围、命令与历次失败](../../docs/implementation/mobile-ime.md)。

通话新增calls.open仅打开手机当前系统通话界面；真实Runtime最终9.94秒通过，独立确认InCallActivity前台、来电仍ringing、旧动作不能结束替代来电。页面成功／失败回归通过，正式通话页→全屏像素E2E仍待验，具体call控制和双向音频继续未实现。[命令与边界](../../docs/implementation/current-call-ui.md)。

遵循用户渐进要求，本批不展开完整键盘／通话矩阵，不把前批整条门禁／三ABI包沿用为当前代码。调试结束清理过期产物，保留必要临时证据与仍复用的构建缓存；无push。

普通lib/main.dart当前源码实际构建27.7秒／安装555ms，CLI R热重启1,763ms，`/tmp/connect-ime-call-main.log`；设备列表空态截图`/tmp/connect-ime-call-main-restarted.png`已目视后detach。两条FRB旧isolate投递告警和启动跳帧仍有，该首页不代替A59或完整动态视觉。

A59后续：第八轮目标先截图、750ms后主控截图、延迟再次两端截图，31秒通过且两张主控图均显示你好🙂；六checkpoint及查询恢复通过。证据`/tmp/connect-e2e/remote-ime-r8/`，截图含UTC时刻，不将其冒称端到端延迟数据。限定该流程旧画面疑点未复现，无播放器生产改动。[范围](../../docs/implementation/mobile-ime.md)。用户新增默认`flutter build apk`耗时及安装包信息为空反馈：本机release无key.properties，正在独立核验签名／实际安装并补构建入口；尚未归因用户原APK。

## 渐进交付：默认release安装与打包速度（A60）

用户默认`flutter build apk`安装失败反馈已复现：无签名仍构建成功，独立apksigner拒绝／PackageManager报INSTALL_PARSE_FAILED_NO_CERTIFICATES。现配置本机持久私密签名、无配置编译前拒绝、单ABI插件过滤及Gradle任务缓存，新增可重复初始化／构建／独立验证入口。x64 50.2MB／通用三ABI128.9MB均通过ZIP／签名／包名入口／ELF／16KB ZIP对齐，三ABI默认命令73.468秒，同源重复10.760秒；不是冷编译10秒承诺。实际第三AVD首次安装＋冷启动正常设备页＋同签名更新成功，本次安装已卸载且多余AVD关闭，主控原数据未动。[可复现入口、原始失败、命令与边界](../../docs/implementation/android-packaging.md)。尚无物理arm64执行／商店分发证据，其他四宿主和全部产品门禁不因此通过。

## 渐进交付：正式通话页接续真实画面

新增两份正式页面／宿主E2E，r3 16秒通过，严格分析无问题。正式通话页观察→实际来电提醒→选择查看→正式打开当前系统界面→全屏真实解码，独立InCallActivity与同一TC@7／原号码持续ringing，四checkpoint及清理恢复全部true。两端实截图已目视，含目标首次沉浸提示，未冒称提示遮住的呼叫标题可见；仍未实现逐呼叫动作／双向音频。[命令、两次前序失败与范围](../../docs/implementation/current-call-ui.md)。

本批最终普通lib/main.dart实际构建14.8秒／安装526ms、R热重启4,401ms，`/tmp/connect-packaging-main.log`；重启设备列表截图`/tmp/connect-packaging-main-restarted.png`已目视后detach。保留两条FRB旧isolate投递告警和启动跳帧，不称性能达标。最终arm64原件46,625,578字节／SHA-256 82bafbe09f8ca803e45204f3b49696e1946c04931ee4ff4135890986d5057cc2，独立签名／ZIP／manifest／ELF／ZIP页对齐通过，留存`/tmp/connect-artifacts/connect-arm64-release.apk`；三ABI原件同目录保留供安装。实际执行仅x64，物理arm64仍未验。R61／R62已回填统一目标与规格，不缩减既有62需求／32流程。

本批实际清理完成：终止临时第三AVD并卸载实验release，普通main detach后清除过期中间产物／debug包／Kotlin／incremental，仅保留最终arm64 APK（build共45MiB）、必要临时证据和复用缓存；磁盘余量78GiB。保留用户原有未跟踪测试／examples，未push。下一批仍为A51媒体预算／活动原件保护及USB共享选择，不展开新的输入／通话边界矩阵。

## 渐进交付：媒体暂存保护与清理（A51部分）

`839293e`实现512MiB持久预算、旧内容淘汰、活动写入预留／精确消费者租约、交付账本与保守系统分享保护，源变化不覆盖旧消费者文件，清理后传输撤下保存入口。接收／详情中断状态曾被自己的租约阻止重传，公开红测复现后修正；Core136 passed／48 ignored、Bridge106、应用全量256及后续相关20／11项回归通过，忽略项不计实际设备证据。`c723af7`加入生成路由与正式设置页、确认清理与真实空间回执。真实Core Android2.90秒及正式双AVD页面r4完整13秒通过，宿主逐字节／实际删除／远端保留／精确夹具清理全部true，hostErrors为空；预览和清理前后截图已目视。前三轮注册／Android规范别名／转场夹具失败均保留。[完整命令和限制](../../docs/implementation/media-cache.md)。

Pencil在偏好类别同行补两页，95页／十二类／26母组件／604实例／153变量，无断引、可见裁切或页面重叠，预览仅临时目录。实际页的matte内容面板与动态玻璃光学／性能不能据此算完整设计通过。A51整体仍不关闭：显式管理外部保留、用户预算调整／超预算大原件路径、真实空间满／进程死亡／长稳和巨量小文件核算继续待验。

Core对iOS／macOS／Windows MSVC交叉check30.93／17.04／20.31秒通过，非对应宿主Flutter链接；误选未安装GNU target的缺core失败未计通过。当前arm64 release38.86秒、46,740,766字节、SHA-256 a948e13cbd98c3552e4462415e9e964505b16c60d54e6e85c919be18242865e0，签名与完整性通过，留存`/tmp/connect-artifacts/connect-arm64-cache-release.apk`；物理ARM运行仍未验。`5b9cb1f`补E2E后旧测试插件注册导致--no-pub release失败的提前诊断，实际51秒编译失败与正常刷新后成功均记录，不手改SDK或生成Java。[打包依据](../../docs/implementation/android-packaging.md)。

普通main实际构建19.9秒／安装469ms、CLI R热重启4,513ms，`/tmp/connect-media-cache-main.log`，设备列表空态截图`/tmp/connect-media-cache-main-restarted.png`已目视后detach；两条FRB旧isolate投递及启动跳帧告警保留。最终严格分析／164输入生成一致性／Rust格式与clippy通过。实际清理本批过期debug、宿主测试可执行文件、incremental与Python缓存，释放12,264MiB，磁盘余量75.3GiB；保留最新release、必要证据、release中间缓存及native hooks／Gradle可复用缓存，避免每次全clean拖慢打包。原先五项未跟踪用户测试／examples未动，无push。

**用户最新主优先级：视频流传输性能、首帧速度、连接稳定性。** 下一批以可重复的实际计时／帧呈现和重连证据驱动优化，对照scrcpy开发者文档，先建立分阶段基线；USB共享选择顺延。十二领域和完整目标继续active，不把本批缓存或打包通过当作产品整体完成。


## 视频主优先级：首帧对照、持续新像素与阻塞期限

本批不重建JAR：官方v5.0.1与既有暂停补丁产物职责/摘要分别核验，保持当前视频暂停协议。[一手核查](../../docs/research/scrcpy-first-frame-performance.md)。同负载H264三样本输出首像素中位数1036→411ms，完整会话启动1823→1175ms；主控已知Matroska头的probesize32消除了长时间探测，单独analyzeduration无收益已撤回。没有移除首帧像素验证/播放确认，也没有使用丢初始IDR的nobuffer。五编码及各3次暂停恢复16秒通过，正式RemotePage五编码另28秒通过，实截图已目视；HEVC画质和物理硬解仍不据此通过。

真实ADB半包和活HTTP消费者不读两类阻塞均先红后绿，分别补单元开始后的完整交付期限/实际输出交付期限各10秒；完整包之间静止与主动取消保留，3+2条回归通过。独立目标动态图案r5 66秒通过6次连接/120次新像素/暂停恢复/纹理分离，输入到snapshot可读P50/P95/P99为446/452/569ms，含readback与轮询；6张实际Flutter截图及目标图已核对。夹具自动卸载/包不存在均true，r4 SDK直接exit绕过finally的漏清理已实际补清并修驱动，未隐藏失败。[阶段计时、对照原件、各次失败、命令与限制](../../docs/implementation/video-performance.md)。

主任务继续active，下一段仍围绕持续交互约0.45秒等待、Core启动核验约0.35–0.47秒、播放器失败传播与真实半开/切网重连开展。低复杂度色块640包不是高动态满负荷吞吐，主动重连不是Wi-Fi故障自动恢复，66秒不是小时级长稳。音画共同时间基/漂移、并发/玻璃负载、物理ARM/ROM/温度/耗电、四宿主Flutter整包继续开放；USB共享选择仍顺延。

`1cc5774`/`d41a26d`分别提交阻塞修复和首帧优化/真实基准。最终Core141 passed /48 ignored（35 suites）、Bridge107、相关应用43通过；严格分析/165输入生成一致性/格式/clippy通过。iOS/macOS/Windows MSVC Core交叉check8.61/3.19/6.59秒通过，非对应宿主Flutter整包。普通main构建27.4秒/安装584ms/R热重启2250ms，设备列表截图已目视后detach；旧isolate及SurfaceSyncGroup告警保留。本批闲置Gradle已停止，清理debug/incremental与过期非视频测试可执行文件实际释放11132MiB，余量73.2GiB，保留视频反馈循环及打包有效缓存，五项原有未跟踪文件未动，无push。

## 视频持续交互：软件回退与正式失败生命周期

`25c2ddc`补齐已打开播放器失败的正式传播，并统一媒体poll的所有权校验。真实Port事件链先红后绿：HTTP还在streaming时播放器已失败、迟到旧relay会误杀新代、重复故障会重复stop；现在按device/generation/relay/texture认领已提交输出，先撤下再并行stop/释放。候选错误事件不越权结束旧输出，正式恢复失败仍终止，不把冻结帧当恢复成功。新增7条及完整Bridge114项通过，相关应用43项通过；严格分析首次发现5处括号风格问题，补齐后4.9秒无问题。

`d0215db`依据真实分段及MDK decoder.video回执，仅优化实时视频FFmpeg回退线程策略，各平台原硬解优先保留。同负载80次默认FFmpeg与slice对照，P50为244→151.5ms、P95为254→245ms；新增P50≤200/P95≤300门槛后，40次默认FFmpeg为243/302ms实际失败，80次最终slice为149/242ms通过。输入回执通常1–4ms、snapshot通常1–2ms；未把snapshot可读称为玻璃到玻璃。fps=-1、async=0、image=1、direct IO无足够收益均撤回；不是叠加猜参数或让所有设备默认软件解码。[各轮原始结果、门禁、回执、复现与边界](../../docs/implementation/video-performance.md)。

正式RemotePage五编码28秒通过，H264全屏Settings及计数VIDEO12代表图已目视；其余图案每轮自动核对。4轮最终性能会话均确认纹理分离，夹具自动卸载/包不存在均true，宿主另验4个精确会话JAR路径均已不存在。普通main构建15.7秒/安装574ms，R热重启2557ms后设备列表截图已目视、detach；FRB旧isolate与SurfaceSyncGroup启动告警仍保留。

两种scrcpy JAR摘要再次核对且未改、未重建；普通Flutter/Rust编译直接嵌入已提交产物，tool/check.sh的重建可复现性验证独立于APK组装，说明补入servers/scrcpy/README.md。主任务继续active：AMediaCodec持续等待约0.35–0.45秒、Core核验、真实TLS/半开/切网恢复、高动态吞吐/并发、共同音画时间基/漂移、物理ARM/功耗与四宿主Flutter整包仍开放，不能用软件路径收益替代这些验收。

本批当前arm64签名release78.42秒通过，同模式热构建4.64秒通过且APK摘要一致；最新原件`/tmp/connect-artifacts/connect-arm64-video-release.apk`，46,740,766字节，SHA-256 `506f80ff966bed5669640c66e397120a0a400b9a3271a5fa319b7f7ae657ffd9`，完整性/manifest/ELF/16KB ZIP对齐/签名检查通过，未冒称物理ARM运行。清理406处释放3345MiB时也误删了旧Dart AOT缓存，已明确记录并补建当前有效缓存，未来不能仅凭app.dill判定debug；原签名、旧成品与Rust缓存未受影响。[完整打包记录](../../docs/implementation/android-packaging.md)。Gradle停止，最终空闲73.8GiB，保留当前release/有效原生缓存及临时证据；五项原有未跟踪文件未动，无push。

## 视频后续：重复打开与无EOF网络丢失

`9542e05`按实际ADB连接身份共享成功的编码器目录，并发合并，失败/取消可重试；关闭或替换连接拒绝旧结果，最多32项且淘汰不关闭连接。真实250ms暖校验门槛先红后绿：第二次378ms→最终52/47/46ms，Core814ms→431/450/440ms，暖启动到解码711/707/739ms；首次1197ms没有改善。每次捕获保留睡眠查询、服务端上传/启动和实际关键帧/解码验证。新连接三轮仍重新探测346/357/360ms，逐轮新像素/暂停恢复/截图/纹理分离及自动卸载均通过。[对照和复现](../../docs/implementation/video-performance.md)。

`25e9bac`在Rust TCP层、TLS前配置keepalive；Android/Linux同时限制未ACK数据等待。Android内核真实socket丢包、peer始终打开的两项原策略16秒失败，最终三项17秒通过，包括健康静止和主动close后真实EOF。正式Runtime+真实TLS协议端夹具原策略25秒未恢复，最终20.84秒整项通过：offline→同ID重连、仅一个设备记录、显式断开后实际EOF和5秒无第三次accept。宿主过滤器权限不足的初试不算目标故障红；专用AVD测试进程su0安装仅自身socket过滤器，不增加产品root要求。协议端夹具不是实际配对adbd，不把这些结果写成Wi-Fi切网、视频活动自动恢复或物理双机长稳通过。

完整Core147 passed/49 ignored（37 suites）、ADB50 passed/13 ignored通过；默认ignored不计设备通过，以上Android故障测试另显式执行。Clippy两包all-target -D warnings8.51秒、严格Flutter分析4.7秒、165输入生成一致性通过；iOS/macOS/Windows Core交叉check通过，不是对应Flutter宿主链接/整包。JAR摘要仍一致、未改未重建；AMediaCodec持续等待、冷启动、真实无线/后台恢复、高动态吞吐/音画同步与物理ARM/功耗继续开放。

最终正式远控页五编码24秒通过，H264全屏及悬浮退出截图已目视；普通main构建13.5秒/安装598ms/R热重启1724ms，设备列表已目视。最终签名arm64包总65.03秒、同模式4.09秒，摘要一致，原签名身份/ZIP/manifest/ELF/16KB ZIP对齐通过；当前`/tmp/connect-artifacts/connect-arm64-video-release.apk`为46,757,150字节，SHA-256 `f701f9690d5e00c4ee9ae23fcefb8c1e96e5c1f99a5a2540985d4309a3d759fb`，前一批成品保留归档，仍无物理ARM执行证据。编译/测试结束后停止Gradle，清理非视频测试程序/对应incremental、旧Android测试二进制及debug APK释放8259MiB，空闲65.0GiB；有效release/native hooks及无法确认模式的Flutter缓存保留，AVD测试二进制已删除。五项原有未跟踪文件未动，无push；[完整回执](../../docs/implementation/video-performance.md)。
