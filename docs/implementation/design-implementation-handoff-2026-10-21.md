# 设计调整的代码实施交接 · 2026-10-21

本文将本轮设计要求映射到后续编码入口与验收事项，供人工实施使用。本轮只修改设计稿和文档，没有执行下列代码改动。清单状态统一为“待实现对照与运行验收”；部分能力已有代码基础，不代表全部需要重写。

产品行为仍由[产品规格](../../designs/prod/README.md)负责，视觉数值由[视觉规范](../../designs/design.md)负责。本文记录本次交接范围，不另设一套长期规则。静态稿完成情况见[设计复核记录](design-refinement-2026-10-21.md)，页面与状态ID见[用户流程索引](../../designs/prod/user-flows.md)。

## 原始要求对应的编码范围

| 要求 | 后续代码工作与核验 | 当前实现入口 | 责任规格／设计状态 |
| --- | --- | --- | --- |
| 固定列表用圆角实体卡片包裹 | 全局核对设置、能力、选项等固定分组；组头位于卡片外，行有正常内距。动态列表保持逐项构建，不能把整组结果套进总卡片。同步明暗外观、长文字和窄屏布局 | `app/lib/widgets/grouped_list.dart`、`action_row.dart`、`packages/design_system/lib/`，以及各使用页面 | [列表与内容布局](../../designs/design.md#layout)；设备详情 `YLhiR`、画面设置 `XPceX` |
| 设备列表“更多”补连接动作 | 在线提供断开、离线提供开始连接，同时保留连接配置和移除；连接中避免重复提交，断开和移除各自核对活动影响 | `app/lib/pages/devices/index/widgets/device_card.dart`、`devices/widgets/device_access.dart` | [设备列表](../../designs/prod/device-connection.md#首屏与设备记录)；`PxnBS` |
| 发现页只保留发现内容，并补刷新与完整地址 | 移除顶栏加号／IP入口、空态的IP／配对码／USB等连接动作；右上保留刷新，覆盖发现中、无结果及失败状态。列表以名称、地址、信任状态三行排列，地址放在中间，显示各结果实际的 `IP:端口`，IPv6 为 `[地址]:端口`，不能只显示IP；区分配对与连接服务端口。选中结果返回原表单，带回已知方式和地址，不直接把发现当作授权 | `app/lib/pages/connection/discovery/connection_discovery_page.dart`、`app/lib/router/app_router.dart` | [添加与无线连接](../../designs/prod/device-connection.md#添加与无线连接)；`yMlVd`、`Fv2FI`、`facEi` |
| 添加设备可选全局或设备专属私钥 | 添加页四种连接形式共用私钥来源选择，自定义时原位展开PEM文本与文件选择；设备密钥随当前连接方式主动作校验、确认和提交，选文件不立即更换身份。保留全局密钥管理。此选择能力不带入已有设备连接配置模式 | `app/lib/pages/connection/form/connection_form_page.dart`、`settings/adb_identity/settings_adb_identity_page.dart`；核心身份存储入口 `crates/interop_core/src/host_identity.rs` | [授权密钥](../../designs/prod/device-connection.md#授权密钥)；添加页私钥选择／展开状态见[用户流程索引](../../designs/prod/user-flows.md) |
| 连接配置高度复用添加页，明确只读私钥差异 | 复用四方式Tab、当前方式内容及帮助；配置模式隐藏发现入口，并将已使用的私钥／私钥来源只读置灰展示，不开放来源切换、文本编辑、文件导入或更换身份。编辑原设备，预填可复用值，校验并确认影响后应用；取消保留原配置。不能因改地址、切换方式或重新授权新增设备记录；只读展示不要求将私钥秘密内容放入普通快照 | `app/lib/pages/devices/details/connection_preferences/devices_details_connection_preferences_page.dart`、`connection/form/connection_form_page.dart`、`connection/index/connection_index_page.dart`；`packages/interop_bridge/lib/src/connection_setup_coordinator.dart` | [设备连接配置](../../designs/prod/device-connection.md#设备连接配置)；`q3bM72`、`WSmhU`，只读字段状态以本轮源稿为准 |
| 添加四表单统一视觉与主动作 | 核对配对码、二维码、USB、IP四形式及其展开状态的标题、字段、帮助文案、文字颜色、主动作样式和主动作到帮助的间距；二维码“重新生成”采用与其他形式一致的全宽黑色圆角主按钮。共享组件按明暗外观取规范值，不在单个实例修补间距 | `app/lib/pages/connection/form/connection_form_page.dart`、共享表单与 `packages/design_system/lib/` | [添加与无线连接](../../designs/prod/device-connection.md#添加与无线连接)、[视觉规范](../../designs/design.md)；`W3GRn`、`G4CpTk`、`OxUaB`、`OpFKk` |
| 快捷操作改名、前置并放大图标 | 工作台“内容与通信”统一改名“快捷操作”，并与活跃应用交换顺序：快捷操作在上，活跃应用在下。快捷入口采用与活跃应用一致的外框尺寸，内部功能图形按视觉规范放大；窄屏／大字时换行，图标和标题共同可点击 | `app/lib/pages/devices/workspace/index/devices_workspace_index_page.dart`、`index/widgets/content_shortcuts.dart`、`running_apps.dart`，共享图标组件 | [设备工作台视觉规则](../../designs/design.md)；`nqQEb` |
| 列表图标扩展语义亮色 | 按视觉规范支持灰蓝、亮紫、蓝、亮绿、亮橙与珊瑚红，避免全部蓝色；全部彩色底功能图标统一白色图形，保留现有 `ListIconBadge` 白色前景；核对明暗外观下的实际辨识度。规范源已更新，生成token与组件代码留待人工编码；只读漂移检查预期报告未同步，不执行生成 | `packages/design_system/lib/src/list_icon_badge.dart`、`design_tokens.g.dart`、使用列表图标的页面；生成入口 `tool/design_tokens/generate.mjs` | [视觉规范](../../designs/design.md#colors)；`EPxks`、`aX7Ao`、`BBXRS`及相关实例 |
| 应用打开方式弹层精简 | 仅保留应用名称、独立窗口／手机屏幕两个动作及取消；删除常规设备／登录状态、任务交回、前台切换说明。两个动作间距12px，复用主／次按钮并适应窄屏；实际不可用或必要的现有任务迁移反馈按责任规格处理 | `app/lib/pages/devices/workspace/widgets/phone_app.dart`；本轮只登记，不修改代码 | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；母组件 `yLJek`、代表状态 `tch6A` |
| 全部应用缩小图标并补留白 | 使用列表尺度的原始应用图标，落实行内距、项间距和最小行高；长名称不挤压图标，动态列表继续延迟构建 | `app/lib/pages/devices/workspace/apps/devices_workspace_apps_page.dart`、`workspace/widgets/phone_app.dart` | [列表视觉规则](../../designs/design.md)；`tbWkA` |
| 设备活动后台随APP进入启动并保持 | 默认开启的后台保持在进入APP时即启动；不等待画面连接，不因没有画面或关闭最后画面而停止。将应用级后台保障与画面、声音及被控屏幕唤醒／锁屏的生命周期分开；保留显式关闭偏好和系统明确停止处理。核对初始化与恢复过程不会被画面／音频路径反向启停。本轮仅记录，当前具体触发链及平台行为待后续排查、实施和运行验收 | `app/lib/main.dart`、`app/lib/services/app_controller.dart`、`packages/interop_bridge/lib/interop_bridge.dart`、`src/media/portable_audio.dart`及Android后台服务入口 | [后台与恢复](../../designs/prod/interaction-rules.md#后台与恢复)；`DtBNP` |
| 点亮／锁屏按画面窗口生命周期触发 | 每次新画面窗口启动均按“打开画面时点亮屏幕”开关尝试明确唤醒，即便同设备已有其他画面；独立应用同样计入。按设备统计活跃画面，主动关闭最后一个时按开关锁屏，关闭其他画面不触发。触发源必须是画面启动／关闭，绝非ADB连接成功／断开；遮挡、后台、重新附着和异常掉线不冒充新画面或主动关闭。保持唤醒仍按窗口存续管理首个获取／最后释放，不能据此把唤醒限制为0→1 | `packages/interop_bridge/lib/src/device_screen_coordinator.dart`、`app/lib/services/device_screen_policy.dart`、`devices/workspace/remote/devices_workspace_remote_page.dart`、`services/app_controller.dart` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；`YLhiR` |
| 远控关闭按钮改为可展开快捷控件 | 复用拖动跟手、松手吸边和收起把手，展开提供锁屏、截图、转独立窗口、键盘、旋转及关闭六项操作。按钮／拖动不向远端透传；关闭准确释放当前窗口，锁屏与截图归属当前设备／画面，转独立窗口需核对当前内容与能力并反馈真实结果，不能自动克隆或重放任务。核对边缘、安全区、横屏与覆盖面板后的可达性 | `app/lib/pages/devices/workspace/remote/widgets/exit_handle.dart`、`remote/devices_workspace_remote_page.dart`、`remote/remote_presentation.dart` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；整机 `DtZbX`、独立应用 `aVxBi`，快捷控件状态以本轮源稿为准 |
| 熄屏／锁定时就近提供直接亮屏 | 移除“手机处于休眠状态”模态提示及该状态的“重新检查”；只有检测到目标设备熄屏或锁定才自动在画面下部显示亮屏按钮，单击直接请求明确唤醒，不二次确认。亮屏不解锁；状态恢复后收起，迟到状态不能作用到另一设备或新窗口。未知状态不伪装成已熄屏；其他断线或结果未知的恢复流程按责任规格核对 | `app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart`、`remote/remote_presentation.dart`、`packages/interop_bridge/lib/src/device_screen_coordinator.dart` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；本轮熄屏／锁定代表状态 |
| 关闭即关闭，移除控制窗口管理页 | 移除管理页及入口、关闭后暂停／保留窗口／恢复入口；明确关闭时释放准确窗口的画面、输入和所属资源。当前画面工具直接归属仍打开的窗口 | `app/lib/pages/devices/workspace/sessions/`、`workspace/remote/`、`app/lib/services/session_views.dart`、`app/lib/router/`；核心会话入口 `crates/interop_core/src/scrcpy.rs` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；`DtZbX`、`aVxBi`、工具面板 `XvviW` |
| 重整设备详情，画质统一更名画面设置 | 对照设备设置／连接能力／设备管理三组还原入口顺序；设备名称、连接配置、转为IP连接移入设备设置，设备管理只保留断开与移除；原“画质”的页名、入口、帮助及反馈统一更名“画面设置”，独立行显示当前摘要，所有设置／功能行带左图标。“远控屏幕比例”迁入该页，移除工作台等外部重复比例设置入口 | `app/lib/pages/devices/workspace/index/devices_workspace_index_page.dart`、`workspace/quality/devices_workspace_quality_page.dart`、`services/remote_display_settings.dart`，相关路由与文案 | [工作台、偏好与恢复](../../designs/prod/device-connection.md#工作台偏好与恢复)、[屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；`nqQEb`、`YLhiR`、`XPceX`、`Wp1CG`、`EWW1a` |
| 同设备所有画面共用画面质量偏好 | 统一设备级质量来源，对当前与后续整机／独立应用画面应用同一选择；清理窗口单独覆盖和质量“只对新窗口生效”的产品路径。应用、必要重建和失败反馈需同时处理。比例设置虽迁入同页，仍须按责任规格核对其独立生效范围，不能因改名误改比例生命周期 | `app/lib/pages/devices/workspace/quality/devices_workspace_quality_page.dart`、`packages/interop_bridge/lib/src/video_quality_policy.dart`、`virtual_display_policy.dart`、`crates/interop_core/src/scrcpy.rs`、`preferences.rs` | [屏幕、窗口与输入](../../designs/prod/interaction-rules.md#屏幕窗口与输入)；`XPceX` |
| 工作台首卡重设计并补设备数据页 | 首卡缩小设备轮廓，以设备身份与连接状态组织信息，显示实时电量和充电状态，隐藏Android版本；离线／未知时不把旧电量当实时值。首卡摘要进入设备数据页，展示通过ADB取得且对用户有效的详细设备数据，包括Android版本；核对来源、可用性和缺失反馈，不把静态示例或不可读字段当成实时结果，不重复连接配置 | `app/lib/pages/devices/workspace/index/widgets/device_hero.dart`、`device_facts.dart`、`devices/widgets/device_identity.dart`、`devices/workspace/index/devices_workspace_index_page.dart`，设备信息查询与路由入口待实现定位 | [工作台、偏好与恢复](../../designs/prod/device-connection.md#工作台偏好与恢复)、[设备工作台](../../designs/prod/information-architecture.md#设备工作台)；`nqQEb`、设备数据 `XPYvZ` |
| 转IP选择当前设备的实际地址 | 地址改为非自由输入的下拉选择，候选覆盖目标设备当前所有IP；先读取并显示可用候选，处理读取中、失败、无地址与地址变化，禁止选择其他设备或手写地址。保留端口、影响确认、目标身份验证和同一设备记录更新；提交前再次核对选中地址与目标归属 | `app/lib/pages/devices/details/convert_ip/devices_details_convert_ip_page.dart`、`devices/workspace/index/devices_workspace_index_page.dart`、`packages/interop_bridge/lib/src/connection_setup_coordinator.dart`，ADB接口IP枚举待实现 | [转为IP连接](../../designs/prod/device-connection.md#转为-ip-连接)；`XszXp`、`gHHmj` |
| 浅色底栏稳定选中玻璃加强可见性 | 调整母组件／token映射及使用处，使静止选中项在浅底与实际滚动内容上保持可辨；保留点击、拖动和归位光学反馈及降低透明度分支。需以生产后端实际成像核对，不能用Pencil静态高光证明运行效果 | `app/lib/router/navigation.dart`、`packages/design_system/lib/`及底部导航调用处，视觉数值由规范生成 | [视觉规范](../../designs/design.md)、[全局导航](../../designs/prod/information-architecture.md#手机平板与桌面)；共享底栏母组件及受影响浅色实例 |
| 设备详情及子页不重复连接配置入口 | 地址、端口与USB集中到专门配置页，设备私钥仅在该配置中只读展示；诊断只呈现结果与重新检查。转IP从工作台设备设置进入，不再塞入配置页。当前活动按设备归属，全局设置不重复提供入口 | `app/lib/pages/devices/details/`、`devices/workspace/index/`、`devices/workspace/activities/`、`settings/background/`、`app/lib/router/` | [设备工作台](../../designs/prod/information-architecture.md#设备工作台)、[设备连接配置](../../designs/prod/device-connection.md#设备连接配置)；`eWu3m`、`mDL3I`、`XszXp` |

表中缩写路径均相对已写出的共同父目录；它们是当前定位入口，未来可以按模块职责调整，不要求为每项要求新增页面或服务。

## 已定位的现状差异

以下为本次只读检查所得，实施时以当时源码再次确认：

- `device_card.dart` 的菜单当前只有“移除此设备”；发现页仍有顶栏与空态IP操作。
- `DeviceConnectionPreferencesPage` 仍是“编辑地址与端口／使用USB／ADB私钥／转为IP”的入口列表，需要替换成共享表单的配置模式。
- `host_identity.rs` 已提供 `scope`／`fingerprint` 公开投影，可作为已有设备配置的只读来源；本轮收口的是已有设备的选择、PEM导入与恢复继承入口，不更改全局密钥管理已有的全局导入／重置能力，也不据此声称ADB协议无法更换密钥。
- 转IP页当前使用自由输入地址；发现数据中的 mDNS `endpoints` 是服务发现结果，不能代替目标设备完整接口IP枚举。后续需补目标设备当前IP的读取与候选更新，再绑定非自由输入的选择字段。
- `device_metadata.rs` 当前只从 `dumpsys battery` 提取百分比，`device.rs` 在连接后排队查询；尚不足以证明充电状态、周期更新与数据新鲜度已实现。实时首卡和详情页需补实际字段与刷新来源，并延续连接身份核验，丢弃旧连接迟到结果。
- `DeviceScreenCoordinator` 当前观察连接标识并读取 `wakeOnConnect`；`DeviceScreenPolicy` 当前仅统计手机整机页面。迁移时需同时处理每次新画面启动的唤醒触发、整机与独立应用统一统计、末个活跃画面关闭时锁屏、持久化字段和旧值兼容，不能只改开关文字，也不能仍沿用首个窗口才唤醒的逻辑。
- 远控页普通退出路径仍释放呈现并请求暂停；会话管理页与路由仍存在。需要梳理关闭、页面重建、临时遮挡和异常断线各自的资源收尾，保留准确的会话代际核验。
- 远控页 `device_asleep` 目前进入居中恢复面板，带“唤醒手机”和“重新检查”；需改为检测到熄屏／锁定时在下部显示单击直接亮屏按钮，避免把一般错误恢复与亮屏条件混在同一面板。
- `device.rs` 的 `device_sleeping` 是内部电源状态探测，不能直接等同于可靠的锁定状态；既有 Companion 的局部 Keyguard 用途也不证明通用锁定状态已向远控投影。后续需核对探测来源、OEM未知结果、刷新和目标归属，再驱动条件按钮。
- 核心 `session.quality` 当前返回 `appliesNextSession`，原画质页保留“已保留的窗口需关闭后重新打开”反馈；设备级存储虽已存在，仍需完成对所有当前画面的质量应用。工作台另有“远控屏幕比例”入口，需要迁入更名后的画面设置页。
- [当前架构说明](architecture.md)和[导航说明](flutter-navigation.md)仍记录上述代码现状。完成相应实现后再同步其所有权、路由和生命周期正文，不能把本次静态设计记录当作实现完成证明。

关闭互联窗口后，手机真实应用任务仍按[ADR 0005](../adr/0005-real-application-tasks-in-linked-windows.md)处理。删除窗口管理与关闭后暂停概念，不等于强制停止手机应用；临时遮挡或断线仍可暂停尚未关闭窗口的呈现。

## 复查补充的实现核对项

- 远控内容需要延伸到主控状态栏原本占用的区域，当前顶部黑区问题留待编码修复。只读定位发现远控页设置 `immersiveSticky`，黑底 `Scaffold` 的正文仍包裹默认 `SafeArea`，纹理通过 `AspectRatio` 完整容纳；若宿主顶部inset仍非零，可留下黑区，这是候选原因而非唯一根因。检查系统栏隐藏／透明配置、宿主视口与播放器布局，区分主控额外留白和源画面自身黑边；不以拉伸或裁切远端内容补满黑区。入口为 `app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart` 及主控平台系统栏配置。
- 独立窗口中应用内容比手机屏幕内明显缩小的问题需要诊断：`virtual_display_policy.dart` 默认1080×1920并按 `maxSize` 等比约束；`scrcpy.rs` 创建 `new_display` 与动态 `session.display` 当前传宽高，协议未暴露density参数。密度／分辨率及其与虚拟显示尺寸的组合只是候选因素，不能在未取证前断言根因，更不能先用Flutter整幅缩放替代远端布局修复。对照同一应用、同一设备的实体显示与独立显示，记录实际尺寸、dp／density、编码尺寸、布局和输入坐标；核对 `packages/interop_bridge/lib/src/virtual_display_policy.dart`、`video_quality_policy.dart`、`crates/interop_core/src/scrcpy.rs` 及命令契约。后续结论必须带设备与运行证据，静态稿只交接期望视觉。
- 大屏保留全局侧栏和单一当前内容区，正文、浮动标题使用同一阅读列；对照 `H0TFx`、`zLBrM`，入口为 `app/lib/widgets/page_frame.dart`。
- 文件、目录选择、相册、通知回复、全部应用和诊断持续显示目标设备；回复和文件操作提交时仍核验原对象。对应入口位于 `app/lib/pages/devices/workspace/` 及 `devices/details/diagnostics/`。
- 同名搜索结果显示目录；同名冲突显示文件名、来源、目标与替换影响。对照 `jcZXq`、`zD1BI`、`K950NO`，核对文件搜索页和 `app/lib/pages/transfers/`。
- 发现失败、权限拒绝和配对码失效分别呈现原因及就近恢复动作；配对端口与日常连接端口不得混用。
- 媒体暂存的预算、实际字节和清理后数值来自服务状态，沿用[媒体暂存规则](../../designs/prod/content-and-transfer.md#媒体暂存与空间准入)，不照抄设计示例数据；入口为 `settings/media_cache/`、`crates/interop_core/src/media_cache.rs`。
- 共享表单、卡片和输入框继承页面外观，展开后跟随可用宽度；不要在复用组件或实例中固定浅色主题。

新增代表状态的具体ID沿用[用户流程索引](../../designs/prod/user-flows.md)及本轮[设计复核记录](design-refinement-2026-10-21.md)，实施时同步查阅最终源稿；本文不把尚未定位的状态编号写成已完成证据。

## 实时通知数据不一致的待排查记录

用户原始现象：“实时通知的数据跟目标设备上的真实通知不一致。”本次仅登记排查事项；复现环境、通知样本、具体差异、根因及修复状态均未知，未运行诊断或修改代码，不据此断言某一数据来源或流程存在缺陷。

后续需记录主控与目标设备环境、同一时刻的真实通知样本及主控显示，对照应用身份、标题、正文、时间与其他实际差异字段；分别核对通知增加、更新和删除、设备归属、初始快照与增量事件的时序，以及断线重连后的恢复与迟到事件。排查结果须区分实际采集数据、状态合并和界面呈现，保留可复核证据。验收需逐条对照目标设备真实通知，覆盖更新、删除及重连恢复，不能只以静态稿或模拟数据证明一致；产品规则仍见[通知与通信](../../designs/prod/interaction-rules.md#通知与通信)。

## 编码后的验收重点

- 视觉与入口：逐页检查相关页面和菜单，覆盖明暗外观、窄屏、大字、长设备名、滚动末项及大屏侧栏；工作台显示“快捷操作”，且位于活跃应用上方。按实际变更采集截图，不用源稿结构扫描代替运行渲染。
- 连接与身份：添加的四种形式均可选全局／专属私钥，已有设备配置均只读置灰且无法切换／编辑／导入；两模式的其余复用行为与取消、晚回执分别核验。配置成功后仍是同一设备，取消和失败不错误覆盖记录或降级连接。四表单、展开态、二维码重新生成主按钮及帮助间距逐一检查。
- 发现与转IP：发现页右上刷新在结果、无结果和失败状态可用，列表显示准确端口与IPv6括号；返回带回正确服务地址。转IP只允许选择目标设备当前IP，覆盖多地址、无地址、读取失败及提交前地址变化；身份不符、取消和失败不错误更新原记录。
- 设备活动后台：冷启动进入APP但不打开任何画面时已启动；打开／关闭一个或多个画面均不造成该后台服务启停，关闭最后画面后仍保持。核对前后台切换、重新进入、显式关闭偏好及系统停止的真实结果；声音停止与被控手机锁屏不能顺带停掉应用级设备活动后台。
- 画面生命周期：每次新建整机或独立应用画面均按开关唤醒，特别覆盖已有同设备窗口时再开一个；主动关闭末个活跃画面按开关锁屏，中途关闭一个不锁屏。ADB连接／重连、遮挡、重新附着和临时后台不触发，多设备互不影响，旧回执不能操作新窗口。保持唤醒的首个获取／末个释放单独核验。
- 远控快捷与亮屏：收起、展开、拖动、吸边和全部快捷动作分别运行验证，触控不泄漏到远端；锁屏后下部自动出现亮屏按钮，单击直接执行且没有二次确认，普通亮屏状态不显示，未知状态不误报。覆盖设备锁定、熄屏、状态恢复、横屏、安全区和覆盖面板。
- 关闭与资源：关闭后窗口及输入确实结束，不能从管理页恢复；其他设备、传输、连接和手机真实任务遵循各自规则。临时遮挡／重建不误当成关闭，已经关闭的窗口不被恢复流程复活。
- 画面设置：统一检查新页名、入口与反馈，外部不再出现独立比例设置行；比例选项与自定义值在该页完整可用。质量变更使同设备多个已打开画面和随后打开的画面均采用新值，其他设备不变；必要重建保留正确任务与窗口归属，部分失败说明实际结果，不假报全部成功。
- 设备数据与首卡：在目标设备运行核对电量和充电状态变化、离线与读取失败，首卡不显示Android版本；详情页显示有来源且有效的ADB数据与实际版本。私密字段、缺失值与旧结果不冒充有效实时数据。
- 成像与尺寸：在主控实际系统栏环境中确认远控顶部无额外黑区、源画面比例与输入坐标正确；对照实体显示和独立显示记录应用内容大小，依据采样诊断密度／分辨率问题，再验证修复效果。浅色底栏需检查稳定选中态的真实玻璃可见性，同时覆盖滚动背景、拖动和降低透明度。上述均为待运行验证事项，Pencil状态不提供设备通过结论。
- 路由与迁移：移除旧页生产入口，处理既有地址恢复；更新路由／协议／设置来源后生成对应产物，按[工具链契约](repository-tooling.md)执行适用检查。真实屏幕、授权和媒体结果另做设备验证。

## 仅属于设计源稿的事项

一个完整页面一个顶层画布、每块规范／组件／局部状态底板独立成画布、全部留在同一 `mobile.pen`，属于设计文件组织，不要求新增应用路由、页面或文件。设计规范、组件板和局部状态板同样不一一映射为产品页面。所有大画布载体统一浅灰展示底，属于设计文件呈现，不要求改变APP页面或组件内容配色。
