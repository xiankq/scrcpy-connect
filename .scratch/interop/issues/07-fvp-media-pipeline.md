# 07 · fvp 实时流、时间戳与可替换渲染链路

Status: ready-for-agent
Type: research
Priority: P0
Depends on: 03, 06
Requirements: R13、R16、R22

## 问题

fvp/MDK 是否能满足 scrcpy 实时流低延迟、音画同步和 Flutter 渲染？

## 研究输入与边界

一手依据与已有调查位于 `docs/research/`：scrcpy-media-and-server.md；flutter-rust-platform-runtime.md。入口见[需求审计](../requirements-audit.md)和[任务索引](README.md)。不把文档调查、编译与真机通过混为同一状态；现行规格与用户后续纠正优先于历史研究候选。

## 工作与交付物

- 比较裸流/保PTS封装/native packet路线，记录codec config、设备PTS、时钟、队列、背压、关键帧、首帧、复制次数与实际硬解。
- 验证H264/H265/AV1与声音的支持组合，不能用appendBuffer可播放证明逐帧PTS或同步已正确。
- 覆盖旋转、尺寸重配、Surface/engine重建、静止画面、断线和多窗口；不可见视频暂停、回来恢复。
- 验证就近截图：来自当前设备/具体会话的源画面，正确选主屏或虚拟display、处理旋转/尺寸与色彩；截图不混入本机玻璃控件，保存/分享和空间/权限/取消/源失效结果可确认，不引入录屏。
- 定义可替换媒体接口，维持Flutter主要界面/呈现，避免让Dart逐包桥接成为必选路径。

交付到对应研究报告及能力／流程矩阵；涉及代码或画布验证时保留版本、可复现步骤与证据。依赖项约束对应实验与最终结论，资料研究可先开始。临时截图与日志样本按隐私处理后放临时目录，不把设计预览纳入 Git。

## 完成条件

- [ ] 提交可复现Android对照数据与输入到显示测量方法，不直接相减两端未同步时钟。
- [ ] 截图在多会话、旋转与虚拟显示中归属正确，保存/分享完成与失败有真实结果；无误截其他设备或本机控件。
- [ ] 四端依赖与构建接入有依据/产物，未来端运行未验证如实列出。
- [ ] 若fvp不满足，给接口不变的替代证据；不先凭偏好换库。

## 当前状态

2026-10-17重新核查：当前共享fvp五codec、PCM、旋转/HOME/焦点有真实证据，旧自写播放器已删除。

首次画质选择已修复并通过真实页面；总延迟/同步/资源/物理播放尚未验收，HEVC1280回退低清不算质量通过，1080真实页路径已有后续证据，MDK原生产物闭包仍缺（A41）。

任务保持开放；`ready-for-agent`表示有明确工作可继续，不表示从未实施。逐需求与32流程见[完整重新核查](../completion-reassessment.md)，当前后端证据见[验收记录](../../../docs/implementation/validation.md)。

后续实像素门禁：1280请求/实际230×512明确红；真实产品页显式选1080后码流与解码486×1080、21秒流程通过，原图已目视。沿用既有软件HEVC约束结论，不改全部设备策略；完整延迟/硬件/资源仍开放。见[后续运行](../../../docs/implementation/validation.md#画质实像素与主控系统通知)。


## 本次逐指令复核补回的关闭条件

- [ ] A10细化：实现并验证共同音画时间基／同步策略；当前各mux独立取首PTS、两个Player不能只标成“同步待测”。暂停／重建／切源后的关联与长时漂移分别验收。
- [ ] C10：偏好保存、恢复旧UUID与新建UUID分开；旧会话保留原参数，新会话使用新参数，保存失败与新会话启动失败分别反馈。

源码、研究及本轮证据边界见[重新核查第22节](../completion-reassessment.md#22-用户再次要求逐指令逐文档逐设计核查)；当前状态以[权威入口](../current-status.md)为准。新增检查项尚未通过，不因写入任务自动关闭。

A59（2026-10-18）：真实IME链路证明目标原应用已提交你好🙂，但主控committed截图当时仍显示空查询。当前只是有顺序的截图差异，不能归因永久停帧；需在独立确认目标已绘制后限定时窗检查主控新像素／PTS，覆盖工具页暂停重进。未计动态视觉通过，见[输入证据](../../../docs/implementation/mobile-ime.md)。

A59限定复验：r8目标先拍＋750ms后主控及延迟两端截图，实际31秒通过，主控两张已目视显示你好🙂。原空查询差异未复现，不改生产播放器；不是端到端延迟／长期帧新鲜度验收。[完整时间与范围](../../../docs/implementation/mobile-ime.md)。

2026-10-18用户将视频传输/首帧/连接稳定性设为主优先级。保持现有暂停补丁JAR，不重建；新[官方核查](../../../docs/research/scrcpy-first-frame-performance.md)确认repeat/priority/latency机制已存在。实际分段测量后，已知Matroska头的probesize32使H264输出首像素三样本中位数1036→411ms，完整会话启动1823→1175ms；900ms红回归先失败后通过，单独analyzeduration尝试无收益已撤回。五编码及各3次暂停恢复16秒通过，正式RemotePage五编码另28秒通过，H264与动态图案截图已目视；不把HEVC低清或物理硬解计为通过。

两类真实阻塞先红后绿：上游ADB已交付半个scrcpy单元后静默、活HTTP消费者停止读取。第一字节后单元期限和待写输出期限各10秒，完整包之间仍可静止、取消立即释放；3+2条回归通过。动态图案r5 66秒通过6次连接/120次精确新像素/暂停恢复/纹理分离及自动卸载确认，输入到snapshot可读P50/P95/P99为446/452/569ms，含readback和轮询开销。不是玻璃到玻璃、Wi-Fi故障自动恢复或小时级长稳。[原始对照、失败夹具、复现命令与剩余瓶颈](../../../docs/implementation/video-performance.md)。

本任务仍开放：持续交互约0.45秒等待、播放失败事件到正式会话失败的传播、网络半开/切网恢复、高动态吞吐、音画共同时间基/漂移、物理ARM/热功耗与四宿主整包继续验收，不能用本批局部收益关闭全部性能要求。

后续`25c2ddc`已补已提交播放器失败传播及stale relay/重复故障/异步清理隔离，7条新回归与完整Bridge114项、相关应用43项通过；不会将HTTP仍streaming当作播放器仍健康。`d0215db`仅优化共享实时视频FFmpeg回退线程，硬解优先保留，最终80次新像素P50/P95=149/242ms，200/300门槛先红后绿。平台AMediaCodec仍约350–450ms，4种无明显收益参数已撤回；真实网络自动恢复和高动态/功耗仍开放。正式远控页五编码28秒通过，严格分析补5处风格问题后无问题；详见[持续交互与失败传播](../../../docs/implementation/video-performance.md)。JAR本批仍未重建，普通APK组装直接复用现有产物。

`9542e05`补连接级编码器目录：实际暖校验378→46–52ms、暖Core814→431–450ms；4轮同连接真实图案通过，新连接3轮仍重新枚举。6项目录所有权/并发/失败取消/关闭/淘汰回归通过，冷启动未改善。`25e9bac`补TCP存活与Android/Linux未ACK期限：AVD内核丢包peer保持打开的两项先红后绿，健康静止及close实际EOF一并通过；正式Runtime真实TLS协议夹具原策略25秒未恢复、最终整项20.84秒通过，含相同deviceId自动重连与显式disconnect后无再连接。不是代理代ACK、peer EOF或实际配对adbd/Wi-Fi切网/视频活动恢复证据。完整Core147/49 ignored、ADB50/13 ignored、all-target clippy、严格分析、165输入生成一致性及三宿主Core交叉check通过。任务仍开放，详见[重复启动与TCP链路恢复边界](../../../docs/implementation/video-performance.md)。

下一项研究/实施：增加MDK解码帧交付renderer与snapshot的同PTS/同主控单调时钟观测，分清回调前等待和回调后排队；先核对C ABI同步int回调的线程/帧所有权、既有回调和关闭时序，评估Rust有界原生指标路径，不把frame指针异步传Dart或增加Android呈现代码。CCodec output.delay=8仅是上界，现有日志不能认定实际积压8帧；SPS VUI重排序也尚无完整解析证据。Rust当前无主动定时攒包，不代表实际背压已排除。详见[后续分段任务与一手定义](../../../docs/implementation/video-performance.md)。


2026-10-18后续：上段同PTS研究已实施，Rust可选onVideo/snapshot/relay共享单调时钟，默认不开启，不新增Android呈现代码；`bf4262a`/`c058957`。候选逐项实验后`a694b78`保留现有JAR参数repeat间隔ceil(1e6/min(maxFps,30))与视频fps=-1；正常路径原生AMediaCodec、固定双AVD H264 640/30/2Mbps 80次新像素P50/P95从359/452到186/241ms，相同200/300门槛先红后绿，四轮实际呈现/暂停恢复/清理通过。最大352ms样本未丢弃。首帧无改善，静态重复增加工作，真实功耗/热、默认高清/高动态、物理硬解、长稳/切网/视频活动恢复和四宿主整包继续开放。不能继续把“平台AMediaCodec仍约350–450ms”作为本已测场景的当前结论，也不能外推所有设备已低延迟。[分段、负面实验、复现及边界](../../../docs/implementation/video-performance.md#原生路径分段与持续交互优化2026-10-18-后续批次)。


冷启动后续（2026-10-18）：`657990c`从launcher交回starttime省重复读取，在metadata及START_APP提交后并行完整身份核验与首关键帧预读；两者都成功才发布入口。三轮关键帧后额外工作93–97→47–48→0–1ms，身份/取消/unknown语义经只读review与真实进程测试保留。默认高清80次实际576×1280、AMediaCodec P50/P95=201/248ms，完整首帧1122–1234ms；200/300和首帧1000ms总体门槛仍失败，四轮画面/暂停恢复/清理已完成，不关闭任务。16.667ms repeat试验暂停超时已撤回，JAR不变。详见[冷启动与高清记录](../../../docs/implementation/video-performance.md#冷启动身份校验与默认高清复验2026-10-18-后续)。

- [ ] 冷阶段关联首包/prepare/首次onVideo/renderer，确认观测注册是否覆盖prepare内首解码；保持同主控单调时钟、同PTS且不把snapshot当面板扫描。
- [ ] 高负载暂停HTTP消费者背压/控制ACK建立真实可重复回归；保留静止输入的MDK暂停确认机制，不能未经验证简单颠倒暂停顺序。
- [ ] 独立高动态/持续吞吐测量与资源/热预算；四块离散计数新像素不代表稳定60fps或8Mbps持续负载。
- [ ] 若并行JAR上传与枚举，先验证失败/取消后上传结束与删除的顺序，防止迟到文件复活；不要跳过探测或跨传输复用目录。

动态暂停后续：已补独立持续变色夹具、每轮1–50次pause和暂停期间改变计数／恢复新像素校验。
原JAR静态20次通过、动态第5／6次ACK超时；gate/consumeReset窗口的确定性红回归修复后，
动态仍超时。目标超时前栈与主控447µs最大raw写入指向EOS退出等待；真实encode无EOS
回归先红，改100ms读轮询及完整packet后pending检查后绿。捕获扩展JAR因此重建，官方JAR
不变、普通APK不重建JAR规则不变。最终相同APK两次各20循环全部通过，暂停148–306ms，
恢复新像素410–869ms。

任务继续开放：该候选第一次动态运行触发MDK `JNISurfaceTextu` SIGABRT，两个后续通过
不能抹除；动态首帧2753–3091ms、输入1049–1769ms仍远超严格预算。下项先复现/隔离
此原生崩溃，再分段高动态积压与冷阶段。功能压力的宽门槛true不算1000/200/300ms通过。
研究、失败、命令与校验边界见[暂停记录](../../../docs/implementation/video-performance.md#动态负载下的合作暂停与jar重建2026-10-18)。

- [ ] MDK动态原生崩溃锁定复现率、cycle/renderer状态、可符号化栈或源码边界；保留
  `/tmp/connect-video-pause-native-tombstone.txt`，不凭AVD环境归因，也不全局强制软解掩盖。

后续定位：匹配BuildId的反汇编证实renderer snapshot队列空完成回调进入线程后
`bad_function_call`主动abort；动态30fps同PTS对照再次出现相同地址／BuildId，
此次Rust C snapshot与原fvp snapshot共用MDK内部链路。仍未锁定空回调产生机制，
没有可靠修复，复现率也未闭合，所以上项继续未勾选。60次动态暂停及2,000次无暂停
串行截图通过不覆盖崩溃。60fps动态16次关联的输入→relay中位1002ms，relay→onVideo
262ms；30fps重跑对应1036／220ms，未改善主要上游等待，不更改生产帧率。
下一步独立夹具目标输入／绘制时钟与原始源PTS关联，先核对时钟定义再分段。
[现场、复现参数与失败记录](../../../docs/implementation/video-performance.md#mdk截图崩溃与动态上游分段2026-10-18)。

目标时钟分段已实施（`aa9330e`／`e99d4b6`）：16次真实输入与2次暂停输入按sequence
匹配目标处理／绘制时间，4 bit回绕不串样。60fps负载回调CPU中位0.393ms，
开始绘制等待0.902ms，所观察源PTS晚于绘制结束约67.483ms，不能称编码完成。
relay前中位仍1012ms；15fps对照降到227ms，总报告P50／P95=566／911ms，仍未达标。
不把15fps实验设为所有设备默认。严格分析、16项HTTP、Core all-target clippy通过，
采集失败保留主错误／完整报告的真实负面验证通过。下一步测Rust ADB读取／raw输出
至relay，继续区分编码与传输；不必为这些主控观测重建JAR，MDK崩溃继续开放。

ADB消费／raw分段已实施：默认关闭、256项上限、source PTS及捕获分段标识；真实
分段ADB路由回归先红后绿，同组4项通过。恢复后同环境60fps动态AMediaCodec与FFmpeg
各16次新像素／2次暂停完成，报告P50／P95分别1310／1699、1098／1549ms，严格失败。
完整包读完→relay中位0.123／0.139ms，relay→onVideo为233.155／4.025ms，输入→relay
仍均约1067ms。默认后端不变；主要上游等待未解决。AdbStream只交付已收齐WRTE，
当前读时钟看不到首包先前接收／排队，下一项补实际packet reader及路由／消费分段，
不能据此排除ADB或物理网络。只读review的收据发布竞争已补有界等待；两个JAR未改。
最终同版复跑、原始命令／证据／时钟边界见[当前传输记录](../../../docs/implementation/video-performance.md#adb消费raw转发与解码后端对照2026-10-18)。

逐WRTE后续：接收观测已实施，默认关闭、恒定每stream收据及token隔离，ACK不变；
真实协议回归先红后绿，完整ADB52项／13 ignored、Core4项及clippy通过。Android同配置
16次新像素与18项时间线完整，20个首末WRTE payload读中位0.256ms、路由→消费0.014ms，
输入→relay仍1002ms，P50／P95=1268／1584ms、首帧3138／2840ms严格失败。头读完前的
等待仍不可见，下一项带误差界关联目标源PTS与主控收包，继续分编码前后，不能直接
相减未同步时钟。Burst官方仍实验默认关闭，本库缺完整credit支持，待独立实施与A/B，
没有只改banner。JAR未改，已有MDK崩溃继续开放。
[实测与观测范围](../../../docs/implementation/video-performance.md#逐wrte接收与消费实测2026-10-18)。


时钟括号后续：新增默认关闭的session.clock.probe，整个exec响应前后取同一主控时钟；
目标夹具BOOTTIME／nanoTime三读数与每轮前后三次probe，按明确常offset条件及量化余量
求区间，缺失／逆序／空交集拒绝，非空不证明无暂停。原始PTS额外假设单列。
同双AVD默认动态16次输入，绘制结束→首payload两轮中位界962–1013／957–1009ms；
主要范围收窄到此段，不能唯一归因编码器。仅Surface输入15fps、固定repeat33334µs
候选的P50／P95=540／1567ms（默认1301／1701），第二轮draw→payload161–203ms，
仍有首轮长尾及2.6秒首帧；支持负载／排队方向，候选已撤回，默认60fps和两个JAR不变。
两组新像素／18项时间线／暂停恢复／呈现／停止／卸载完成，严格性能和MDK崩溃项仍开放。
[模型、源码依据与真实结果](../../../docs/implementation/video-performance.md#时钟括号与surface输入实验2026-10-18)。

Burst后续：Rust ADB已补完整默认关闭的字节credit协议，双方主动feature相交、
部分消费返还、有界逐流／连接预算及正反向关闭尾包；Core显式设置仅影响新连接。
19项新wire测试、完整ADB72通过／13忽略、Core153／49忽略及严格workspace检查通过。
实际双AVD每组16次新像素／2次暂停完成且模式回执匹配；经典P50／P95=1224／1493ms，
Burst=1324／1670ms，首帧仍2.5–3.0秒，两组严格门槛均失败。没有消除主要上游等待，
Burst默认继续关闭，不是完整视频性能修复。宿主无解码快速排空仍约0.46–0.55秒PTS年龄，
目标video线程857次write最长9.505ms，仅排除该次宿主实验长socket写阻塞。
后续优先Surface采集／fence／编码输入排队和冷创建开销；没有通用应用可控input slots
旋钮的已证方案。MDK当前发布无对应snapshot空回调修复；onFrame→VideoFrame.to为
待验候选，不降低实际像素门禁。两个JAR未改、未重建，任务继续开放。
[真实对照、范围和复现](../../../docs/implementation/video-performance.md#可选adb-burst与宿主排空诊断2026-10-18)。


目标Perfetto新证据：303项CCodec输出回调与接收PTS精确关联，trace无data-loss；
全体／最后1/3条件源年龄中位299.213／590.659ms，主要年龄已在回调前，包含采集／
队列／计算／IPC与调度，不等于纯编码CPU。Clock snapshot非正式误差括号，原PTS
时钟假设保留。新增可复跑离线分析器和三项校验，拒绝缺失事件关联；软件AVC不支持
MediaFormat complexity快速档的固定一手源码已核实，不添加无效参数。
冷阶段电源查询与实际编码器枚举安全join、限4项有主探测清理；捕获JAR仍顺序上传。
静态双AVD四轮对照校验399→281ms、完整首像素1244.5→1097ms，严格预算仍失败。
HEAD与候选默认栈真实应用窗口均复现SIGABRT；生产入口Box::pin后40512→160B，
同测试默认2MiB栈通过，无线程栈／测试调用方绕过。最终lib48通过2忽略及clippy通过。
最终Android四轮16次正常新像素／4次暂停恢复及呈现停止卸载完成；首像素中位
1182ms、输入P50/P95=190/310ms，严格门槛仍失败，未重跑挑样本。两个JAR未改未重建，
动态输入长延迟及MDK崩溃继续开放。
[目标侧分段](../../../docs/implementation/video-performance.md#目标ccodec完成边界与源年龄2026-10-18)、
[冷阶段对照与栈修复](../../../docs/implementation/video-performance.md#冷启动探测并行与默认栈修复2026-10-18)。

最终Core iOS/macOS/Windows交叉check与fmt通过；普通main热重载127ms及无Dart
运行错误，首页已目视。Gradle停止后清理debug产物释放5730.4MiB，保留缓存/release
及原始证据。代码`c121a51`、分析器`8201485`，完整目标继续active。


MDK默认Surface下单次onVideo→to(RGBA)真实候选返回全黑图，实际图案断言失败，
完整撤回，不切软解或删除像素门槛。原动态路径400截图/20暂停/8新像素完成未崩溃，
但首帧3146/2766ms、输入P50/P95=1360/1478ms仍严格失败；历史MDK崩溃继续开放。
转向视频断网：新增真实adbd透明TCP切断E2E，原实现设备重连后30秒无视频，确实红；
修复当前可见主屏的恢复意图，明确停止/后台/unknown/迟到提交不自动重放。旧绑定
本地撤销，不向已结束输出发pause。新5项缺陷回归先红后绿，最终相关52项、App275项
和严格分析通过。真实双AVD两次完整exit0，3.965/3.831秒恢复新session和实际图案0→1，
停止/卸载/代理清理完成。仅可控TCP EOF，不冒称物理无线切网/长稳或完整性能通过。
两个JAR完全未改未重建。[读帧否定及真实恢复](../../../docs/implementation/video-performance.md#读帧候选否定与真实网络恢复2026-10-18)。

代码`39f62ca`、真实恢复E2E`9c42aff`。普通main热重载148ms无Dart错误并目视；
清理382项debug输出释放1489.4MiB，保留缓存及release。目标无捕获进程/fixture，
已知本批session无残留JAR，原始证明仍在/tmp，完整目标active。

后续动态codec对照：性能入口增加显式codec/encoder实验参数，不改产品默认。
同双AVD、实际576×1280/请求60fps/8Mbps、AMediaCodec、trace开启，H264/VP8默认/
VP8临时CBR各2轮、16次新像素及暂停恢复/Flutter合成/停止/卸载完成。
输入P50/P95分别1331/1592、973/1508、1135/1546ms；首像素分别2830/2520、
2357/2308、2256/2253ms。三组严格1000/200/300门槛均exit1，未关闭性能任务。
CBR改变不能仅归因speed值，临时Rust参数已按原字节恢复；不切默认codec/软解或
降低帧率，不重建两个JAR。当前软件编码模拟器结果不能代替跨设备画质与功耗验收。

既有Perfetto只读拆分发现真实media.swcodec编码主线程4009.856ms运行、3595.733ms
可运行等待；两个目标vCPU已记录sched约96.5%以上非idle，后段完成25–30/s且
匹配PTS首末条件源年龄增长417.364ms。支持调度竞争/吞吐退化，不等于纯编码CPU
或某个队列深度。下一步隔离目标CPU与合成竞争，保留实际吞吐和新像素判据。
[固定VP8源码](../../../docs/research/scrcpy-first-frame-performance.md#vp8实时编码与公开码控参数2026-10-18)、
[三组实际结果/复跑/SQL与限制](../../../docs/implementation/video-performance.md#编码器对照与目标调度2026-10-18)。

性能入口严格分析/格式检查通过；普通main热重载120ms无Dart错误并目视。
Gradle停止后清理394项debug输出释放1493.4MiB，保留缓存/release及原始证据；
目标无捕获进程/fixture，6项session捕获JAR已确认清理。完整目标继续active。

截图生命周期后续：新增最多8项的播放器操作队列，串行snapshot与播放状态；关闭
拒绝后续/排队操作，实际结果交付后才stop/detach/dispose，超时仅报告deferred并
继续占退役配额。Rust诊断-4超时保留native槽位，真实C ABI回归先红后绿；补
textureSize await后的关闭检查。review发现初队列会让refresh抢在native pause前，
生产Portable+gate回归确实红；最终onRequested放在成功native提交后，双分支均
结束才解除占用，提交失败不刷新，已暂停候选也沿用。完整Bridge Dart123、Rust17、
App275项通过，严格分析/clippy/fmt通过。

最终双AVD静态普通snapshot10次暂停恢复、动态trace200次串行截图+10次暂停恢复，
实际图案12/同PTS/呈现/停止/卸载均完成且目视，本次无崩溃；严格性能仍exit1，
静态首帧1269ms、动态2659ms，动态输入P50/P95=1234/1455ms。不能用本次有限
通过关闭历史MDK内部空std::function；还需worker收尾、真实长期故障与物理设备证据。
[代码路径、红绿、实际样本及复跑](../../../docs/implementation/video-performance.md#截图生命周期与暂停提交顺序2026-10-18)。

- [x] 补fvp公开snapshot失败结果null的独立真实回归及可复现依赖层修复；后续已由
  仓库内补丁及源边界红绿闭合，Android链路另验，不能与历史worker空function混因。
  [一手依据及边界](../../../docs/research/scrcpy-first-frame-performance.md#snapshot交付关闭与失败结果边界2026-10-18)。


最终真实ADB EOF恢复17秒exit0、3534ms新session及VIDEO1，停止后无重建，代理/夹具/
Settings清理确认；普通main热重载125ms无Dart错误并目视。清理395项debug/本批测试
可执行文件释放1670.1MiB，保留有效缓存/release/原始证据；目标无本批进程或JAR。
完整目标active，严格延迟、历史MDK崩溃和上述null失败回调继续开放。


2026-10-18公开snapshot失败补丁：已按官方pub归档摘要引入最小仓库内fvp0.39.1
源码fork，五平台副本仅增加null结果→空Uint8List完成，保留原API／许可证及
跨平台入口。源边界原版SIGSEGV先红、修补后null／正常stride／未知handle绿；
另经真实Dart VM确认空和非空typed data投递。完整Bridge123项／严格分析通过。
Android静态10pause及动态200串行截图＋10pause、新像素／实际图案12／停止
分离／卸载完成；首帧1469/2901ms，输入两样本188/381和1377/1319ms，严格
1000/200/300仍exit1。实际frame trace=false，不宣称同PTS分段。真实ADB EOF
恢复17秒exit0，3521ms新session及图案0→1，主动停止不重建，所有夹具清理确认。
历史MDK renderer空std::function、动态源年龄、原生SDK闭包及四端整包仍开放。
随后宿主OOM杀目标AVD／主控模拟器signal11，普通App恢复单独处理；不混为
本次依赖空结果故障。两JAR不变，详见[本批证据](../../../docs/implementation/video-performance.md#fvp失败截图结果与仓库内补丁2026-10-18)。

普通main随后仅主控冷启、复用已构建APK恢复，热重载及Dart运行错误检查通过，
首页已目视；394项debug输出已清理、缓存及release保留。新独立首帧候选为暂停
补丁的初始重复编码器分配，先量化而不贸然改JAR；不解释关键帧后输出等待或
稳态源年龄，见上述研究。代码提交7cbf010，本任务及完整目标继续开放。


2026-10-18首验证截图分段：E2E在后续readback覆盖前保留32×32验证snapshot指标，
用启动Stopwatch前后包围读取；计时点提前避免2–6ms观测开销。新增GPU／renderer
buffer隔离实验参数，默认不覆盖SDK。五组15会话／30次正常新像素／15次暂停恢复、
实际Texture、停止分离与清理完成；所有严格1000/200/300命令仍exit1。
默认→buffer1→默认、GPU0与buffer1复跑未形成可保留的整体性能收益，生产Fvp逐字节
恢复、两JAR不变。首个已观测同PTS onVideo→snapshot约0.21–0.37秒，含调度、渲染
和读回，不称面板延迟。下一步定位这段主控等待，并独立处理目标软件编码积压。
[完整对照、复现和边界](../../../docs/implementation/video-performance.md#首个验证画面的观测与隔离对照2026-10-18)。

同JAR目标codec日志三次确认双创建，Created间隔39/34/33ms含必需初始化，不能当
纯可节省成本；先不改变暂停门或重建JAR。固定Android16还确认drop-input-frames
清全部GBS待输入，可能丢最终静态变化，且不清已送入组件工作；不盲加生产pulse。
[源码与实际分配证据](../../../docs/research/scrcpy-first-frame-performance.md#同jar双分配实测与首帧sdk选项2026-10-18)。
普通main热重载成功、无Dart运行错误、首页已目视并detach；启动卡顿告警继续开放。
Gradle停止、394项debug输出清理1484.6MiB，保留有效缓存及release。目标15个session
JAR与捕获进程确认无残留后正常关闭，主控保留首页。完整目标和本任务继续开放。


2026-10-18截图提交计时及呈现门禁复核：native元数据增加同钟submittedElapsedUs，
完整Bridge Rust17项／严格clippy／fmt通过。四组三轮真实负载实验均完成新像素、
暂停恢复及Texture，严格性能仍失败；提前挂载或等decode后截图未保留生产改动。
发现fullyLive叠加Live绑定自调度形成额外持续框架绘制，原默认又会抑制部分框架帧；
两者都不能直接充当正常产品等效。普通main真实UI连AVD及全屏0→2已目视，正常
静态trace与测试负载分开记录；仍缺正常binding下的完整首帧/输入性能测量入口。
仅保留native计时与回执binding/framePolicy，代码`f4db3b6`，两JAR未改未重建。
[实验、源码边界及真实产品页](../../../docs/implementation/video-performance.md#截图提交时间与测试帧调度边界2026-10-18)。

普通main热重载成功／无Dart错误；测试设备记录、fixture、12个session JAR及捕获
进程确认清理，设备首页已目视。AVD内存增长后正常关闭两台模拟器，Gradle停止，
清理394项debug输出1484.6MiB，保留release及有效缓存。本任务与完整目标继续开放。
