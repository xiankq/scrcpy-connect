# 当前完成度与下一步验收

更新：2026-10-18。目标状态：**active，未完成**。本页是当前完成度的权威入口；[目标契约](goal.md)定义完成门槛，[重新核查](completion-reassessment.md)保留U01–U44／R01–R60／C01–C32逐项追溯和A01–A58发现，[需求审计](requirements-audit.md)保留原需求来源。后续证据须先更新本页，再回填对应既有任务；历史快照不覆盖本页。

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
| 04 手机远控与真实应用；R03/R12/R20/R23–R25/R51，C07–C09/C32 | **部分**：全屏、触控、三真实会话保留／切换／精确关闭、窗口工具和可见设备归属。**部分**：主屏应用接续复用原会话，双AVD主屏＋两应用窗口51秒／9个独立进程与任务checkpoint及实际Settings像素／截图通过。A49已在未断链的已测路径补固定unknown身份、只读检查、核验入口及阻断主屏绕过该独立窗口记录，10项应用widget／38项生命周期回归与2项真实Runtime通过；副屏失败主屏回退的真实UI与实际解码故障仍未验；A49／A50本批已补私有持久操作账本、断开保留、Runtime重建转unknown、主屏独立操作身份与恢复核验门禁；真实Android公开Runtime四项50.17秒通过，含丢ACK、排队关闭后迟到ACK、写盘失败及deviceId精确关闭。主屏页面核对／关闭不等待旧输入清理，49项应用／生命周期／会话窄回归通过。Android杀进程现场、实际解码故障和完整恢复仍未验 | **部分修复／进行中**：A43退出pause拒绝／挂起实际先红，非阻塞离页修复后32项生命周期／会话视图回归通过，悬浮退出／系统返回×失败／挂起4组合通过；旧挂起队列可能阻塞同session重进，真实故障UI仍待验。**未实现／未验**：IME焦点／composing／密码／emoji／横屏、真实迁回／多实例、最近／常用与真实应用标签／图标、系统分屏／大屏并排。A45已修向内拖开保持展开／最近侧边／安全区，8项组件与真实产品25秒回归通过；下一步继续挂起／拒绝／系统返回及未知启动不重发的真实故障验收 | [06](issues/06-server-orchestration.md)、[08](issues/08-mobile-input-and-windows.md)、[18](issues/18-complete-design-state-coverage.md) |
| 05 媒体、声音与资源；R16/R22/R26/R39/R60，C10/C25/C28 | **部分**：共享fvp／MDK五编码、PCM／双设备焦点、HOME／旋转／同UUID恢复；按官方首帧文档修复；真实页选择1080后HEVC486×1080通过实像素门槛 | **未决／未验**：1280低清根因／默认策略、冷启动总耗时、触控到像素P50/P95/P99、丢帧、长期／热／功耗、物理声音／路由。**未实现**：共同音画时间基／同步调度（当前音视频各自取首PTS、独立Player），以及新／非焦点窗口资源降载完整策略；下一步固定设备与场景测端到端延迟和资源不足，保护已有活动 | [07](issues/07-fvp-media-pipeline.md)、[12](issues/12-calls-and-audio-arbitration.md)、[16](issues/16-glass-and-performance-budget.md)、[20](issues/20-android-validation-bench.md) |
| 06 通知与原应用；R33–R37，C18–C21 | **部分**：免APK listener、持续观察／独立停止、原PI／清除／失效保护、主屏复用；跨页回复有界保护及独立receiver原文count1；API36真实后台OS发布／精确撤回／通知栏点击后当前内容呈现 | **未实现／未验**：完整锁屏／应用认证后重取并重验、拒权／渠道／冷启动／系统停止／OEM及真实来电提醒、真实聊天服务一次接收／进程死亡恢复。下一步实际关闭渠道／撤权与认证完成后重验，不能重放未知回复 | [11](issues/11-notifications-continuation.md)、[14](issues/14-background-and-recovery.md)、[18](issues/18-complete-design-state-coverage.md) |
| 07 通话；R26/R32/R39，C22–C24 | **部分**：聚合状态与受限提示、危险全局动作明确拒绝，不抢已有活动 | **未实现**：安全绑定具体呼叫的接听／拒接／挂断与真实双向通话音频。**未验**：PSTN／VoIP、同设备多呼叫／多SIM、耳机／麦克风／转手机／结束恢复；下一步固定具体call身份及物理HAL对照，安全拒绝不能算功能完成 | [12](issues/12-calls-and-audio-arbitration.md)、[20](issues/20-android-validation-bench.md) |
| 08 文件与传输；R28–R30/R38，C11–C14 | **部分**：目录／基础管理、双向传输、三选一远端冲突／本批策略、无覆盖发布、有界搜索；A44已实施精确原件／操作的持久保存账本，13项Runtime重开／并发／限额／落盘失败及跨页unknown回归通过。双AVD取消→保存→离页重进恢复saved→分享43秒通过，独立63字节／hash／grant及重进截图已核验 | **未验**：Android实际写入中杀进程／unknown恢复及切设备迟到回执；Runtime重开不替代此证据。**部分**：已有批量选择、目录扫描／导入／导出与批次进度代码，最终交付和异常闭环未验。**未实现／未验**：浏览分类完整体验、provider／非seek／云盘／空间／撤权、恢复意图及外部分享打断系统选择器（A55）。A48系统provider冲突已迁到共享协调器与Flutter页面，按operation／conflict身份决定并支持本次后续策略；多USB设备选择仍由Kotlin产品AlertDialog决定。系统目录冲突真实E2E最终r5完整3分02秒通过并核验文件／零成果标题，前几轮夹具及第四轮目视发现的误报均保留记录；下一步继续实际中断与USB共享选择 | [09](issues/09-file-endpoints-and-recovery.md)、[14](issues/14-background-and-recovery.md)、[19](issues/19-dependency-license-and-updates.md) |
| 09 相册与预览；R31，C15–C17 | **部分**：缩略图／旋转／单项大小和并发限制；真实网格JPEG／MP4→原件预览→准备→系统取消／保存／分享，字节／hash／授权／双MIME；视频时钟／暂停／定位／静音 | **未实现／未验**：总磁盘预算／淘汰／清理及活动原件保护（A51）；A53本批已接动态共享目录扫描、权限空DONE复核、部分结果、冻结快照分页和mtime；10项公开Runtime协议fixture、7项公开页面测试及真实105原件双AVD85秒链路已通过；目视新发现A57已补共享调度／精确取消／有限重试，9项公开测试及真实15＋21张可见网格解码通过，完整异常／长稳仍待验，持续增量／其他用户和卷等仍独立说明；持续增量及实际大原件准备进度／取消、批量、全格式／损坏／缓冲／结束／断线／源变化／空间矩阵；无音轨MP4不证明物理音频。下一步大原件中断／离页取消，先验证准备活动与残留 | [10](issues/10-gallery-video-and-content.md)、[09](issues/09-file-endpoints-and-recovery.md)、[18](issues/18-complete-design-state-coverage.md) |
| 10 剪贴板与分享；R27–R28，C26–C27 | **部分**：文本跟随／固定／隔离与普通主控后台停读、专用页返回正确跟随；外部九模式导入／取消；出站文本／JPEG／MP4真实Sharesheet和独立receiver | **未实现／未验**：图片／文件剪贴板URI授权生命周期；入站内容实际提交指定设备、提交时切焦点不串线、系统本机打开、批量／大原件。下一步外部URI→选A→切到B→独立核验A字节且B不变，并测授权撤回 | [13](issues/13-device-targets-and-sharing.md)、[09](issues/09-file-endpoints-and-recovery.md)、[20](issues/20-android-validation-bench.md) |
| 11 后台、恢复与活动；R21/R38–R40，C28–C29 | **部分**：不可见视频协作暂停、主动声音／Activity重建、同runtime水位快照校准和过期播放器清理、主标签核验重试；回复跨页保护；A44系统保存持久账本及重开pending转unknown，真实saved离页重进通过 | **未实现／未验**：断网／换网／进程死亡／系统Stop／重启的完整活动意图与恢复资格；A23已接设备音源活动投影、精确sourceId独立停止与本地Player释放；真实播放→确认停止→连接／观察保留9秒通过。任务仍需按具体活动核对。Android写入中杀进程的unknown恢复仍未验。下一步活动×中断原因矩阵逐格注入并核对主动停仍停／未知副作用不重放 | [14](issues/14-background-and-recovery.md)、[15](issues/15-identity-trust-and-transports.md)、[20](issues/20-android-validation-bench.md) |
| 12 设计、易用性与研究；R01/R41–R50/R52，C01–C32 | **部分**：同一pen **93独立页／12类／26母组件／588实例／153变量**，保存重开核对；新tch6A／qTeGO；浅色／黑中性／小彩色／Lucide、全屏共享组件；实时背景折射已实现并有实际视频截图 | **未实现／未验**：全部状态与实际UI闭环、可打断液态形变、独立光学／视频性能／大字／读屏／高对比／减少动态矩阵、token全覆盖；A45内拖已通过组件与真实远控验收，TalkBack／完整无障碍仍未验；OPPO／vivo地区与端角色操作证据，Apple自身连续互通官方流程研究（A54）已补，实操未验；当前实际依赖的逐库契约／版本差异未闭合（A56）。下一步按coverage逐流程补入口→操作→失败→恢复并对照真实UI；相册范围面板短内容高度／灰色材质仍有实际视觉差距，93页静态完整性不等于实现验收 | [16](issues/16-glass-and-performance-budget.md)、[17](issues/17-manufacturer-mobile-flows.md)、[18](issues/18-complete-design-state-coverage.md)、[19](issues/19-dependency-license-and-updates.md) |

## 证据入口与优先顺序

1. **按用户最新要求渐进交付**：每批完成一条可用产品链路及对应必要验收，再推进下一条；尚未覆盖的边界明确留账，不围绕同一项反复扩展细节。新增明确的数据安全／重复副作用或崩溃问题优先处理，普通视觉细化不长期阻塞功能推进。
2. **下一批顺序**：A23活动列表的音源独立停止已完成本批链路，继续入站分享准确提交指定设备→远控IME→通话分级能力。各批保留精确对象、操作结果及失败出口；物理设备或其他宿主专属证据单独登记。
3. **按风险验收并阶段汇总**：局部改动先跑相应公开边界回归和可运行真实链路；完整工程门禁用于阶段汇总／依赖与打包变更，不把每个低影响细节都展开成新一轮全量测试。A43／A44／A49恢复、A48 USB共享选择、A51缓存、动态视觉／无障碍／性能、生产密码与四宿主等未闭合项继续按原任务推进。

| 证据 | 可复现入口／实际边界 |
| --- | --- |
| [首次安全配对](../../docs/implementation/first-pairing.md) | 真实产品表单、系统API精确撤权；直接Settings Forget失败原样保留，不称量产安全验收 |
| [总验收记录](../../docs/implementation/validation.md)、[状态恢复](../../docs/implementation/state-recovery.md) | 命令、失败、完成回执与截图路径；同runtime校准不等于断网／进程恢复 |
| [内容交付](../../docs/implementation/content-delivery.md)、[搜索](../../docs/implementation/file-search.md) | 单项文本／JPEG／MP4与搜索已有真实结果；A44新增持久账本与真实saved页面重进，Android杀进程unknown仍未验；首次重进夹具失败未计通过 |
| [系统提醒](../../docs/implementation/system-notifications.md) | 真实OS投递／撤回／点击；仍保留权限／认证／冷启动等矩阵 |
| [主屏应用widget](../../apps/connect/test/app_launch_test.dart)、[公开Runtime真实测试](../../crates/interop_core/tests/app_launch_android.rs) | 10项应用widget／38项生命周期回归；真实Runtime两项及双AVD51秒通过，独立display0／9个进程checkpoint、主屏同ID与实际Settings截图；旧宽松截图不计视觉通过，跨进程unknown与真实失败回退仍未验 |
| [Pencil覆盖](../../designs/prod/coverage.md)、[交互规则](../../designs/prod/interaction-rules.md) | 当前93页静态结构与产品规则；实际实现和动态验收逐项单独核对 |

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
