# 全会话需求审计与补齐账本

初始审计：2026-10-16；当前实现复核：2026-10-17。

**当前完成度唯一入口：[当前状态](current-status.md)。** [完整重新核查](completion-reassessment.md)保留U01–U44、R01–R60、C01–C32及A01–A48证据追溯；本文件主表是设计／研究阶段历史结论。“尚未实现／所有运行未验”只说明当时情况，不能覆盖后续实际结果，也不能把局部结果外推为整项完成。

初始审计范围：本会话可见的全部用户需求、Q1–Q38中实际可见回答、后续范围授权及最新视觉纠正。对未显示原题的“都对”，只采用已有访谈中可追溯的归纳，不虚构用户逐字确认。

## 初始结论与状态口径（历史）

有遗漏。主要是**已写需求没有状态/验收闭环、研究报告发生漂移、零散POC没有任务化**，而不是核心方向被全部漏掉。

- 已有：Rust/Flutter/FRB、monorepo、尽量纯Rust ADB、无被控APK与主控不调试、设备优先、真实应用任务、分级支持等已进入规格/ADR。画布当前为77页、十二类分行，默认浅色、黑色主题色。
- 本轮补齐：原50项需求逐条对照，追加全屏远控R51、组件R52、设备列表R53及连接闭环R54、32项产品流程覆盖表、兼容基线、20项后续任务（19研究/验证＋1设计补齐）、关键官方事实复核与相互冲突的旧文档修正。
- 仍未完成：应用工程、完整ADB实现、四端真实构建、Android运行/真机POC及覆盖表中缺失的画布状态。登记任务或文档调查不能把这些标通过。
- 已移除：录屏、文件/相册备份、独立SMS数据服务等；历史候选研究不重新构成产品承诺。普通文件手动保存、截图与真实远端应用不因此删除。

“已落实”下文只表示相应文档或静态稿存在；所有运行能力仍为未验。用户最新明确纠正和范围授权优先于旧答复，代理默认与用户确认分别标注。

## 逐项需求追溯

现行总规格：[spec](spec.md)。产品说明：[prod](../../designs/prod/README.md)。初始页面：[77页分组](../../designs/prod/user-flows.md#当前页面分组)。工程证据：[研究索引](../../docs/research/README.md)。

| ID | 会话依据 | 需求 | 对照结果／缺口 | 后续任务 |
| --- | --- | --- | --- | --- |
| R01 | 原始产品方向／后续授权 | 参考小米桌面与iOS、OPPO/vivo/苹果等成熟互联，完整规划，常规取舍由代理负责 | 已有厂商证据与scope；OPPO/vivo国内及手机操作细节不足 | [17](issues/17-manufacturer-mobile-flows.md) |
| R02 | Q2及后续纠正 | 面向普通用户，首次尽量无感、日常简单，不让用户输命令 | 已补连接表单、主控出示二维码及USB转无线条件稿；首次操作测量与协议互通仍未验 | [05](issues/05-ordinary-user-onboarding.md) |
| R03 | Q1 | Android手机控手机优先；平板与桌面扩展 | 布局已有；手机真实IME、手势、横屏和并行未验 | [08](issues/08-mobile-input-and-windows.md)、[20](issues/20-android-validation-bench.md) |
| R04 | Q7及明确约束 | 被控无需额外APK/no root，系统调试授权，允许临时JAR | ADR0001已定；JAR全生命周期与扩展权限未验 | [06](issues/06-server-orchestration.md)、[11](issues/11-notifications-continuation.md) |
| R05 | Q33 | 主控始终不要求调试，不提供本机ADB增强 | ADR0006已定；所有任务继续受此约束 | [05](issues/05-ordinary-user-onboarding.md)、[13](issues/13-device-targets-and-sharing.md) |
| R06 | 原始范围 | 仅Android当前实施／运行验证，未来iOS/Windows/macOS留适配 | 已记录；未来端运行未通过不算丢需求 | [03](issues/03-workspace-bridge-platform-builds.md)、[20](issues/20-android-validation-bench.md) |
| R07 | Q32最新补充 | 四端都必须实际可编译，区别运行支持 | 契约已有；旧‘只留静态接口’已修正，四端产物均未生成 | [03](issues/03-workspace-bridge-platform-builds.md) |
| R08 | Q22/Q32 | 尽量整个ADB依赖链纯Rust；未默认接受原生密码后端 | 已有深度依赖调查；纯度/成熟度与正式feature闭包未闭合 | [02](issues/02-pure-rust-crypto-dependencies.md) |
| R09 | 原始技术目标 | 独立、完整Rust ADB主机库，不依赖外部adb可执行文件 | 完整度清单已有；API/参考行为账本未形成 | [01](issues/01-adb-contract-and-wireless.md) |
| R10 | 原始要求 | 参考最新版ADB无线；USB/局域网及已有可达跨网，不依赖账号云/中继/自动穿透 | 已研究Wi-Fi2；需版本对照与Rust主机行为验收，并补VPN/网关可达路径、无法发现/不可达的反馈；不承诺自动穿透 | [01](issues/01-adb-contract-and-wireless.md)、[05](issues/05-ordinary-user-onboarding.md) |
| R11 | 原始要求 | 复用scrcpy server JAR但自行实现主控流程 | 协议调查已有；启动、通道、取消、并发和清理尚未实现 | [06](issues/06-server-orchestration.md) |
| R12 | Q25/Q37 | 最新版单应用启动、独立显示、多实例按实际支持 | 5.0.1已复核；启动原应用与Android10+独立显示须分级 | [04](issues/04-compatibility-capabilities.md)、[06](issues/06-server-orchestration.md)、[08](issues/08-mobile-input-and-windows.md) |
| R13 | 原始技术架构 | Rust/Flutter，Flutter主要UI与呈现，FRB供Dart调用 | 职责规划已有；接口和生命周期未实现验证 | [03](issues/03-workspace-bridge-platform-builds.md)、[07](issues/07-fvp-media-pipeline.md) |
| R14 | 原始要求 | monorepo | 目录规划已有；真实workspace尚未生成 | [03](issues/03-workspace-bridge-platform-builds.md) |
| R15 | 原始要求 | Flutter Hooks/Riverpod等主流方案 | 已记录；Rust会话与UI状态所有权需验证 | [03](issues/03-workspace-bridge-platform-builds.md) |
| R16 | 原始要求 | fvp作为初选，可验证后调整 | 已有字节流/PTS差异研究；实际实时链路未验 | [07](issues/07-fvp-media-pipeline.md) |
| R17 | 原始工具条件 | 可调用Android模拟器进行调试 | 此前未建立环境/用例账本；本轮补任务，不虚构已调试 | [20](issues/20-android-validation-bench.md) |
| R18 | Q11 | 按功能分级；被控Android5+基础、现代系统无线/声音分别支持 | 此前分散于报告；本轮补统一基线，基础/扩展版本不能混用 | [04](issues/04-compatibility-capabilities.md) |
| R19 | Q12及保留设备管理 | 设备优先首页/工作台、全局传输、设备信息与连接诊断 | 固定设备列表、空/检查/离线/搜索、设备详情与连接诊断已补；真实状态更新和诊断归因未验 | [05](issues/05-ordinary-user-onboarding.md)、[18](issues/18-complete-design-state-coverage.md) |
| R20 | 后续确认 | 多设备、多控制会话、传输并行；手机切换/分屏、大屏并排 | 有会话和大屏代表稿；规模、争用与切换未验 | [08](issues/08-mobile-input-and-windows.md)、[16](issues/16-glass-and-performance-budget.md)、[20](issues/20-android-validation-bench.md) |
| R21 | Q13/Q23 | 后台连接/通知/传输继续，暂停不可见视频，主动音频保持，回前台恢复 | 规则及后台页已有；系统/活动恢复分型不完整 | [14](issues/14-background-and-recovery.md) |
| R22 | Q14及访谈 | 默认低延迟；清晰度/帧率/码率/编码器及三档预设 | 已补清晰度/帧率/码率/编码器具体选项稿；应用反馈和性能通过门槛仍待验 | [07](issues/07-fvp-media-pipeline.md)、[16](issues/16-glass-and-performance-budget.md)、[18](issues/18-complete-design-state-coverage.md) |
| R23 | Q20及保留屏幕控制 | 不引入查看模式、直接操作；保留主动实体屏幕开关，与锁定分开 | 直接操作已遵守；手机手势/输入、实体屏幕当前状态/操作失败/退出恢复尚未验 | [06](issues/06-server-orchestration.md)、[08](issues/08-mobile-input-and-windows.md) |
| R24 | Q25 | 真实应用任务/登录态；单实例迁移说明，多实例按实际能力 | 已补单实例迁移确认；回退/焦点/关闭去向仍待验 | [06](issues/06-server-orchestration.md)、[08](issues/08-mobile-input-and-windows.md) |
| R25 | Q28交由能力研究 | 关闭窗口默认与任务去向依据scrcpy，由代理定默认 | 现默认保留并迁回，非用户逐项同意；ADR旧待问已修正 | [06](issues/06-server-orchestration.md)、[08](issues/08-mobile-input-and-windows.md) |
| R26 | Q24 | 声音按设备只播一次；多设备默认单路，可固定/主动混音 | 已补跟随/固定/混音及离线对象稿；成员选择、路由失败和实际播放仍待验 | [12](issues/12-calls-and-audio-arbitration.md)、[13](issues/13-device-targets-and-sharing.md) |
| R27 | Q34 | 剪贴板跟随当前设备，可固定，其他后台设备不覆盖 | 已补跟随/固定、主动发送/获取与读取限制；固定对象和运行反馈仍待验 | [13](issues/13-device-targets-and-sharing.md) |
| R28 | 已保留范围 | 文本/图片/文件、系统分享、本机打开；内容和目标可辨 | 有技术调查；实际URI/目标选择/失效反馈未验且欠稿 | [09](issues/09-file-endpoints-and-recovery.md)、[10](issues/10-gallery-video-and-content.md)、[13](issues/13-device-targets-and-sharing.md) |
| R29 | Q21 | 同名询问保留两份/替换/跳过，可应用当前任务 | 同名sheet已有；目录/源变化/恢复时冲突待验 | [09](issues/09-file-endpoints-and-recovery.md) |
| R30 | 专用功能页要求 | 文件浏览/搜索/目录/基本管理、批量双向取用与传输 | 已补目录、重命名、删除确认和部分失败详情；新建/搜索/操作结果与恢复实测仍缺 | [09](issues/09-file-endpoints-and-recovery.md)、[18](issues/18-complete-design-state-coverage.md) |
| R31 | 专用功能页要求 | 相册图片/视频预览、手动保存分享，拍摄/修图转原应用 | 已补视频播放/进度/声音及格式回退；缓冲、保存/分享进度和失败仍缺 | [10](issues/10-gallery-video-and-content.md)、[18](issues/18-complete-design-state-coverage.md) |
| R32 | 专用功能页要求 | 来电/通话页，接听拒接挂断，双向语音按能力，拨号等去原应用 | 可用/受限代表稿已有；HAL、多设备来电与路由状态未验 | [12](issues/12-calls-and-audio-arbitration.md) |
| R33 | 最新短信取舍 | 短信只通知与远控原应用，不做收件箱/写库/短信业务页 | 旧SMS研究仍可误执行，本轮归档退出任务 | [11](issues/11-notifications-continuation.md) |
| R34 | 最新同类路由授权 | 其他消息/邮箱/日历等完整业务也进入原应用，非每类重建一页 | 规则已定；不能定位/认证等路径未完整画出 | [11](issues/11-notifications-continuation.md)、[18](issues/18-complete-design-state-coverage.md) |
| R35 | Q27/Q30 | 实时通知同步手机；清除/打开/原通知快捷回复，旧动作重验 | 已补通知失效和未知回复保留提交内容；清除、发送中/明确失败和认证仍缺 | [11](issues/11-notifications-continuation.md) |
| R36 | 最新授权取舍 | 长期通知历史移出范围，替代Q27旧可选历史 | scope已定；本轮修正词表/报告相邻历史表述 | [11](issues/11-notifications-continuation.md)、[19](issues/19-dependency-license-and-updates.md) |
| R37 | Q38 | 唤醒仅打开远控，不强制实体亮屏，需认证走手机解锁 | 规则已定；锁屏→原应用续接缺代表状态 | [11](issues/11-notifications-continuation.md)、[18](issues/18-complete-design-state-coverage.md) |
| R38 | Q29 | 按原因/操作恢复，主动停保持停，未知发送/拨号/删除不重放 | 规则已有；任务账本/结果核对/恢复资格未验 | [09](issues/09-file-endpoints-and-recovery.md)、[11](issues/11-notifications-continuation.md)、[14](issues/14-background-and-recovery.md) |
| R39 | Q31 | 资源不足保护已有重要活动和当前操作，先降新/非焦点负载 | 资源不足sheet已有；预算、路由和降载反馈未验 | [12](issues/12-calls-and-audio-arbitration.md)、[16](issues/16-glass-and-performance-budget.md) |
| R40 | Q26 | 主控身份本机保管不自动迁移；元数据独立恢复，换机重新授权 | ADR及恢复元数据需重新授权稿已有；备份排除、signer与多路径仍未验 | [15](issues/15-identity-trust-and-transports.md) |
| R41 | 原始及重设计要求 | Apple/iOS Liquid Glass理念，官方网页研究；最新要求加强玻璃透色、亮边与控制层次 | Apple研究与静态材质已有；跨端库、动态视频/无障碍性能未验 | [16](issues/16-glass-and-performance-budget.md) |
| R42 | 最新明确纠正 | 黑色/中性色是主题色，默认浅色，深色可选；允许图标/小元素彩色，否定深绿按钮 | 当前主页面light；已加强玻璃及功能色、接听改浅薄荷；深色首页与降低透明度分别复核 | [18](issues/18-complete-design-state-coverage.md) |
| R43 | 图标要求 | Lucide优先，无适配才Iconify | 当前使用Lucide；最终包装/名称映射/许可和后备规则未验 | [19](issues/19-dependency-license-and-updates.md) |
| R44 | Google标准/NPM问题 | 遵循Google DESIGN.md，使用官方NPM校验 | 已运行lint：0错误26警告；不是动态/布局/Flutter验收，自动门禁尚未实施 | [16](issues/16-glass-and-performance-budget.md)、[19](issues/19-dependency-license-and-updates.md) |
| R45 | Pencil及CLI工具 | 用Pencil绘制，CLI可用时可按规则操作 | 已用CLI对象模型；需求审计只读，本轮视觉反馈通过对象模型修改，不以文本读写.pen | [18](issues/18-complete-design-state-coverage.md) |
| R46 | 最终排列要求 | 同一.pen每页独立，按类型分类、一类一行 | 当前77页/12组/组件板；按用户最终分类分行要求核对，不以Frame冒称已验证的独立工作区集合 | [18](issues/18-complete-design-state-coverage.md) |
| R47 | 目录整理要求 | 移除previews和designs根README；导出临时；源素材可保留 | 目录已符合，prod/README是另一层索引不在删除要求内 | [19](issues/19-dependency-license-and-updates.md) |
| R48 | prod目录要求 | 在ADR/技术文档与画布间解释产品，不讲库与代码路线 | prod已有；本轮补产品coverage与规则，工程任务留.scratch/docs | [18](issues/18-complete-design-state-coverage.md) |
| R49 | 最新移除/代理取舍 | 不做录屏/备份；自动回写、相机、硬件共享、开发面板等移出 | 画布已清理；本轮归档旧研究执行清单，手动取用/截图仍保留；截图来源/尺寸/保存分享需验 | [07](issues/07-fvp-media-pipeline.md)、[19](issues/19-dependency-license-and-updates.md) |
| R50 | 访谈/自主性要求 | grill-me/grill-with-docs形成研究与文档；事实代理查、常规不重复问 | 本轮用研究/审计取代重复功能问卷，未冻结未验方案 | [17](issues/17-manufacturer-mobile-flows.md)、[19](issues/19-dependency-license-and-updates.md) |
| R51 | 移动端最新纠正 | 远控沉浸全屏，像直接使用远端手机；悬浮退出可拖动并吸附侧边隐藏 | 整机/原应用接续/独立应用及重连、画质/声音、资源不足面板底层已全屏；工作台/会话列表改状态卡；退出展开、拖动、左右收起已有静态稿；手势隔离、旋转/键盘/无障碍与真实动态尚未验 | [08](issues/08-mobile-input-and-windows.md)、[18](issues/18-complete-design-state-coverage.md) |
| R52 | 最新Pencil要求 | 善用共享组件与实例，重复远控底层/控件/面板通过母组件统一更新 | 已建立全屏会话、退出状态、源画面、面板外壳/内容和系统控件复用；需持续验证状态覆盖与保存后引用 | [18](issues/18-complete-design-state-coverage.md) |

| R53 | 最新设备首屏纠正 | 固定设备列表，所有设备平等，不存在备用手机角色 | 列表已替代单设备首页；在线/离线/检查/需授权/空/搜索分别表达 | [05](issues/05-ordinary-user-onboarding.md)、[18](issues/18-complete-design-state-coverage.md) |
| R54 | 最新连接及查漏要求 | 完整连接表单、设备管理与关联流程，按类型优化当前页面 | 新增38页；12类77页，字段/权限/失败/恢复逐项追溯；未画与未验状态继续公开 | [05](issues/05-ordinary-user-onboarding.md)、[18](issues/18-complete-design-state-coverage.md) |

## 初始审计发现与后续处理

1. **画质细项只剩摘要。**当前 `FkCjb` 有三档预设、720p/60fps/8Mbps/H264摘要和“更多设置”，尚无四类详细选项的可评审状态。
2. **视频只有筛选入口。**`RqDYL` 具视频标签，但36页中无视频播放、拖动、格式不支持和取用失败状态。
3. **文件没有完整管理/恢复闭环。**`MaHXL` 是近期文件代表，缺目录、搜索结果、重命名/删除/新建反馈、任务详情、部分成功及恢复资格。
4. **轻量通知缺异常与认证。**不能定位、锁屏/应用认证、通知撤回、草稿保留和结果未知，尚未完整承接。不能由正常短信示意推导已实现免APK通知链。
5. **手机输入与多设备对象缺具体操作。**本机IME/遮挡/焦点、横屏、固定音源/混音、固定剪贴板与主动分享目标需要可观察状态。
6. **已有通话保护缺多呼叫模型。**需区分设备与具体通话/SIM、主控麦克风/耳机的所有权，新来电不抢占已有通话。
7. **后台与身份不能靠统一重连页。**系统回收、主动停止、换机只恢复元数据、撤销授权、不可恢复传输分别有不同下一步。
8. **“完整、全平台、低延迟”还缺交付判据。**完整ADB API账本、正式四端target/feature/SDK、基准设备/网络/并发/测量与阈值，仍需研究和真实产物。
9. **首次无感缺真实起点。**目前未从两台未授权手机跑通过程；扫码配对、旧系统USB转无线和用户拒绝后的恢复须单列。
10. **设备与跨网诊断职责需明确。**设备信息/最近状态、已有VPN/网关可达条件、无发现与不可达的区别仍需反馈；不以命令终端或自动穿透补齐。
11. **竞品研究仍有证据薄弱处。**OPPO/vivo国内手机操作细节及苹果相关参照需要补，不以宣传分类拼成已验证流程。

上述条目保留初始审计发现，不作为最新完成情况。全屏修订后曾为39页；本轮设备首屏与连接纠正再新增38页，当前77页。已补设备列表/管理/连接表单、文件目录/重命名/删除/部分失败、视频、通知异常、画质、多设备对象/来电和后台活动；手机IME/横屏、通知认证、文件新建/搜索/结果、保存分享失败、路由及系统停止仍有缺口。逐项最新状态以[产品流程覆盖表](../../designs/prod/coverage.md)为准。

## 事实复核与不能擅自改掉的要求

[补充研究](../../docs/research/requirements-gap-verification.md)再次核实官方版本与流程：

- scrcpy v5.0.1仍声明API21基础支持，Android10+是独立显示门槛，不能据此移除Android5+基础目标。
- Platform Tools37.0.1发布说明与通用ADB页面的mDNS后端描述有差异；Android17 Wi-Fi2需设备和主机共同支持，自有Rust主机须实现其行为。
- 首次配对/系统调试与信任不能在本约束下静默略过。优化目标是无需命令、步骤清楚、自动发现及已有信任时减少重复操作；旧系统首次无线有USB前置。
- Apple本地网络、Bonjour、自行multicast和后台资格要分别研究；手动LAN地址不绕过本地网络授权，编译不等于运行可用。

上述是文档/源码证据，不是真机通过。不要让用户重新证明这些事实，也不在无证据时自动接受原生密码依赖、额外被控APK或主控调试。

## 已修正的文档漂移

| 原问题 | 本轮处理 |
| --- | --- |
| 访谈仍称38页；厂商报告说录屏/备份/回写页待删，旧锚点失效 | 当时改为36页/九类及新页面/覆盖链接；最新计数见文末 |
| ADR0005把窗口关闭继续交回访谈 | 标明保留任务并迁回的代理默认与未验边界 |
| ADB/运行时旧报告只要求未来端静态接口 | 对齐Q32四端核心、FRB链接、整包实际编译，未来端运行仍单列 |
| 已答的音源/剪贴板/后台/身份等仍列为问卷 | 改为当前决定、研究前沿及任务引用 |
| 原生SMS写库、录屏、专用相机/通用mic仍在当前POC清单 | 标归档，当前执行转通知动作、已有视频播放和通话双向音频 |
| 通知历史措辞看起来仍是产品功能 | 词表改通用定义，研究标注后续范围替代，历史访谈保留并说明 |
| “38页/36页完成”容易被理解成全流程完成 | prod、spec及工具链均链接缺失状态覆盖表 |

历史资料中的未采用功能事实可保留，用于避免重复调查；它们不能进入现行执行清单。

## 执行与完成条件

入口为[20项任务](issues/README.md)。任务按依赖推进，不将依赖顺序改称“首版只做”。已定产品行为可以先补画；能力待证时必须保持条件状态，不因等研究而搁置所有设计。

- 研究完成：固定一手来源、区分直接事实/推论/未验，给具体下一步和产物，不只追加文章链接。
- 构建完成：对应宿主与正式target/feature下，核心、绑定最终链接、整包均有可复现证据。
- 功能完成：Android实际端到端及故障场景通过；需要真机的项不能用模拟器代替。
- 设计完成：每项覆盖需求有入口、操作、结果、失败/恢复和对应Frame/变体；源文件保持分类行和独立页面。
- 只有出现现有授权无法覆盖的实质取舍，才带证据向用户提问。普通默认、算法事实、常规失败路径继续由代理处理。


## 设备首屏修订的静态交付

2026-10-16：固定列表首屏、平等设备，完整梳理记录/连接/会话，新增38页并优化原连接和工作台；当前77页、12组、23母组件、470实例、148变量。对32条流程补充现有Frame、进入/退出和剩余项；R53/R54补入追溯。真实能力、四端构建、手机输入和上表剩余静态状态均不因此标完成。

## 2026-10-17实施期间追加要求

| ID | 用户要求 | 实施与验证要求 |
| --- | --- | --- |
| R55 | 一个页面一个文件，文件以page结尾 | 独立`*_page.dart`；可复用控件和helper另行归属，不能靠part合并页面 |
| R56 | 使用go_router | 明确业务路由、实体ID与错误处理；首页tab有路由身份，返回/替换/分享/远控退出完整回归 |
| R57 | 多文件夹架构，Dart文件不能全部放在同一层 | 用户最后明确采用lib/pages/<页面>/<页面>_page.dart；公共widgets/services/router在lib下，不增加features/core/app等深层分组 |

| R58 | 最新工程化纠正 | 实际使用go_router_builder、riverpod_generator、build_runner与官方lint；锁文件、生成一致性、状态/资源归属不能只装依赖 |
| R59 | 最新原生层纠正 | 共享业务放Rust/Dart，Android只保留系统授权/句柄/执行资格适配；成熟跨端媒体组件优先，不能为每平台各造播放器 |

## R60：首帧问题先查官方开发文档

用户要求首帧拿不到或慢时参考scrcpy开发者文档。已对照固定官方server静止补帧与媒体控制源码，并定位共享播放器起播前waitFor0阻塞；当前共享五codec/后台/旋转有实际证据。总启动与交互延迟、HEVC质量仍未通过，见[首帧研究](../../docs/research/scrcpy-first-frame-and-latency.md)和[重新核查A10](completion-reassessment.md)。

## 本轮当前入口整理（2026-10-17）

逐指令、逐需求及32流程标识继续沿用，不增加平行清单。当前权威摘要迁至[current-status](current-status.md)；新增A43–A48及精确证据见[重新核查第20节](completion-reassessment.md#20-本轮当前账本与新增断链2026-10-17)，已回填原01／03／08／09／14／18／19／20任务。当前89页静态源稿、已有系统保存／搜索／配对／通知／折射证据均与实现、动态和生产验收分开；目标仍active。
