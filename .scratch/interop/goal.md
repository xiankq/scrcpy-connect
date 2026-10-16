# 持续实施目标与验收契约

启动：2026-10-16。最近核验：2026-10-17。用户明确要求目标模式、完整实现、反复验收，允许AVD/无头Android、视觉检查与真实E2E。此文件是持续执行入口，不能用一次交付摘要替代完成判据。

## 目标

完成可实际连接、控制和协同另一台Android手机的互联产品。Flutter承载界面与呈现，Rust建设不调用外部adb的完整主机库和持续活动核心，经flutter_rust_bridge供Dart使用；采用monorepo、Hooks/Riverpod。Android手机控手机优先，保留平板/桌面布局，四平台实际编译与Android实际运行分别验收。ADB依赖尽量纯Rust，不能用不成熟密码实现假称生产验收。

设备列表固定首屏、所有设备平等；设备记录、配对信任、连接、控制会话与传输任务分开。被控无root、无额外APK，仅要求系统调试授权，允许临时JAR。主控始终不开调试，不跳过信任或认证。最新版ADB/scrcpy文档与固定源码对照实现，服务端可复用，自行编排完整生命周期。

功能与取舍完整遵循spec、prod/scope、57项需求、32项流程与本会话最新纠正：设备管理/发现/配对/手动地址/USB、全屏投控和真实应用任务、文件/相册手动取用、传输冲突与恢复、实时通知与原应用、分级通话/声音、剪贴板对象、后台与中断恢复。录屏、自动备份、独立短信/联系人/相机/终端、自动编辑回写保持退出范围。

默认浅色，黑色/中性色为主题色，彩色图标小元素、液态玻璃导航/控制、Lucide优先，视觉值来自designs/design.md。移动远控全屏保留源画面比例，唯一常驻本机控件为可拖动、左右吸附收起且可访问的退出；所有异常/面板也保持全屏。77页设计是输入，缺失状态要在实际交互中补齐，并必要时回补Pencil共享组件。

## 权威输入

- [总规格](spec.md)、[57项需求](requirements-audit.md)、[兼容矩阵](compatibility-matrix.md)、[访谈](interview.md)。本会话最新明确指令优先于历史记录。
- [产品说明](../../designs/prod/README.md)、[32条流程](../../designs/prod/coverage.md)、[页面与转换](../../designs/prod/user-flows.md)、[交互规则](../../designs/prod/interaction-rules.md)。
- [视觉规范](../../designs/design.md)、[Pencil源文件](../../designs/mobile.pen)，不得作为文本读写pen。
- [词表](../../GLOSSARY.md)、[ADR](../../docs/adr/)、[全部研究与来源](../../docs/research/README.md)、[20项研究/验证任务](issues/README.md)。历史未采用候选不自动恢复产品范围。

## 验收循环

每条能力持续执行：固定版本与通过条件→实现真实链路→协议/业务/集成测试→构建→安装启动→真实设备操作和故障注入→截图与交互/性能检查→修复→相关回归→记录证据并按主题提交。测试通过后不无目的重复；新改动、故障和未解决风险必须触发相应回归。不得以TODO、假数据、mock成功、静态截图或按钮存在作为实现通过。

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

## 逐项状态

初始状态继承当前事实：只有静态设计与研究，应用尚未实现。以下逐项随可复现证据更新；每条可引用实施记录，不能只改文字为通过。

| ID | 验收需求 | 实施/验收状态 | 证据 |
| --- | --- | --- | --- |
| R01 | 参考小米桌面与iOS、OPPO/vivo/苹果等成熟互联，完整规划，常规取舍由代理负责 | 既有竞品研究与规划完成；实现持续验收 | docs/research/manufacturer-*与prod/scope；运行功能逐项回填 |
| R02 | 面向普通用户，首次尽量无感、日常简单，不让用户输命令 | 引导/表单/扫码路径已实现；普通用户可用性仍待验 | product_flow真实手动连接；首次系统调试授权仍不能由普通App跳过 |
| R03 | Android手机控手机优先；平板与桌面扩展 | 手机双机全屏操作/后台恢复/五codec渲染通过；平板静态验收 | product_flow/background_resume/native_video_codecs；平板widget截图 |
| R04 | 被控无需额外APK/no root，系统调试授权，允许临时JAR | 真实被控端通过；Android主控部分通过 | 固定5.0.1 JAR与真实adbd/虚拟display测试；无APK/root |
| R05 | 主控始终不要求调试，不提供本机ADB增强 | 已实现；Android普通权限路径 | 主控仅网络、USB授权、媒体播放；测试调试只部署使用 |
| R06 | 仅Android当前实施／运行验证，未来iOS/Windows/macOS留适配 | Android整包运行已通过；其他平台接口已建 | Flutter四端runner；ADB/core跨target检查，Apple/Windows宿主链接未通过 |
| R07 | 四端都必须实际可编译，区别运行支持 | 部分检查；整包受宿主限制 | ADB四target、core三target check；FRB Apple/Windows链接缺SDK/MSVC |
| R08 | 尽量整个ADB依赖链纯Rust；未默认接受原生密码后端 | 纯Rust协议已实现；发布安全未验收 | RustCrypto experimental与RSA时序风险未解除 |
| R09 | 独立、完整Rust ADB主机库，不依赖外部adb可执行文件 | 主要协议、reverse/JDWP及压缩已真实通过；完整性继续审查 | 44默认测试；官方adbd三压缩/LST2/reverse；81e3bd2 |
| R10 | 参考最新版ADB无线；USB/局域网及已有可达跨网，不依赖账号云/中继/自动穿透 | 现代无线实际通过；USB编译未实物验收 | 真实PAKE/TLS及重连；手动TCP；USB系统授权/FD导入与取消路径 |
| R11 | 复用scrcpy server JAR但自行实现主控流程 | 已实测 | crates/interop_core/tests/scrcpy_device.rs；实际SPS/PPS/IDR与主控首帧 |
| R12 | 最新版单应用启动、独立显示、多实例按实际支持 | 真实被控端通过；主控应用页待完整E2E | scrcpy_device：Settings虚拟display、应用枚举、任务保留 |
| R13 | Rust/Flutter，Flutter主要UI与呈现，FRB供Dart调用 | Android运行已通过；流程继续验收 | FRB2.13.0，真实主控启动/Texture/AudioTrack |
| R14 | monorepo | 已实现并构建 | Cargo/Dart workspace及首个Android APK |
| R15 | Flutter Hooks/Riverpod等主流方案 | 已实现并验证 | Flutter hooks/riverpod；widget及实际Android界面 |
| R16 | fvp作为初选，可验证后调整 | 已按实测分媒体适配 | fvp保留桌面视频预览；Android实时流采用MediaCodec Texture |
| R17 | 可调用Android模拟器进行调试 | 已完成环境与实测 | 三台独立API36 AVD，KVM无头；5554主控/5556和5558被控 |
| R18 | 按功能分级；被控Android5+基础、现代系统无线/声音分别支持 | 能力分级已实现；仅API36运行证据 | API等级与实际错误分开；旧API/OEM矩阵待验 |
| R19 | 设备优先首页/工作台、全局传输、设备信息与连接诊断 | 设备首屏/工作台/文件真实通过；其余流程继续验收 | product_flow与widget；全局传输/诊断已接真实核心 |
| R20 | 多设备、多控制会话、传输并行；手机切换/分屏、大屏并排 | 两台被控同时连接及对象隔离真实通过；多控制窗口/布局继续验收 | native_clipboard_test三AVD；多会话实际资源矩阵待补 |
| R21 | 后台连接/通知/传输继续，暂停不可见视频，主动音频保持，回前台恢复 | HOME视频与声音策略真实通过；长后台/进程回收待验 | background_resume及native_audio：默认停声/主动续声/OS媒体FGS；连接/通知/传输长时仍待验 |
| R22 | 默认低延迟；清晰度/帧率/码率/编码器及三档预设 | 五codec/逐设备参数已渲染；HEVC已定位目标编码器尺寸降级，实际尺寸提示待新包验 | bfaee32；五种FFmpeg真实解码与Native全屏；质量保存下次打开，保留旧会话；非延迟数值验收 |
| R23 | 不引入查看模式、直接操作；保留主动实体屏幕开关，与锁定分开 | 直接触控真实通过；实体屏开关仍待专门验收 | product_flow真实点击；无查看模式；不绕过锁屏 |
| R24 | 真实应用任务/登录态；单实例迁移说明，多实例按实际能力 | 真实被控端通过；主控启动页继续E2E | 独立display启动Settings，关闭后实际任务仍存在 |
| R25 | 关闭窗口默认与任务去向依据scrcpy，由代理定默认 | 已按scrcpy设置并实测 | vd_destroy_content=false；停止会话后任务保留，迁移/多实例按实际系统 |
| R26 | 声音按设备只播一次；多设备默认单路，可固定/主动混音 | 单设备真实播放/暂停/后台策略通过；多设备混音仍待实测 | native_audio start/dedup/volume/mute/pause/head/resume/HOME/stop；共享AudioFocus JVM7 |
| R27 | 剪贴板跟随当前设备，可固定，其他后台设备不覆盖 | 文本自动同步三AVD真实通过；普通主控后台暂停访问 | 本机↔目标/独立客户端变更/跟随固定隔离/HOME零读写/禁用；图片文件剪贴板仍分级待补 |
| R28 | 文本/图片/文件、系统分享、本机打开；内容和目标可辨 | 路由/确认已实现，文本与系统文件部分真实通过 | clipboard与SAF E2E；图片/文件系统分享及本机应用打开仍待E2E |
| R29 | 同名询问保留两份/替换/跳过，可应用当前任务 | 批冲突实际通过 | files_android.rs：本批applyToAll隔离，未知保存结果不重试 |
| R30 | 文件浏览/搜索/目录/基本管理、批量双向取用与传输 | 文件/目录/本机SAF真实通过，provider故障矩阵仍待补 | files_android5+files_tree_android4；SAF三阶段实际字节/空目录通过 |
| R31 | 相册图片/视频预览、手动保存分享，拍摄/修图转原应用 | 页面已实现；缩略图效率与相册真实E2E在补 | 目标端有界JPEG、EXIF8方向/视频旋转/缓存/取消实际通过；主控新链路待E2E |
| R32 | 来电/通话页，接听拒接挂断，双向语音按能力，拨号等去原应用 | 真实来电状态通过；安全逐通话控制待实现 | 聚合Telecom API无法绑定具体call；快速A结束/B来电负例证实；危险全局动作已拒绝 |
| R33 | 短信只通知与远控原应用，不做收件箱/写库/短信业务页 | 范围与UI已落实；通知原应用路径真实被控端通过 | 无独立SMS业务页；原通知PendingIntent/手机应用入口 |
| R34 | 其他消息/邮箱/日历等完整业务也进入原应用，非每类重建一页 | 原应用路由已实现；部分真实通过 | notifications.open真实Settings任务接续；控制会话无重新登录/克隆 |
| R35 | 实时通知同步手机；清除/打开/原通知快捷回复，旧动作重验 | 真实被控端部分通过；主控通信页待E2E | snapshot/事件/原PI/清除/stale校验通过；RemoteInput仅系统接受，应用实际送达未验 |
| R36 | 长期通知历史移出范围，替代Q27旧可选历史 | 实现中未持久化通知正文或历史 | companion内存快照；生产无历史归档页面 |
| R37 | 唤醒仅打开远控，不强制实体亮屏，需认证走手机解锁 | power_on=false，休眠隔离实测不自动开屏；显式wake通过 | sleeping_target_requires_explicit_wake；不声称验证密码/生物认证矩阵 |
| R38 | 按原因/操作恢复，主动停保持停，未知发送/拨号/删除不重放 | 取消/主动断开与文件未知提交已有验证；进程回收恢复待补 | device_lifecycle、files_state、原子助手未知receipt；通知回复不自动重发 |
| R39 | 资源不足保护已有重要活动和当前操作，先降新/非焦点负载 | 原子启动预留及保留旧活动通过；本机精确资源错误单次降新负载已实现待验 | resource_admission默认5+真实guard1；Native1100才降无应用副作用的新画面，1101/未知不重放；未验实际硬件耗尽 |
| R40 | 主控身份本机保管不自动迁移；元数据独立恢复，换机重新授权 | 已实现并测试 | preferences_lifecycle三项，包括USB/待连接无线0端口恢复；不含私钥不恢复授权 |
| R41 | Apple/iOS Liquid Glass理念，官方网页研究；最新要求加强玻璃透色、亮边与控制层次 | 共享玻璃材质实现；实际浅色首屏/静态多外观验收 | 对比合成修复；深浅×黑白背景实际像素文字对比测试≥4.5；动态性能待验 |
| R42 | 黑色/中性色是主题色，默认浅色，深色可选；允许图标/小元素彩色，否定深绿按钮 | 默认浅色/黑色主题/彩色Lucide已实现 | 真实启动图、浅深与低透明度widget截图；无厚重深绿按钮 |
| R43 | Lucide优先，无适配才Iconify | Android主UI/通知/启动图标统一Lucide | lucide_icons_flutter；启动矢量link-2；其他runner默认图标仍待替换 |
| R44 | 遵循Google DESIGN.md，使用官方NPM校验 | 官方校验已运行 | @google/design.md@0.4.0：0 errors，26 warnings（玻璃扩展/未引用token） |
| R45 | 用Pencil绘制，CLI可用时可按规则操作 | 既有设计已完成；运行后继续核对 | f18c150；mobile.pen77页与共享组件 |
| R46 | 同一.pen每页独立，按类型分类、一类一行 | 既有设计已完成 | 同一pen按类型12组逐行；77独立页面 |
| R47 | 移除previews和designs根README；导出临时；源素材可保留 | 已完成并遵循 | 仓库无previews；本轮所有截图均/tmp |
| R48 | 在ADR/技术文档与画布间解释产品，不讲库与代码路线 | 既有产品说明已完成 | designs/prod/ 与产品流程/交互规则 |
| R49 | 不做录屏/备份；自动回写、相机、硬件共享、开发面板等移出 | 范围已落实；持续审计 | 应用未提供录屏/备份/独立短信等退出能力 |
| R50 | grill-me/grill-with-docs形成研究与文档；事实代理查、常规不重复问 | 既有研究/访谈完成；实现证据持续回填 | docs/research与20研究/验收任务；常规技术取舍自主推进 |
| R51 | 远控沉浸全屏，像直接使用远端手机；悬浮退出可拖动并吸附侧边隐藏 | 真实全屏、触控、吸附展开退出与后台恢复已通过 | product_flow_test和background_resume_test；截图目视无卡片/错误覆盖 |
| R52 | 善用共享组件与实例，重复远控底层/控件/面板通过母组件统一更新 | Pencil共享组件既有完成；Flutter组件已落地 | 23母组件/470实例引用；packages/design_system共用glass/按钮/导航 |
| R53 | 固定设备列表，所有设备平等，不存在备用手机角色 | 首屏实际通过 | /tmp/connect-avd/startup.png；生产无假设备/备用角色 |
| R54 | 完整连接表单、设备管理与关联流程，按类型优化当前页面 | 手动连接/文件/全屏退出真实通过；其他系统授权流程持续验收 | product_flow_test；配对/二维码/USB表单及owned取消widget；物理USB未验 |
| R55 | 每个页面独立文件，Dart页面文件统一以_page.dart结尾 | 正在按功能拆分 | 2026-10-17用户新增要求；迁移后重新验收 |
| R56 | 采用go_router管理业务页面与返回、替换、系统分享路由 | 正在迁移 | 明确路由身份/ID参数；远控root全屏；不以generic Widget extra包装代替 |
| R57 | 多文件夹架构，lib下直接pages及少量共享目录 | 正在迁移 | lib/pages/<页面>/<页面>_page.dart；共享widgets/services/router另放，不增加features/core/app嵌套 |

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
