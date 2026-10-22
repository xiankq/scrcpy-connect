# 设计调整的代码实施交接 · 2026-10-21

本文保留累计设计要求对应的编码入口与验收范围。相关代码已实施，远控五场矩阵、双MDK质量重建、通知完整链路及稳定玻璃运行核对已取得分层证据；完整产品UI／设备数据刷新、普通main最终冷启动与热重载、受控电量变化自动同步也已通过。具体结果及环境边界见[验证记录](validation.md)，下表是范围清单，不代表所有平台与运行组合已通过。

产品行为仍由[产品规格](../../designs/prod/README.md)负责，视觉数值由[视觉规范](../../designs/design.md)负责。本文记录本次交接范围，不另设一套长期规则。静态稿完成情况见[设计复核记录](design-refinement-2026-10-21.md)，页面与状态ID见[用户流程索引](../../designs/prod/user-flows.md)。

## 原始要求对应的编码范围

| 要求 | 实施范围与核验 | 当前实现入口 | 责任规格／设计状态 |
| --- | --- | --- | --- |
| 固定列表用圆角实体卡片包裹 | 全局核对设置、能力、选项等固定分组；组头位于卡片外，行有正常内距。动态列表保持逐项构建，不能把整组结果套进总卡片。同步明暗外观、长文字和窄屏布局 | `app/lib/widgets/grouped_list.dart`、`action_row.dart`、`packages/design_system/lib/`，以及各使用页面 | [列表与内容布局](../../designs/design.md#layout)；设备详情 `YLhiR`、画面设置 `XPceX` |
| 设备列表“更多”补连接动作 | 在线提供断开、离线提供开始连接，同时保留连接配置和移除；连接中避免重复提交，断开和移除各自核对活动影响 | `app/lib/pages/devices/index/widgets/device_card.dart`、`devices/widgets/device_access.dart` | [设备列表](../../designs/prod/device-connection.md#首屏与设备记录)；`PxnBS` |
| 发现页只保留发现内容，并补刷新与完整地址 | 移除顶栏加号／IP入口、空态的IP／配对码／USB等连接动作；右上保留刷新，覆盖发现中、无结果及失败状态。列表以名称、地址、信任状态三行排列，地址放在中间，显示各结果实际的 `IP:端口`，IPv6 为 `[地址]:端口`，不能只显示IP；区分配对与连接服务端口。选中结果返回原表单，带回已知方式和地址，不直接把发现当作授权 | `app/lib/pages/connection/discovery/connection_discovery_page.dart`、`app/lib/router/app_router.dart` | [添加与无线连接](../../designs/prod/device-connection.md#添加与无线连接)；`yMlVd`、`Fv2FI`、`facEi` |
| 添加设备可选全局或设备专属私钥 | 添加页四种连接形式共用私钥来源选择，自定义时原位展开PEM文本与文件选择；设备密钥随当前连接方式主动作校验、确认和提交，选文件不立即更换身份。保留全局密钥管理。此选择能力不带入已有设备连接配置模式 | `app/lib/pages/connection/form/connection_form_page.dart`、`settings/adb_identity/settings_adb_identity_page.dart`；核心身份存储入口 `crates/interop_core/src/host_identity.rs` | [授权密钥](../../designs/prod/device-connection.md#授权密钥)；添加页私钥选择／展开状态见[用户流程索引](../../designs/prod/user-flows.md) |
| 连接配置高度复用添加页，明确只读私钥差异 | 复用四方式Tab、当前方式内容及帮助；配置模式隐藏发现入口，并将已使用的私钥／私钥来源只读置灰展示，不开放来源切换、文本编辑、文件导入或更换身份。编辑原设备，预填可复用值，校验并确认影响后应用；取消保留原配置。不能因改地址、切换方式或重新授权新增设备记录；只读展示不要求将私钥秘密内容放入普通快照 | `app/lib/pages/devices/details/connection_preferences/devices_details_connection_preferences_page.dart`、`connection/form/connection_form_page.dart`、`connection/index/connection_index_page.dart`；`packages/interop_bridge/lib/src/connection_setup_coordinator.dart` | [设备连接配置](../../designs/prod/device-connection.md#设备连接配置)；`q3bM72`、`WSmhU`，只读字段状态以本轮源稿为准 |
| 添加四表单统一视觉与主动作 | 核对配对码、二维码、USB、IP四形式及其展开状态的标题、字段、帮助文案、文字颜色、主动作样式和主动作到帮助的间距；二维码“重新生成”采用与其他形式一致的全宽黑色圆角主按钮。共享组件按明暗外观取规范值，不在单个实例修补间距 | `app/lib/pages/connection/form/connection_form_page.dart`、共享表单与 `packages/design_system/lib/` | [添加与无线连接](../../designs/prod/device-connection.md#添加与无线连接)、[视觉规范](../../designs/design.md)；`W3GRn`、`G4CpTk`、`OxUaB`、`OpFKk` |
| 快捷操作改名、前置并放大图标 | 工作台“内容与通信”统一改名“快捷操作”，并与活跃应用交换顺序：快捷操作在上，活跃应用在下。快捷入口采用与活跃应用一致的外框尺寸，内部功能图形按视觉规范放大；窄屏／大字时换行，图标和标题共同可点击 | `app/lib/pages/devices/workspace/index/devices_workspace_index_page.dart`、`index/widgets/content_shortcuts.dart`、`running_apps.dart`，共享图标组件 | [设备工作台视觉规则](../../designs/design.md)；`nqQEb` |
| 列表图标扩展语义亮色 | 按视觉规范支持灰蓝、亮紫、蓝、亮绿、亮橙与珊瑚红，避免全部蓝色；全部彩色底功能图标统一白色图形，保留现有 `ListIconBadge` 白色前景；核对明暗外观下的实际辨识度。规范源与正式生成token已同步；组件颜色与使用处进入运行核对 | `packages/design_system/lib/src/list_icon_badge.dart`、`design_tokens.g.dart`、使用列表图标的页面；生成入口 `tool/design_tokens/generate.mjs` | [视觉规范](../../designs/design.md#colors)；`EPxks`、`aX7Ao`、`BBXRS`及相关实例 |
| 应用打开方式弹层精简 | 仅保留应用名称、独立窗口／手机屏幕两个动作及取消；删除常规设备／登录状态、任务交回、前台切换说明。两个动作间距12px，复用主／次按钮并适应窄屏；实际不可用或必要的现有任务迁移反馈按责任规格处理 | `app/lib/pages/devices/workspace/widgets/phone_app.dart` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；母组件 `yLJek`、代表状态 `tch6A` |
| 全部应用缩小图标并补留白 | 使用列表尺度的原始应用图标，落实行内距、项间距和最小行高；长名称不挤压图标，动态列表继续延迟构建 | `app/lib/pages/devices/workspace/apps/devices_workspace_apps_page.dart`、`workspace/widgets/phone_app.dart` | [列表视觉规则](../../designs/design.md)；`tbWkA` |
| 设备活动后台随APP进入启动并保持 | 默认开启的后台保持在进入APP时即启动；不等待画面连接，不因没有画面或关闭最后画面而停止。将应用级后台保障与画面、声音及被控屏幕唤醒／锁屏的生命周期分开；保留显式关闭偏好和系统明确停止处理。核对初始化与恢复过程不会被画面／音频路径反向启停。进入APP请求和原生服务拆分已实施，实际覆盖范围见验证记录 | `app/lib/main.dart`、`app/lib/services/app_controller.dart`、`packages/interop_bridge/lib/interop_bridge.dart`、`src/media/portable_audio.dart`及Android后台服务入口 | [后台与恢复](../../designs/prod/interaction-rules.md#后台与恢复)；`DtBNP` |
| 点亮／锁屏按画面窗口生命周期触发 | 每次新画面窗口启动均按“打开画面时点亮屏幕”开关尝试明确唤醒，即便同设备已有其他画面；独立应用同样计入。按设备统计活跃画面，主动关闭最后一个时按开关锁屏，关闭其他画面不触发。触发源必须是画面启动／关闭，绝非ADB连接成功／断开；遮挡、后台、重新附着和异常掉线不冒充新画面或主动关闭。保持唤醒仍按窗口存续管理首个获取／最后释放，不能据此把唤醒限制为0→1 | `packages/interop_bridge/lib/src/device_screen_coordinator.dart`、`app/lib/services/device_screen_policy.dart`、`devices/workspace/remote/devices_workspace_remote_page.dart`、`services/app_controller.dart` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；`YLhiR` |
| 远控关闭按钮改为可展开快捷控件 | 复用拖动跟手、松手吸边和收起把手，展开提供锁屏、截图、转独立窗口、键盘、旋转及关闭六项操作。按钮／拖动不向远端透传；关闭准确释放当前窗口，锁屏与截图归属当前设备／画面，转独立窗口需核对当前内容与能力并反馈真实结果，不能自动克隆或重放任务。核对边缘、安全区、横屏与覆盖面板后的可达性 | `app/lib/pages/devices/workspace/remote/widgets/exit_handle.dart`、`remote/devices_workspace_remote_page.dart`、`remote/remote_presentation.dart` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；整机 `DtZbX`、独立应用 `aVxBi`，快捷控件状态以本轮源稿为准 |
| 熄屏／锁定时就近提供直接亮屏 | 移除“手机处于休眠状态”模态提示及该状态的“重新检查”；只有检测到目标设备熄屏或锁定才自动在画面下部显示亮屏按钮，单击直接请求明确唤醒，不二次确认。亮屏不解锁；状态恢复后收起，迟到状态不能作用到另一设备或新窗口。未知状态不伪装成已熄屏；其他断线或结果未知的恢复流程按责任规格核对 | `app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart`、`remote/remote_presentation.dart`、`packages/interop_bridge/lib/src/device_screen_coordinator.dart` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；本轮熄屏／锁定代表状态 |
| 关闭即关闭，移除控制窗口管理页 | 移除管理页及入口、关闭后暂停／保留窗口／恢复入口；明确关闭时释放准确窗口的画面、输入和所属资源。当前画面工具直接归属仍打开的窗口 | `workspace/sessions/`生产页已删除；`workspace/remote/`、`app/lib/services/session_views.dart`、`app/lib/router/`；核心会话入口 `crates/interop_core/src/scrcpy.rs` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；`DtZbX`、`aVxBi`、工具面板 `XvviW` |
| 重整设备详情，画质统一更名画面设置 | 对照设备设置／连接能力／设备管理三组还原入口顺序；设备名称、连接配置、转为IP连接移入设备设置，设备管理只保留断开与移除；原“画质”的页名、入口、帮助及反馈统一更名“画面设置”，独立行显示当前摘要，所有设置／功能行带左图标。“远控屏幕比例”迁入该页，移除工作台等外部重复比例设置入口 | `app/lib/pages/devices/workspace/index/devices_workspace_index_page.dart`、`workspace/quality/devices_workspace_quality_page.dart`、`services/remote_display_settings.dart`，相关路由与文案 | [工作台、偏好与恢复](../../designs/prod/device-connection.md#工作台偏好与恢复)、[屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；`nqQEb`、`YLhiR`、`XPceX`、`Wp1CG`、`EWW1a` |
| 同设备所有画面共用画面质量偏好 | 统一设备级质量来源，对当前与后续整机／独立应用画面应用同一选择；清理窗口单独覆盖和质量“只对新窗口生效”的产品路径。应用、必要重建和失败反馈需同时处理。比例设置虽迁入同页，仍须按责任规格核对其独立生效范围，不能因改名误改比例生命周期 | `app/lib/pages/devices/workspace/quality/devices_workspace_quality_page.dart`、`packages/interop_bridge/lib/src/video_quality_policy.dart`、`virtual_display_policy.dart`、`crates/interop_core/src/scrcpy.rs`、`preferences.rs` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；`XPceX` |
| 工作台首卡重设计并补设备数据页 | 首卡缩小设备轮廓，以设备身份与连接状态组织信息，显示实时电量和充电状态，隐藏Android版本；离线／未知时不把旧电量当实时值。首卡摘要进入设备数据页，展示通过ADB取得且对用户有效的详细设备数据，包括Android版本；核对来源、可用性和缺失反馈，不把静态示例或不可读字段当成实时结果，不重复连接配置 | `app/lib/pages/devices/workspace/index/widgets/device_hero.dart`、`device_facts.dart`、`devices/widgets/device_identity.dart`、`devices/workspace/index/devices_workspace_index_page.dart`、`devices/details/data/devices_details_data_page.dart` | [工作台、偏好与恢复](../../designs/prod/device-connection.md#工作台偏好与恢复)、[设备工作台](../../designs/prod/information-architecture.md#设备工作台)；`nqQEb`、设备数据 `XPYvZ` |
| 转IP选择当前设备的实际地址 | 地址改为非自由输入的下拉选择，候选覆盖目标设备当前所有IP；先读取并显示可用候选，处理读取中、失败、无地址与地址变化，禁止选择其他设备或手写地址。保留端口、影响确认、目标身份验证和同一设备记录更新；提交前再次核对选中地址与目标归属 | `app/lib/pages/devices/details/convert_ip/devices_details_convert_ip_page.dart`、`devices/workspace/index/devices_workspace_index_page.dart`、`packages/interop_bridge/lib/src/connection_setup_coordinator.dart`，ADB接口IP枚举已有主机与API36读取证据，真实切换互操作仍待验 | [转为IP连接](../../designs/prod/device-connection.md#转为-ip-连接)；`XszXp`、`gHHmj` |
| 浅色底栏稳定选中玻璃加强可见性 | 调整母组件／token映射及使用处，使静止选中项在浅底与实际滚动内容上保持可辨；保留点击、拖动和归位光学反馈及降低透明度分支。需以生产后端实际成像核对，不能用Pencil静态高光证明运行效果 | `app/lib/router/navigation.dart`、`packages/design_system/lib/`及底部导航调用处，视觉数值由规范生成 | [视觉规范](../../designs/design.md)、[全局导航](../../designs/prod/information-architecture.md#手机平板与桌面)；共享底栏母组件及受影响浅色实例 |
| 设备详情及子页不重复连接配置入口 | 地址、端口与USB集中到专门配置页，设备私钥仅在该配置中只读展示；诊断只呈现结果与重新检查。转IP从工作台设备设置进入，不再塞入配置页。当前活动按设备归属，全局设置不重复提供入口 | `app/lib/pages/devices/details/`、`devices/workspace/index/`、`devices/workspace/activities/`、`settings/background/`、`app/lib/router/` | [设备工作台](../../designs/prod/information-architecture.md#设备工作台)、[设备连接配置](../../designs/prod/device-connection.md#设备连接配置)；`eWu3m`、`mDL3I`、`XszXp` |

表中缩写路径均相对已写出的共同父目录；它们是当前定位入口，未来可以按模块职责调整，不要求为每项要求新增页面或服务。

## 当前实施状态与边界

- 设备菜单、发现、四方式表单、专属身份与原记录配置事务已实施；主机回归通过，物理USB与扫码互操作仍须分别验证。
- 工作台首卡、快捷操作顺序、分组入口及只读设备数据已落地；API36真实数据读取、错误连接拒绝与离线不留旧动态值已有证据。持续电量有连接栅栏和过期屏障；完整product-06 UI／数据刷新与普通main最终冷启动、热重载均通过；目标受控电量100%充电→37%不充电→恢复100%充电时首卡自动同步，已确认reset。
- 远控已改展开快捷控件、直接亮屏、每新窗唤醒和最后关闭锁屏；旧管理页删除，旧地址重定向工作台。API36双AVD的settings、workspace、recovery、IME及input五场整场通过，覆盖48个设置检查点、4个唯一窗口、同一真实任务接续及关闭后保留、同session恢复与关闭后不复活、中文／emoji精确一次，以及真实HOME时输入释放。该输入法证据来自Flutter编辑值到实际Android输入框，不包含Gboard候选界面。
- 默认应用级后台在进入APP时启动，连接与音频FGS独立，系统停止不会被自动请求或首个恢复快照撤销。API36正常APP和隔离集成场景已取得运行证据。
- 画面设置已更名并收纳比例；质量重建及独立密度修复已通过API36实际复验。暂停手机画面与播放中的Settings双MDK同时从720升至1280，取得新capture／renderer代际与 `mdk.snapshot` 解码证据，保持逻辑窗口、task79及暂停意图，随后新窗口继承设置，清理无错误。暂停重建等待首帧超时已修复，验证capture取得首帧后仍维持paused，而非移除暂停断言。
- 稳定底栏采用公开三层玻璃组合，8种状态的实际捕获与断言通过；宿主是Mesa llvmpipe软件渲染，不代表物理GPU、普通main连续手感、多视频负载或读屏验收。
- 工程检查通过：app406项、设计系统23项、bridge190项；Rust全量404通过／85显式忽略，后续相关scrcpy回归52通过／3显式忽略；分析无问题，正式生成一致性检查通过。忽略项不计通过；架构与导航已同步，其他宿主、物理USB／Wi-Fi及OEM互操作仍按实际证据声明。

关闭互联窗口后，手机真实应用任务按[ADR 0005](../adr/0005-real-application-tasks-in-linked-windows.md)保留交回手机，不能以删除管理页为由强停应用。

## 复查补充的实现核对项

- 远控顶部额外安全区已由可失败Widget回归定位并去除：400×800视口/inset32原画面Rect(8,32,392,800)，修后Rect(0,0,400,800)。浮动工具自行避让安全区，纹理仍按源比例完整容纳。此证据不代替目标系统栏、横屏和输入的设备验收，不拉伸或裁切源画面补黑。入口为 `app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart` 及主控平台系统栏配置。
- 独立窗口内容过小已在API36 Settings样本定位为虚拟显示逻辑密度与实体显示不一致：实体宽约411dp，旧独立显示宽720dp，先取得失败证据；修复后720px／280dpi对应约411dp，不再以Flutter整幅缩放补偿远端布局。1280质量设置重建及不同分辨率复验保留真实task，实际resize→quality→resize与旧capture拒绝通过。入口为 `packages/interop_bridge/lib/src/virtual_display_policy.dart`、`video_quality_policy.dart`、`crates/interop_core/src/scrcpy.rs` 及命令契约；该结论与修复证据限于已测目标，其他应用／OEM仍需对照实际dp／density。
- 大屏保留全局侧栏和单一当前内容区，正文、浮动标题使用同一阅读列；对照 `H0TFx`、`zLBrM`，入口为 `app/lib/widgets/page_frame.dart`。
- 文件、目录选择、相册、通知接续、全部应用和诊断持续显示目标设备；文件和接续操作提交时仍核验原对象。对应入口位于 `app/lib/pages/devices/workspace/` 及 `devices/details/diagnostics/`。
- 同名搜索结果显示目录；同名冲突显示文件名、来源、目标与替换影响。对照 `jcZXq`、`zD1BI`、`K950NO`，核对文件搜索页和 `app/lib/pages/transfers/`。
- 发现失败、权限拒绝和配对码失效分别呈现原因及就近恢复动作；配对端口与日常连接端口不得混用。
- 媒体暂存的预算、实际字节和清理后数值来自服务状态，沿用[媒体暂存规则](../../designs/prod/content-and-transfer.md#媒体暂存与空间准入)，不照抄设计示例数据；入口为 `settings/media_cache/`、`crates/interop_core/src/media_cache.rs`。
- 共享表单、卡片和输入框继承页面外观，展开后跟随可用宽度；不要在复用组件或实例中固定浅色主题。

新增代表状态的具体ID沿用[用户流程索引](../../designs/prod/user-flows.md)及本轮[设计复核记录](design-refinement-2026-10-21.md)，实施时同步查阅最终源稿；本文不把尚未定位的状态编号写成已完成证据。

## 实时通知不一致排查

用户原始现象：“实时通知的数据跟目标设备上的真实通知不一致。”已在API36隔离目标的真实原生通知复现：BigText展开标题被采成折叠标题，Inbox通知已存在的多条正文被采成空。采集层现按原通知的展开标题、大文本和文本行取值，普通／MessagingStyle保留系统预览。真实probe先失败后通过，核对Android服务实际通知，并覆盖更新、旧动作引用失效、移除和观察重新附着；源码、JAR、manifest及共享资源已同步。

`notifications-02` 完整Flutter链路已通过：真实Binder创建、更新和撤回先驱动实际UI，再调用list交叉核对，目标系统来源独立一致；原应用名称／图标与打开、锁屏不绕过、单条／全部清除、前台系统提醒及目标撤回后的提醒撤回均通过，主控错误为空，临时PIN、通知与APK清理确认。证据入口含 `servers/companion/tests/notification-snapshot.dart`，环境和分层结果见[验证记录](validation.md)。这证明所测API36原生样式及其实际链路的具体缺陷已修复，不外推第三方消息服务、其他OEM或未测重连组合。

## 验收对照与剩余范围

以下保留逐项对照范围；已通过的API36矩阵与媒体、通知、玻璃结果以上文及[验证记录](validation.md)为准，不再将这些已测场景统一标为待验。完整product-06 UI／设备数据刷新、普通main最终冷启动／热重载及受控电量变化自动同步已通过；物理设备与其他平台的缺口分别保留。

- 视觉与入口：逐页检查相关页面和菜单，覆盖明暗外观、窄屏、大字、长设备名、滚动末项及大屏侧栏；工作台显示“快捷操作”，且位于活跃应用上方。按实际变更采集截图，不用源稿结构扫描代替运行渲染。
- 连接与身份：添加的四种形式均可选全局／专属私钥，已有设备配置均只读置灰且无法切换／编辑／导入；两模式的其余复用行为与取消、晚回执分别核验。配置成功后仍是同一设备，取消和失败不错误覆盖记录或降级连接。四表单、展开态、二维码重新生成主按钮及帮助间距逐一检查。
- 发现与转IP：发现页右上刷新在结果、无结果和失败状态可用，列表显示准确端口与IPv6括号；返回带回正确服务地址。转IP只允许选择目标设备当前IP，覆盖多地址、无地址、读取失败及提交前地址变化；身份不符、取消和失败不错误更新原记录。
- 设备活动后台：冷启动进入APP但不打开任何画面时已启动；打开／关闭一个或多个画面均不造成该后台服务启停，关闭最后画面后仍保持。核对前后台切换、重新进入、显式关闭偏好及系统停止的真实结果；声音停止与被控手机锁屏不能顺带停掉应用级设备活动后台。
- 画面生命周期：每次新建整机或独立应用画面均按开关唤醒，特别覆盖已有同设备窗口时再开一个；主动关闭末个活跃画面按开关锁屏，中途关闭一个不锁屏。ADB连接／重连、遮挡、重新附着和临时后台不触发，多设备互不影响，旧回执不能操作新窗口。保持唤醒的首个获取／末个释放单独核验。
- 远控快捷与亮屏：收起、展开、拖动、吸边和全部快捷动作分别运行验证，触控不泄漏到远端；锁屏后下部自动出现亮屏按钮，单击直接执行且没有二次确认，普通亮屏状态不显示，未知状态不误报。覆盖设备锁定、熄屏、状态恢复、横屏、安全区和覆盖面板。
- 关闭与资源：关闭后窗口及输入确实结束，不能从管理页恢复；其他设备、传输、连接和手机真实任务遵循各自规则。临时遮挡／重建不误当成关闭，已经关闭的窗口不被恢复流程复活。
- 画面设置：统一检查新页名、入口与反馈，外部不再出现独立比例设置行；比例选项与自定义值在该页完整可用。质量变更使同设备多个已打开画面和随后打开的画面均采用新值，其他设备不变；必要重建保留正确任务与窗口归属，部分失败说明实际结果，不假报全部成功。
- 设备数据与首卡：在目标设备运行核对电量和充电状态变化、离线与读取失败，首卡不显示Android版本；详情页显示有来源且有效的ADB数据与实际版本。私密字段、缺失值与旧结果不冒充有效实时数据。
- 成像与尺寸：API36两端像素对照已确认自动无导航与横屏无额外顶部安全区黑边，保留源比例和实际输入；独立显示dp／density修复及稳定玻璃各状态已有上述运行证据。继续验证其他系统栏／物理GPU与未测设备，普通main的连续手感与性能尚不能由独立玻璃夹具外推，Pencil状态不提供设备通过结论。
- 路由与迁移：移除旧页生产入口，处理既有地址恢复；更新路由／协议／设置来源后生成对应产物，按[工具链契约](repository-tooling.md)执行适用检查。真实屏幕、授权和媒体结果另做设备验证。

## 仅属于设计源稿的事项

一个完整页面一个顶层画布、每块规范／组件／局部状态底板独立成画布、全部留在同一 `mobile.pen`，属于设计文件组织，不要求新增应用路由、页面或文件。设计规范、组件板和局部状态板同样不一一映射为产品页面。所有大画布载体统一浅灰展示底，属于设计文件呈现，不要求改变APP页面或组件内容配色。
