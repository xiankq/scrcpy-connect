# 当前完成度与下一步验收

更新：2026-10-18。目标状态：**active，未完成**。本页是当前完成度的权威入口；[目标契约](goal.md)定义完成门槛，[重新核查](completion-reassessment.md)保留U01–U44／R01–R62／C01–C32逐项追溯和A01–A60发现，[需求审计](requirements-audit.md)保留原需求来源。后续证据须先更新本页，再回填对应既有任务；历史快照不覆盖本页。

## 当前视频性能增量（2026-10-18）

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
