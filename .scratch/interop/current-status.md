# 当前完成度与下一步验收

更新：2026-10-17。目标状态：**active，未完成**。本页是当前完成度的权威入口；[目标契约](goal.md)定义完成门槛，[重新核查](completion-reassessment.md)保留U01–U44／R01–R60／C01–C32逐项追溯和A01–A49发现，[需求审计](requirements-audit.md)保留原需求来源。后续证据须先更新本页，再回填对应既有任务；历史快照不覆盖本页。

## 状态口径

- **已落实**：只对列明的实现与已通过证据成立，不外推整个领域完成。
- **部分**：已有实现或真实证据，仍有明确交付缺口。
- **进行中**：本轮存在改动／复现，尚未完成相应验收。
- **未实现**：源码或产品链路缺失；不能用“设备不支持”代替。
- **未验**：已具备实现或候选路径，但指定环境／故障／产品步骤尚无通过证据。默认忽略的真实用例不计通过。

## 12个领域逐项现状

| 领域／需求与流程 | 当前已落实的范围 | 未闭合范围与下一次可执行验收 | 既有任务 |
| --- | --- | --- | --- |
| 01 设备与首次设置；R02/R19/R53–R54，C01–C05/C30 | **部分**：固定设备列表、连接表单和真实诊断；隔离secure=1 API36上真实表单错码拒绝→PAKE→独立端口TLS→系统接口撤权后旧身份拒绝，两轮64秒 | **未验**：QR／发现／USB、码过期／切网／后台、旧系统USB转无线、量产OEM。直接Settings Forget持久化仍失败；设备最近信息时间、同物理设备USB／无线身份归并及工作台功能分级入口仍未闭合，首次步骤／用时也须实测。**进行中**：中文错误提示已改并有widget证据，尚无本轮真实表单UI验收；下一步从撤权错误页检查可理解提示和可继续路径 | [05](issues/05-ordinary-user-onboarding.md)、[15](issues/15-identity-trust-and-transports.md)、[20](issues/20-android-validation-bench.md) |
| 02 Rust ADB与信任；R08–R11/R40，C04/C06 | **部分**：独立库不调用外部adb，主要协议／服务、无线互通、Required TLS和发现→表单→Core类型保留及拒明文负例；安全AVD首次正负例已有证据 | **未实现／未决**：完整公开服务契约；README排除typed forward／包管理／delayed ACK／incremental／5037与任务01边界未闭合（A47）。当前TLS provider为alpha且上游明确不供生产，RSA时序风险尚未解除；纯Rust实现不能等同生产安全。**未验**：Wi-Fi2、成熟生产密码链、锁定OEM／重装／四端密钥保护。下一步逐服务给API／参考／差异／关闭条件，区分实现缺失与合理范围 | [01](issues/01-adb-contract-and-wireless.md)、[02](issues/02-pure-rust-crypto-dependencies.md)、[15](issues/15-identity-trust-and-transports.md) |
| 03 四端与工程；R06–R07/R13–R15/R55–R59 | **部分**：monorepo、FRB、Hooks／生成Riverpod、typed路由与严格分析；Android armv7／arm64／x64整包已有本地通过，生成及部分JVM门禁存在 | **未验**：iOS／macOS／Windows宿主整包和最终链接、平台资格、干净检出。**未实现**：CI调用check.sh不带--android，Android整包与native ownership main未入CI（A46）；FRB／companion／MDK原生产物闭包仍缺。下一步补Android CI明确入口与失败负例，再推进四宿主产物 | [03](issues/03-workspace-bridge-platform-builds.md)、[19](issues/19-dependency-license-and-updates.md) |
| 04 手机远控与真实应用；R03/R12/R20/R23–R25/R51，C07–C09/C32 | **部分**：全屏、触控、三真实会话保留／切换／精确关闭、窗口工具和可见设备归属。**进行中**：主屏启动应用／副屏失败经明确同意回退，3项widget与公开Runtime真实目标观察已有证据，尚无本轮真实UI闭环；首帧超时后‘重新检查’可能重提真实应用启动（A49，源码发现待动态复现） | **部分修复／进行中**：A43退出pause拒绝／挂起实际先红，非阻塞离页修复后32项生命周期／会话视图回归通过，悬浮退出／系统返回×失败／挂起4组合通过；旧挂起队列可能阻塞同session重进，真实故障UI仍待验。**未实现／未验**：IME焦点／composing／密码／emoji／横屏、真实迁回／多实例、最近／常用与真实应用标签／图标、系统分屏／大屏并排。退出每次拖动结束必收起，与内拖保持展开约定不符（A45）；下一步覆盖挂起／拒绝／系统返回、内拖保持展开及未知启动不重发 | [06](issues/06-server-orchestration.md)、[08](issues/08-mobile-input-and-windows.md)、[18](issues/18-complete-design-state-coverage.md) |
| 05 媒体、声音与资源；R16/R22/R26/R39/R60，C10/C25/C28 | **部分**：共享fvp／MDK五编码、PCM／双设备焦点、HOME／旋转／同UUID恢复；按官方首帧文档修复；真实页选择1080后HEVC486×1080通过实像素门槛 | **未决／未验**：1280低清根因／默认策略、冷启动总耗时、触控到像素P50/P95/P99、同步／丢帧、长期／热／功耗、物理声音／路由。**未实现**：新／非焦点窗口资源降载完整策略；下一步固定设备与场景测端到端延迟和资源不足，保护已有活动 | [07](issues/07-fvp-media-pipeline.md)、[12](issues/12-calls-and-audio-arbitration.md)、[16](issues/16-glass-and-performance-budget.md)、[20](issues/20-android-validation-bench.md) |
| 06 通知与原应用；R33–R37，C18–C21 | **部分**：免APK listener、持续观察／独立停止、原PI／清除／失效保护、主屏复用；跨页回复有界保护及独立receiver原文count1；API36真实后台OS发布／精确撤回／通知栏点击后当前内容呈现 | **未实现／未验**：完整锁屏／应用认证后重取并重验、拒权／渠道／冷启动／系统停止／OEM及真实来电提醒、真实聊天服务一次接收／进程死亡恢复。下一步实际关闭渠道／撤权与认证完成后重验，不能重放未知回复 | [11](issues/11-notifications-continuation.md)、[14](issues/14-background-and-recovery.md)、[18](issues/18-complete-design-state-coverage.md) |
| 07 通话；R26/R32/R39，C22–C24 | **部分**：聚合状态与受限提示、危险全局动作明确拒绝，不抢已有活动 | **未实现**：安全绑定具体呼叫的接听／拒接／挂断与真实双向通话音频。**未验**：PSTN／VoIP、同设备多呼叫／多SIM、耳机／麦克风／转手机／结束恢复；下一步固定具体call身份及物理HAL对照，安全拒绝不能算功能完成 | [12](issues/12-calls-and-audio-arbitration.md)、[20](issues/20-android-validation-bench.md) |
| 08 文件与传输；R28–R30/R38，C11–C14 | **部分**：目录／基础管理、双向传输、三选一远端冲突／本批策略、无覆盖发布、有界搜索；A44已实施精确原件／操作的持久保存账本，13项Runtime重开／并发／限额／落盘失败及跨页unknown回归通过。双AVD取消→保存→离页重进恢复saved→分享43秒通过，独立63字节／hash／grant及重进截图已核验 | **未验**：Android实际写入中杀进程／unknown恢复及切设备迟到回执；Runtime重开不替代此证据。**未实现／未验**：浏览分类、批量／目录、provider／非seek／云盘／空间／撤权、恢复意图。A48系统provider冲突仍由Kotlin产品AlertDialog决定，未收敛共享职责；下一步覆盖系统目录冲突及真实中断 | [09](issues/09-file-endpoints-and-recovery.md)、[14](issues/14-background-and-recovery.md)、[19](issues/19-dependency-license-and-updates.md) |
| 09 相册与预览；R31，C15–C17 | **部分**：缩略图／旋转／有界缓存；真实网格JPEG／MP4→原件预览→准备→系统取消／保存／分享，字节／hash／授权／双MIME；视频时钟／暂停／定位／静音 | **未实现／未验**：时间／分页／增量、真实大原件准备进度／取消、批量、全格式／损坏／缓冲／结束／断线／源变化／空间矩阵；无音轨MP4不证明物理音频。下一步大原件中断／离页取消，先验证准备活动与残留 | [10](issues/10-gallery-video-and-content.md)、[09](issues/09-file-endpoints-and-recovery.md)、[18](issues/18-complete-design-state-coverage.md) |
| 10 剪贴板与分享；R27–R28，C26–C27 | **部分**：文本跟随／固定／隔离与普通主控后台停读、专用页返回正确跟随；外部九模式导入／取消；出站文本／JPEG／MP4真实Sharesheet和独立receiver | **未实现／未验**：图片／文件剪贴板URI授权生命周期；入站内容实际提交指定设备、提交时切焦点不串线、系统本机打开、批量／大原件。下一步外部URI→选A→切到B→独立核验A字节且B不变，并测授权撤回 | [13](issues/13-device-targets-and-sharing.md)、[09](issues/09-file-endpoints-and-recovery.md)、[20](issues/20-android-validation-bench.md) |
| 11 后台、恢复与活动；R21/R38–R40，C28–C29 | **部分**：不可见视频协作暂停、主动声音／Activity重建、同runtime水位快照校准和过期播放器清理、主标签核验重试；回复跨页保护；A44系统保存持久账本及重开pending转unknown，真实saved离页重进通过 | **未实现／未验**：断网／换网／进程死亡／系统Stop／重启的完整活动意图与恢复资格；观察／音源／任务完整独立停止。Android写入中杀进程的unknown恢复仍未验。下一步活动×中断原因矩阵逐格注入并核对主动停仍停／未知副作用不重放 | [14](issues/14-background-and-recovery.md)、[15](issues/15-identity-trust-and-transports.md)、[20](issues/20-android-validation-bench.md) |
| 12 设计、易用性与研究；R01/R41–R50/R52，C01–C32 | **部分**：同一pen **89独立页／12类／26母组件／557实例／153变量**，保存重开核对；新tch6A／qTeGO；浅色／黑中性／小彩色／Lucide、全屏共享组件；实时背景折射已实现并有实际视频截图 | **未实现／未验**：全部状态与实际UI闭环、可打断液态形变、独立光学／视频性能／大字／读屏／高对比／减少动态矩阵、token全覆盖；A45退出约定不一致；OPPO／vivo地区与端角色操作证据。下一步按coverage逐流程补入口→操作→失败→恢复并对照真实UI，89页静态完整性不等于实现验收 | [16](issues/16-glass-and-performance-budget.md)、[17](issues/17-manufacturer-mobile-flows.md)、[18](issues/18-complete-design-state-coverage.md)、[19](issues/19-dependency-license-and-updates.md) |

## 证据入口与优先顺序

1. **先修可造成退出阻塞／重复写入的断链**：A43／A44／A49，回归失败、挂起、离页重进、迟到回执与系统返回；A43局部红绿通过、同session重进／真实故障仍待验。A44持久账本、跨页unknown及真实saved重进已补，Android实际杀进程unknown故障待验。
2. **完成本轮在途行为的真实页面验收**：主屏应用回退／中文错误；保留3项widget及真实Runtime证据边界。随后A45内拖状态、A48共享冲突UI、A46 CI门禁，分别回填既有任务。
3. **继续完整目标**：IME、认证接续、批量内容与入站提交、活动恢复、通话、动态视觉／无障碍／性能、生产密码与四端整包；环境内可做项继续推进，缺物理设备／宿主单独登记。

| 证据 | 可复现入口／实际边界 |
| --- | --- |
| [首次安全配对](../../docs/implementation/first-pairing.md) | 真实产品表单、系统API精确撤权；直接Settings Forget失败原样保留，不称量产安全验收 |
| [总验收记录](../../docs/implementation/validation.md)、[状态恢复](../../docs/implementation/state-recovery.md) | 命令、失败、完成回执与截图路径；同runtime校准不等于断网／进程恢复 |
| [内容交付](../../docs/implementation/content-delivery.md)、[搜索](../../docs/implementation/file-search.md) | 单项文本／JPEG／MP4与搜索已有真实结果；A44新增持久账本与真实saved页面重进，Android杀进程unknown仍未验；首次重进夹具失败未计通过 |
| [系统提醒](../../docs/implementation/system-notifications.md) | 真实OS投递／撤回／点击；仍保留权限／认证／冷启动等矩阵 |
| [主屏应用widget](../../apps/connect/test/app_launch_test.dart)、[公开Runtime真实测试](../../crates/interop_core/tests/app_launch_android.rs) | 当前工作区改动；Runtime实际任务在display0，3项widget覆盖UI协议／未知启动不重发，尚无当前UI E2E |
| [Pencil覆盖](../../designs/prod/coverage.md)、[交互规则](../../designs/prod/interaction-rules.md) | 89页静态结构与产品规则；实际实现和动态验收逐项单独核对 |

## 历史与更新规则

[重新核查第12.1节](completion-reassessment.md#121-可见会话的每一次输入如何落到要求)保留逐指令追溯；A01–A42、最初R/C表及历次批次是历史证据。持续观察、系统提醒、共享折射、单项系统保存、搜索、首次安全码配对已有后续成果，读取旧缺口时必须回到本页判断。A43–A49是本轮新增发现，编号回填原20任务，不另造平行任务。

当前本地Android整包通过与CI持续门禁、静态设计与动态产品、AVD授权与生产密码、同进程恢复与进程重建分别判断。只有所有[完成门槛](goal.md#完成门槛)满足后才可把目标改为complete；本轮继续active。

本轮复验：应用195项测试通过（15秒，`/tmp/connect-full-audit-app-tests.log`）；严格分析先发现5处缺少花括号，修正后无问题；build_runner生成一致性143输入通过（10秒）。退出修复本地提交`0bf9cb1`；设计补页本地提交`6d00d71`。普通main重新构建安装，实际R热重启1,401ms并截图检查设备列表空态；仍有两条FRB旧isolate告警及SurfaceSync／跳帧日志。该启动检查不代替真实断线退出E2E或全页面视觉验收。
