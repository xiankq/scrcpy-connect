# 持续实施目标与验收契约

启动：2026-10-16。最近核验：2026-10-17。用户明确要求目标模式、完整实现、反复验收，允许AVD/无头Android、视觉检查与真实E2E。此文件是持续执行入口，不能用一次交付摘要替代完成判据。

## 目标

完成可实际连接、控制和协同另一台Android手机的互联产品。Flutter承载界面与呈现，Rust建设不调用外部adb的完整主机库和持续活动核心，经flutter_rust_bridge供Dart使用；采用monorepo、Hooks/Riverpod。Android手机控手机优先，保留平板/桌面布局，四平台实际编译与Android实际运行分别验收。ADB依赖尽量纯Rust，不能用不成熟密码实现假称生产验收。

设备列表固定首屏、所有设备平等；设备记录、配对信任、连接、控制会话与传输任务分开。被控无root、无额外APK，仅要求系统调试授权，允许临时JAR。主控始终不开调试，不跳过信任或认证。最新版ADB/scrcpy文档与固定源码对照实现，服务端可复用，自行编排完整生命周期。

功能与取舍完整遵循spec、prod/scope、R01–R60、32项流程与本会话最新纠正：设备管理/发现/配对/手动地址/USB、全屏投控和真实应用任务、文件/相册手动取用、传输冲突与恢复、实时通知与原应用、分级通话/声音、剪贴板对象、后台与中断恢复。录屏、自动备份、独立短信/联系人/相机/终端、自动编辑回写保持退出范围。

默认浅色，黑色/中性色为主题色，彩色图标小元素、液态玻璃导航/控制、Lucide优先，视觉值来自designs/design.md。移动远控全屏保留源画面比例，唯一常驻本机控件为可拖动、左右吸附收起且可访问的退出；所有异常/面板也保持全屏。77页设计是输入，缺失状态要在实际交互中补齐，并必要时回补Pencil共享组件。

## 权威输入

- [总规格](spec.md)、[R01–R60](requirements-audit.md)、[兼容矩阵](compatibility-matrix.md)、[访谈](interview.md)。本会话最新明确指令优先于历史记录。
- [产品说明](../../designs/prod/README.md)、[32条流程](../../designs/prod/coverage.md)、[页面与转换](../../designs/prod/user-flows.md)、[交互规则](../../designs/prod/interaction-rules.md)。
- [视觉规范](../../designs/design.md)、[Pencil源文件](../../designs/mobile.pen)，不得作为文本读写pen。
- [词表](../../GLOSSARY.md)、[ADR](../../docs/adr/)、[全部研究与来源](../../docs/research/README.md)、[20项研究/验证任务](issues/README.md)。历史未采用候选不自动恢复产品范围。

## 验收循环

每条能力持续执行：固定版本与通过条件→实现真实链路→协议/业务/集成测试→构建→安装启动→真实设备操作和故障注入→截图与交互/性能检查→修复→相关回归→记录证据并按主题提交。遇到慢首帧、平台限制或重复失败时，先查官方文档与固定源码，用独立输入/后端/工具构造对照；及时调整路径，不固守一个未经验证的假说。测试通过后不无目的重复；新改动、故障和未解决风险必须触发相应回归。不得以TODO、假数据、mock成功、静态截图或按钮存在作为实现通过。

测试中的官方adb仅用作设备部署、对照和验收工具，产品运行不能调用或分发该可执行文件。主控测试AVD本身打开调试仅是测试部署条件，不能转化为产品用户要求。需要两台Android时分别建主控/被控AVD，记录设备API/ABI、网络/端口/授权、构建摘要和操作结果。

视觉检查至少包含设备列表、空态/搜索、添加及错误表单、详情/诊断、全屏与退出拖动/左右收起、文件/传输/相册、通知/通话受限状态、主题/大字/横屏。截图和导出放系统临时目录；仓库保留复现方法、结论、必要摘要及源资产，不提交大量预览。

实测区分纯协议fixture、真实adbd、Android主控端到端、模拟器能力和真机能力。USB/音频HAL/硬解/OEM后台/热功耗及Apple/Windows构建缺少环境时，如实记录现有证据、已尝试替代与所需外部条件，不伪造通过、不静默删需求。只要还有可独立推进的实现/验收，继续工作。

## 完成门槛

1. 可复现monorepo与固定工具链/锁文件，生成绑定可重建，构建/测试/设计lint有自动化入口。
2. 独立ADB库按参考行为覆盖握手/认证/TLS配对/发现/USB/stream/shell/sync/服务，具有坏帧、取消、超时、恢复和官方互操作证据。
3. 真实Android主控经Rust/FRB连接被控、启动临时JAR、解码/输入/内容协同，完整核心流程与失败恢复通过真实E2E。
4. 当前保留的每项功能有真实可用或有依据的能力分级；未测试不是不可用，不能把缺实现藏进不支持。
5. UI遵循设计并经实际截图/操作复核，后台/安全/未知副作用/资源/无障碍/低延迟按风险验收。
6. Android/iOS/Windows/macOS核心、FRB最终链接与Flutter整包有对应宿主实际产物；运行支持另列。
7. 全部需求与流程有实现和证据定位，重大缺陷已修复，剩余真实外部阻塞明确且不被标为完成。工作按主题提交；没有要求推送、发布或部署。

## 当前重新核查优先

2026-10-17已按当前源码/Pencil/实际测试路径重新核查，见[完整重新核查](completion-reassessment.md)：60条会话需求、32流程、20任务；再次逐指令复核补入A37–A42。下表的局部实验不能覆盖该文件发现的产品断链；诊断、首次画质选择、手机三窗口和事件缺口核验已有修复证据；主屏回退、持续通知与认证、断网/进程恢复、内容交付、通话与液态玻璃仍未完成。当前不是“只差验证”，当前差距优先见重新核查第12节。

## 逐项状态

初始状态曾为只有静态设计与研究；现有工程和部分真实证据如下。逐项当前限制以重新核查为准；每条须引用实施记录，不能只改文字为通过。

| ID | 验收需求 | 实施/验收状态 | 证据 |
| --- | --- | --- | --- |
| R01 | 参考小米桌面与iOS、OPPO/vivo/苹果等成熟互联，完整规划，常规取舍由代理负责 | 既有竞品研究与规划完成；实现持续验收 | docs/research/manufacturer-*与prod/scope；运行功能逐项回填 |
| R02 | 面向普通用户，首次尽量无感、日常简单，不让用户输命令 | 引导/表单/扫码路径已实现；普通用户可用性仍待验 | product_flow真实手动连接；首次系统调试授权仍不能由普通App跳过 |
| R03 | Android手机控手机优先；平板与桌面扩展 | 手机双机全屏操作/后台恢复/五codec渲染通过；平板静态验收 | product_flow/background_resume/video_codecs；平板widget截图 |
| R04 | 被控无需额外APK/no root，系统调试授权，允许临时JAR | 真实被控端通过；Android主控部分通过 | 固定5.0.1 JAR与真实adbd/虚拟display测试；无APK/root |
| R05 | 主控始终不要求调试，不提供本机ADB增强 | 已实现；Android普通权限路径 | 主控仅网络、USB授权、媒体播放；测试调试只部署使用 |
| R06 | 仅Android当前实施／运行验证，未来iOS/Windows/macOS留适配 | Android整包运行已通过；其他平台接口已建 | Flutter四端runner；ADB/core跨target检查，Apple/Windows宿主链接未通过 |
| R07 | 四端都必须实际可编译，区别运行支持 | 部分检查；整包受宿主限制 | ADB四target、core三target check；FRB Apple/Windows链接缺SDK/MSVC |
| R08 | 尽量整个ADB依赖链纯Rust；未默认接受原生密码后端 | 纯Rust协议已实现；发布安全未验收 | RustCrypto experimental与RSA时序风险未解除 |
| R09 | 独立、完整Rust ADB主机库，不依赖外部adb可执行文件 | 主要协议、reverse/JDWP及压缩已真实通过；完整性继续审查 | 44默认测试；官方adbd三压缩/LST2/reverse；81e3bd2 |
| R10 | 参考最新版ADB无线；USB/局域网及已有可达跨网，不依赖账号云/中继/自动穿透 | 现代无线实际通过；USB编译未实物验收 | 真实PAKE/TLS及重连；手动TCP；USB系统授权/FD导入与取消路径 |
| R11 | 复用scrcpy server JAR但自行实现主控流程 | 已实测 | crates/interop_core/tests/scrcpy_device.rs；实际SPS/PPS/IDR与主控首帧 |
| R12 | 最新版单应用启动、独立显示、多实例按实际支持 | 真实被控端通过；主控应用页待完整E2E | scrcpy_device：Settings虚拟display、应用枚举、任务保留 |
| R13 | Rust/Flutter，Flutter主要UI与呈现，FRB供Dart调用 | Android运行已通过；流程继续验收 | FRB2.13.0，真实主控启动/共享fvp Texture与PCM |
| R14 | monorepo | 已实现并构建 | Cargo/Dart workspace及首个Android APK |
| R15 | Flutter Hooks/Riverpod等主流方案 | 已实现并验证 | Flutter hooks/riverpod；widget及实际Android界面 |
| R16 | fvp作为初选，可验证后调整 | 共享fvp五codec/PCM/后台/旋转/双设备焦点通过；长期与四端待验 | 官方文档对照；实际像素/时钟/Activity重建；旧Native视频和音频播放循环均已删除 |
| R17 | 可调用Android模拟器进行调试 | 已完成环境与实测 | 三台独立API36 AVD，KVM无头；5554主控/5556和5558被控 |
| R18 | 按功能分级；被控Android5+基础、现代系统无线/声音分别支持 | 能力分级已实现；仅API36运行证据 | API等级与实际错误分开；旧API/OEM矩阵待验 |
| R19 | 设备优先首页/工作台、全局传输、设备信息与连接诊断 | 首屏/部分文件和诊断真实页已通过；能力/最近状态仍未投影 | A04修复真实页证据；A25保持开放 |
| R20 | 多设备、多控制会话、传输并行；手机切换/分屏、大屏并排 | 手机主屏＋两应用保留/同ID切换/精确关闭已真实通过；系统分屏/大屏并排与资源降载缺实现 | 三窗口40秒、8次独立进程检查；重新核查第10–12节 |
| R21 | 后台连接/通知/传输继续，暂停不可见视频，主动音频保持，回前台恢复 | HOME视频/声音与同进程Activity重建通过；长后台/进程回收待验 | background_resume及audio_lifecycle：默认停声/主动续声/OS媒体FGS；新Activity/同PID/同音源；连接/通知/传输长时仍待验 |
| R22 | 默认低延迟；清晰度/帧率/码率/编码器及三档预设 | 五编码共享渲染、实际画质页首次选择已通过；HEVC实际尺寸/画质与总延迟仍未过 | 首帧研究、真实H.265页面选择；A10继续开放，不用媒体局部耗时冒充交互延迟 |
| R23 | 不引入查看模式、直接操作；保留主动实体屏幕开关，与锁定分开 | 直接触控真实通过；实体屏开关仍待专门验收 | product_flow真实点击；无查看模式；不绕过锁屏 |
| R24 | 真实应用任务/登录态；单实例迁移说明，多实例按实际能力 | 三个真实窗口保留/切换/关闭已实测；旧系统/拒副屏的主屏应用回退、最近常用仍缺 | session_workspace_test；A05/A06和任务迁回/多实例矩阵仍开放 |
| R25 | 关闭窗口默认与任务去向依据scrcpy，由代理定默认 | 已按scrcpy设置并实测 | vd_destroy_content=false；停止会话后任务保留，迁移/多实例按实际系统 |
| R26 | 声音按设备只播一次；多设备默认单路，可固定/主动混音 | 双设备同时播放及外部焦点实测通过；物理听感待验 | 真实双AVD音源/去重；外部AudioManager临时loss/手动暂停保留/gain/永久loss终止旧ID/新ID重新开启 |
| R27 | 剪贴板跟随当前设备，可固定，其他后台设备不覆盖 | 文本同步三AVD与后台停读已有证据；本次发现返回旧页面焦点未恢复会串设备，不能称完整跟随已通过 | ClipboardCoordinator实际同步；A38路由返回仍须补齐，图片文件剪贴板未完成 |
| R28 | 文本/图片/文件、系统分享、本机打开；内容和目标可辨 | 外部分享导入/取消九模式真实通过；提交至设备及本机打开待验 | Rust真实pipe字节/中文名/多文件/别名、拒绝无授权与本应用URI/超限、慢源取消、图片页目视；桌面返回宿主先红后绿 |
| R29 | 同名询问保留两份/替换/跳过，可应用当前任务 | 批冲突实际通过 | files_android.rs：本批applyToAll隔离，未知保存结果不重试 |
| R30 | 文件浏览/搜索/目录/基本管理、批量双向取用与传输 | 被控端文件/目录通过；共享SAF新路径与provider故障矩阵待验 | files_android5+files_tree_android4；旧SAF三阶段字节/空目录已通过，不能替代新共享复制路径验收 |
| R31 | 相册图片/视频预览、手动保存分享，拍摄/修图转原应用 | 页面已实现；缩略图效率与相册真实E2E在补 | 目标端有界JPEG、EXIF8方向/视频旋转/缓存/取消实际通过；主控新链路待E2E |
| R32 | 来电/通话页，接听拒接挂断，双向语音按能力，拨号等去原应用 | 真实来电状态通过；安全逐通话控制待实现 | 聚合Telecom API无法绑定具体call；快速A结束/B来电负例证实；危险全局动作已拒绝 |
| R33 | 短信只通知与远控原应用，不做收件箱/写库/短信业务页 | 范围与UI已落实；通知原应用路径真实被控端通过 | 无独立SMS业务页；原通知PendingIntent/手机应用入口 |
| R34 | 其他消息/邮箱/日历等完整业务也进入原应用，非每类重建一页 | 原应用路由和同设备主屏会话复用已做；认证后重验与不能定位路径仍缺 | notifications.open真实PI/Settings接续；Remote.start查既有session；A12 |
| R35 | 实时通知同步手机；清除/打开/原通知快捷回复，旧动作重验 | 部分原动作实验通过；连接未建立持续订阅、认证接续断开、后台提醒及真实回复送达未完成 | snapshot/事件/原PI/清除/stale校验通过；RemoteInput仅系统接受，应用实际送达未验 |
| R36 | 长期通知历史移出范围，替代Q27旧可选历史 | 实现中未持久化通知正文或历史 | companion内存快照；生产无历史归档页面 |
| R37 | 唤醒仅打开远控，不强制实体亮屏，需认证走手机解锁 | power_on=false，休眠隔离实测不自动开屏；显式wake通过 | sleeping_target_requires_explicit_wake；不声称验证密码/生物认证矩阵 |
| R38 | 按原因/操作恢复，主动停保持停，未知发送/拨号/删除不重放 | 同runtime事件缺口核验及可见同UUID恢复已真实通过；瞬断/进程意图恢复与回复跨页未知保护仍缺 | state_recovery_test及真实重复验收；A22/A40继续开放 |
| R39 | 资源不足保护已有重要活动和当前操作，先降新/非焦点负载 | 原子启动预留及保留旧活动通过；共享MDK资源错误分类及降低新窗口负载待补 | resource_admission默认5+真实guard1；旧Native1100降负载路径已停止使用，不以字符串猜测重放应用；实际硬件耗尽未验 |
| R40 | 主控身份本机保管不自动迁移；元数据独立恢复，换机重新授权 | 已实现并测试 | preferences_lifecycle三项，包括USB/待连接无线0端口恢复；不含私钥不恢复授权 |
| R41 | Apple/iOS Liquid Glass理念，官方网页研究；最新要求加强玻璃透色、亮边与控制层次 | 基础模糊/对比已做；当前白卡与静态渐变不足液态玻璃目标，折射/形变和动态验收缺失 | 对比合成修复；深浅×黑白背景实际像素文字对比测试≥4.5；动态性能待验 |
| R42 | 黑色/中性色是主题色，默认浅色，深色可选；允许图标/小元素彩色，否定深绿按钮 | 默认浅色/黑色主题/彩色Lucide已实现 | 真实启动图、浅深与低透明度widget截图；无厚重深绿按钮 |
| R43 | Lucide优先，无适配才Iconify | 主UI大多Lucide；默认BackButton与其他平台runner包装仍有偏差 | lucide_icons_flutter；启动矢量link-2；其他runner默认图标仍待替换 |
| R44 | 遵循Google DESIGN.md，使用官方NPM校验 | 官方校验已运行 | @google/design.md@0.4.0：0 errors，26 warnings（玻璃扩展/未引用token） |
| R45 | 用Pencil绘制，CLI可用时可按规则操作 | 设计源文件与工具路径已具备；缺失状态和运行对齐继续补齐 | f18c150；mobile.pen77页与共享组件 |
| R46 | 同一.pen每页独立，按类型分类、一类一行 | 静态结构已直接核对 | 同一pen按类型12组逐行；77独立页面 |
| R47 | 移除previews和designs根README；导出临时；源素材可保留 | 已完成并遵循 | 仓库无previews；本轮所有截图均/tmp |
| R48 | 在ADR/技术文档与画布间解释产品，不讲库与代码路线 | 产品说明层已建立，随行为持续同步 | designs/prod/ 与产品流程/交互规则 |
| R49 | 不做录屏/备份；自动回写、相机、硬件共享、开发面板等移出 | 范围已落实；持续审计 | 应用未提供录屏/备份/独立短信等退出能力 |
| R50 | grill-me/grill-with-docs形成研究与文档；事实代理查、常规不重复问 | 既有研究/访谈完成；实现证据持续回填 | docs/research与20研究/验收任务；常规技术取舍自主推进 |
| R51 | 远控沉浸全屏，像直接使用远端手机；悬浮退出可拖动并吸附侧边隐藏 | 真实全屏、触控、吸附展开退出与后台恢复已通过 | product_flow_test和background_resume_test；截图目视无卡片/错误覆盖 |
| R52 | 善用共享组件与实例，重复远控底层/控件/面板通过母组件统一更新 | Pencil已使用连接组件；Flutter共享组件已落地，视觉目标仍未完成 | 23母组件/470实例引用；packages/design_system共用glass/按钮/导航 |
| R53 | 固定设备列表，所有设备平等，不存在备用手机角色 | 首屏实际通过 | /tmp/connect-avd/startup.png；生产无假设备/备用角色 |
| R54 | 完整连接表单、设备管理与关联流程，按类型优化当前页面 | 手动连接/文件/单会话通过；未授权双机起点、完整系统授权与USB转无线闭环未完成 | product_flow_test；配对/二维码/USB表单及owned取消widget；物理USB未验 |
| R55 | 每个页面独立文件，Dart页面文件统一以_page.dart结尾 | 已实现并回归 | 40页面目录/独立_page.dart；78应用widget及真实后台路由通过 |
| R56 | 采用go_router管理业务页面与返回、替换、系统分享路由 | typed生成路由已实现并回归 | go_router_builder三tab shell/ID参数/恢复；远控root全屏及真实HOME返回通过 |
| R57 | 多文件夹架构，lib下直接pages及少量共享目录 | 已实现并回归 | lib/pages/<页面>/<页面>_page.dart；共享widgets/services/router另放，不增加features/core/app嵌套 |

| R58 | 使用go_router_builder、riverpod_generator、build_runner及官方lint，防止工程和架构退化 | 已完成生成迁移及严格分析/78项widget；真实Android五codec、后台与旋转通过 | 精确兼容版本、生成typed shell/导航、深冻结Notifier、根原生Riverpod插件负例实检、workspace only-check |
| R59 | Flutter/Rust为主体，减少自维护Android代码和未来多端重复适配 | 正在重构 | 分享owner/导入/持久化与SAF复制迁共享Dart/Rust；267行视频decoder与313行PCM播放器已删除；真实五codec/声音/Activity重建/双设备焦点通过，Kotlin删除播放器后1172行，补宿主/OS租约隔离后1246行（10文件）；OS适配仍保留，四端编译未冒称完成 |

| R60 | 首帧拿不到/慢时先查scrcpy开发者文档 | 已核对官方静止补帧/源码并修复播放器等待，当前五codec实际通过；总延迟/画质仍缺 | docs/research/scrcpy-first-frame-and-latency.md；重新核查A10 |

## 执行记录

- 2026-10-16：创建目标模式。宿主Ubuntu x86_64，Flutter3.47.6/Dart3.13.5、JDK21可用；已创建Flutter四端及Linux验收runner。Rust1.99.1已安装，AndroidSDK/NDK/AVD正在配置。KVM设备实际可读写；macOS/Windows构建宿主尚未发现。
- 并行实施：独立ADB帧/认证/stream/shell/sync、现代无线配对/TLS/发现、Flutter产品UI/设计系统。主代理承担workspace、FRB/核心编排、平台媒体、环境与端到端验收，修改范围互不重叠。

- Rust ADB实测：Android16真实adbd已通过连续shell、sync能力探测；修复真实adbd在EOF时额外发送尾WRTE导致误断开的问题，有界缓冲保留背压。
- 无线实测：错误配对码拒绝、正确PAKE配对、STLS/TLS1.3、shell及再次TLS重连通过。AVD的ro.adb.secure=0使未配对身份同样被系统接受，因此授权强制/撤权负例未通过；不能以此证明生产信任验收。
- scrcpy5.0.1实测：JAR上传/运行、两socket连接、视频元数据/SPS/PPS/IDR、错误本机token拒绝、真实应用枚举/Settings虚拟display、clipboard ACK/get、点击与英文/中文输入通过。关闭会话后真实应用任务仍存在。Android主控端实际解码尚待安装运行验证。
- Flutter：9项widget测试通过，覆盖无假设备空态、连接表单校验、源画面坐标/黑边、多指pointer与退出拖动点击；真实资产截图在/tmp/connect-ui-visual/，属于widget证据，非Android端到端。
- FRB2.13.0绑定生成、Rust bridge cargo check、Dart bridge analyze通过；Android首包正在构建。普通设置原子校验、元数据不导出私钥/不恢复授权、活动按连接/会话/传输分别停止已补齐，继续集成验证。

下一步：Android主控安装、首帧Texture与全屏交互E2E；独立设备音源/AudioTrack；文件竞态与真实传输；免APK通知/通话扩展；背景恢复与跨平台构建。目标仍未完成。

- 新增审查修复：原生音频/视频资源发布与取消串行；新USB尝试注册全局取消；含USB/无端口无线元数据可恢复；非UTF8文件名无可操作path，真实同名碰撞文件测试通过。原子文件rename助手与免APK通知/通话正在独立实施。

- 2026-10-17新增实际验收：Android主控AudioTrack首次写入/playing、单设备音源去重、音量/静音/停止完整E2E通过；已知频率PCM实采另外核验。用户可闻的物理扬声器/耳机链路未验。
- 文件安全回归：原始路径字节不会经有损UTF8映射成为另一个可操作文件；四ABI临时Rust助手完成同inode校验后执行真实renameat2，目录、符号链接、竞争目标/源、尾换行与FUSE均实测。推送先写part再原子提交；缺失/截断回执是result_unknown，不重放。
- 通话安全负例：聚合系统电话状态在A结束/B立即来电时可能不交付可区分转换，无法把观察ID作为具体通话身份。产品暂拒绝answer/reject/hangup并显示实现限制与手机入口；不得以早期全局API试验冒充安全通话控制完成。
- 界面新增回归：29项widget通过，含通知limited/unknown状态、送达未知保留草稿、批量来电事件、USB表单取消及退出按钮spring/生命周期。真实远控仍有首帧后暂停竞态，保留健康断言并通过真实时序诊断，未标完成。

- 后续已定位并修复初始暂停：inactive并非不可见，改为仅释放触点/禁止输入；hidden/paused/detached才暂停。真实HOME→Activity返回→native新frame的完整测试退出0，恢复截图目视通过。目标休眠另行返回device_asleep，并保留用户明确的唤醒动作。
- ADB第二批81e3bd2：reverse完整双向桥/授权入站OPEN、JDWP、单路径nofollow LST2及三压缩真实互操作，44默认测试与五target检查通过。工作区Rust全测/Clippy通过；Flutter39widget已通过。
- 目录4真实+旧文件5真实回归通过，保留源变化、部分失败、当前批冲突策略与取消语义；Android私有暂存不得称已保存到系统位置，SAF导入/导出继续实施。

- 2026-10-17共享媒体：核对官方scrcpy develop/SurfaceEncoder/ControlMessage/Controller与MDK API，修复起播前waitFor0同步等待、AV1默认FFmpeg路径，以及静止输入pause供帧顺序。五种codec真实Rust ADB→Matroska HTTP→fvp首帧/暂停/捕获恢复/非单色PNG/停止通过（12秒）；首帧1016/347/290/294/301ms，不含服务启动时间。记录docs/research/scrcpy-first-frame-and-latency.md；整机后台、旋转及音频迁移继续验收，没有标为全产品完成。

- 共享视频整机后台：background_resume_test实际HOME/2秒后Activity返回、Core暂停/恢复、session.output.resumed真实snapshot回执、全屏无暂停覆盖及正常退出通过，12秒；截图/tmp/connect-e2e/shared-background/remote-after-actual-background.png已目视检查。共享Dart61项、应用78项widget、Rust59项与all-target clippy通过。生成检查发现controller hash陈旧，已真实重生成，随后only-check零写入通过。

- 旋转与取消：同session/relay generation 1→2、真实新代像素/触控尺寸/Texture交接及bridge.dispose正常退出通过；目标自动旋转夹具恢复原值。修复Rust空闲事件流取消不退出，显式cancel token/RAII及7项API测试通过。删除Native视频后实际产品五codec完整回归28秒通过，提交4da9bf8；媒体driver在缺失完成回执时强制失败，负例已实测。

- 共享音频迁移：直接PCM生命周期4秒、产品HOME与同进程Activity重建14秒通过；补齐host退出前等待finally后13秒复验，完成回执true、开发设置恢复且临时archive不存在。外部AudioManager双设备焦点测试先红后绿16秒通过：临时loss保留手动暂停、永久loss关闭准确旧ID且gain不复活，用户显式新开取得新ID。修复旧焦点acquire/release迟到复用epoch竞态，22项对应单测与独立review通过。
- 整合tool/check.sh实际退出0：Rust133 passed/41 ignored、应用78、桥接71、生成only-check、严格分析、Riverpod插件负例及Google官方design lint通过（0 errors/26 warnings/1 info）。旧Rust生成格式和新增helper严格lint问题在首轮检查发现后修正，第二轮全绿。当前尚未完成长期后台、系统回收、真实HAL/扬声器、共享SAF新路径及外部分享实际验收等剩余矩阵。

- 外部分享实际验收：九模式20秒通过（/tmp/connect-incoming-share-final.log），真实URI grant/pipe进入Rust，校验字节、中文名、大小、多文件、错误原因、取消后pending及来源清理。测试提供方补onNewIntent/CLEAR_TOP|SINGLE_TOP、显式ClipData避免系统自动授权，以及未知大小null处理；超大AssetFD由Rust真实容量拒绝。图片页截图已目视。并非已验收提交到被控设备、恶意provider压力或120秒deadline。
- 分享后的桌面返回新负例确认：旧singleTop留下两个MainActivity，旧实例onStart/onResume仍脱离engine，/tmp/connect-share-launcher-before.log实际失败。singleTask后最小7秒通过，实际单宿主、resumed及设备列表正常。Discovery改每Activity独立token，USB交付后仅exact Rust ACK释放（上限16），无需Activity的release由process host处理；真实production协调器JVM端口测试与全Kotlin编译通过，物理USB未验。

- singleTask最终九模式+HOME/launcher组合16秒全过（/tmp/connect-share-acceptance-final.log，completiontrue），确实一宿主且Flutter resumed；焦点实际等待4ms，不能用am start -W的显示完成代替。返回设备列表与图片分享页截图已目视。严格Flutter分析、Dart格式、JVM ownership与diff检查通过；新共享SAF及分享真实提交等继续保留待验。

- 2026-10-17完整重新核查：发现36项实现/产品断链/设计/工程或验收缺口，逐项覆盖R01–R60/C01–C32/20任务；目标仍未完成。诊断与质量UI契约、真实产品验收假绿正在按独立批次修复，其余主线继续开放。

- 重新核查修复批次1660805：实际诊断JSON、画质首次尝试及远控反馈作用域已修复。83应用测试和严格分析通过；新APK真实UI从设备诊断/首次H.265选择到实际mdk.snapshot、全屏/触控/退出20秒通过，completion=true。H.265实际230×512仍明显低清，不算质量通过。真实验收缺配置/缺completion不能静默绿，纯Dart负例退出255，已加入check。全量目标及其余36项账本中的未闭合部分仍继续开放，详见重新核查第8节。

- 持续会话批次：手机主屏＋Settings＋Dialer三个真实会话保留、不可见捕获确认暂停、同ID恢复、精确窗口截图和单独关闭后其他窗口继续使用已通过；40秒UI E2E及8次独立进程核对。按scrcpy独立控制线程顺序修复空虚拟显示START_APP死等，并以被控端最小协作捕获补丁替代整进程SIGSTOP；主控仍使用Rust/Flutter/fvp。后续又锁定并修复配置包后空闲误超时、播放器换代取消恢复、迟到回执倒退和ready覆盖暂停。真实HOME回前台13秒、五编码新建/退出/关闭45秒通过。默认Rust135 passed/43 ignored、应用91、桥接83、严格分析/生成一致性/all-target clippy通过。源码到临时JAR可复现SHA及JVM门禁已接入默认检查。详见重新核查第10节和实施记录；大屏/分屏、主屏应用回退、IME、通知与通话、完整恢复/事件重取、系统文件保存、液态玻璃及四端整包仍未完成。


- 2026-10-17事件缺口核验批次：Rust统一sequence/只读event-fenced快照，FRB真实256容量溢出后重新订阅；Bridge合并核验、废弃旧水位、精确播放器清理；App冻结输入/剪贴板、校准同一UUID、已结束窗口不重建、普通页提供失败重试。设置发布/保存回执、forget、分享队列和companion缓存交错均有红→绿回归。连续复验又发现编码session首帧前重置导致旧新CSD混合，真实TCP复现后按session边界修复；终态也不能被迟到resume解除。核心cf35daf、Bridge3ee0318、媒体d7d60d8、应用591d48e。
- 最终Rust工作区146 passed/43 ignored、all-target clippy、应用全量114加后续远控20定向、Bridge93和严格分析/生成一致性通过。最终APK真实核验连续11/10/10秒三次完整通过，三窗口40秒＋8次独立进程检查、HOME恢复11秒通过，代表图已目视。仅为准备端点/同runtime状态恢复，不是未授权起点、完整断网/进程恢复或全设计通过；会话列表应用包名和白卡材质等继续进入缺口账本。详细命令/失败/边界见 docs/implementation/state-recovery.md、validation.md 和 completion-reassessment.md第11节。


- 2026-10-17再次逐指令审计：可见输入U01–U44逐条映射R01–R60，交叉核对32流程、20任务和现有文档/设计；新增A37–A42，当前完整差距按12领域记录。TLS强制策略8a91df6、独立观察生命周期df2af2d、远控返回焦点/主标签核验a117976、显式观察入口/逐事件来电1236987已分批本地提交。实际API36自动观察→stop后共享剪贴板→重连不复活→显式恢复11.10秒通过；最新APK双AVD产品流程18秒通过。最终App126/Bridge93、严格分析/生成检查及Rust157默认通过、43忽略、all-target clippy通过；忽略用例和本轮设备结果分列。实际目视仍存在HEVC低清和白卡材质；首次授权、通知OS投递/认证/跨页回复保护、真实通话、内容系统保存、完整恢复、设计闭环及四宿主整包等保持开放。目标active，不因审计或这些修复完成而标为complete。


- 2026-10-17后续实现：fb6b69d补发现/表单/Core的TLS类型与禁止降级；9f8448e统一专用页可见设备归属；ebd9bcb补有界跨页回复/未知提交保护、认证明确拒绝、权威恢复快照和容量回收；06a6c99加入独立受管Android原接收器。回复UI→原RemoteInput→独立原文/count1→离页保护→精确清除→过期route复制实际双AVD两轮约16秒通过，测试APK/通知/本次device已清理，最终轮文字基线恢复确认。旧裸shell receiver两次失败如实保留，未将fixture作为产品APK前提。Rust159默认通过/44忽略、App154、host3后续定向、clippy/严格分析/生成检查通过。最新旧TCP明确选择的产品19秒通过但HEVC仍230×512低清；目标保持active，完整差距与本轮边界见completion-reassessment第12/13节。

- 2026-10-17继续交付：63ad1ca实像素门禁重现HEVC1280低清，真实页选1080后486×1080/21秒通过；0f8ef66共享系统通知及精确所有权，f425e31双AVD系统区发布/撤回/实际点击/内容呈现18秒通过，无被控测试APK、无hostErrors。Flutter174、Rust160默认/44忽略、clippy/严格分析/生成检查通过。原始失败、汇总重复提醒修复、夹具时序问题及AVD进程退出均独立记录；不视作完整恢复或视觉通过。完整差距见completion-reassessment第12.2/14节，目标active。

- 2026-10-17视觉后续：ff6ec94接入共享实时折射及完整opaque绕过、光学tokens与Pencil连续通知行，2450e63修浅色状态栏/Lucide返回/空汇总及预览受限说明。175应用测试、3设计系统测试、严格分析/生成检查通过；实际视频及退出拖拽/收起/展开/返回24秒通过，encoded/decoded486×1080；系统区通知发布/精确撤回/点击呈现20秒通过。三段/17stop斜纹失败、径向修复、像素alpha夹具纠正及AVD启动ANR均保留证据。Pencil保存重开仍77页/12类/23母组件/470ref，预览仅tmp。液态形变、完整光学/性能/无障碍/77页一致性及第12.2节其余首次连接/输入/通话/内容交付/恢复/四宿主缺口继续开放，目标active。
