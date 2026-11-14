# 平台与能力边界

主控以普通应用身份运行，不要求开启调试。平台安装下限以构建配置为准；被控 Android 无需 root 或配套 APK，但须开启调试并授权临时服务。免安装仍会在被控手机执行临时代码，不取得系统应用权限；主控权限不能由被控 shell 权限补齐。

## 窗口与形态适配目标

所有页面按当前应用窗口的可用宽高、方向、系统安全区、显示特征和输入方式布局，不按设备名称或物理屏幕猜测。compact 窗口使用单列与底部导航；medium 窗口使用沿可用窗口高度铺开的侧栏或 rail；expanded 窗口使用侧栏、列表／详情双栏和工作区工具栏；freeform 桌面窗口即使宽度低于 expanded 断点也保留工作区工具栏。桌面不绘制手机式默认顶部状态条，窗口标题栏和窗口菜单由宿主负责，应用内容从工作区工具栏开始。设计基线与窗口示意维护于 Ardot《规范 / 07 折叠、平板与多窗口适配》。

折叠与双屏必须避开铰链、折痕、挖孔和相机等系统保留区。外屏保持单列，完全展开使用双栏，书本／桌面半折按实时折叠特征避让；只有 `FoldingFeature.isSeparating` 为真时才把 Android 特征当作窗格分隔，非分隔折痕保持连续内容并避开关键控件。开合、旋转、分屏、自由缩放和键盘出现时保留当前设备、应用任务、焦点、选择、未提交输入和滚动位置。iPhone Duo 使用外屏单列、内屏双栏和 reserved regions；外屏及内屏横向姿态的工具栏、导航和标签栏进入系统侧边垂直栏，内屏竖向姿态使用横向栏；Flutter 通过 `GlassNavigationShell` 与 `GlassVerticalBar` 接收 UIKit 的垂直栏边缘和保留区，底部导航继续由单一 `GlassTabBar` 持有。Android 依据实际 app window 的 WindowManager 指标与 `FoldingFeature.isSeparating` 选择布局，不依据物理设备型号；HarmonyOS 使用 `windowSizeChange` 驱动断点，API 12+ 的 `FoldSplitContainer` 处理展开、悬停和折叠态，`windowStatusChange` 只更新窗口模式，`foldStatusChange` 只服务悬停等物理形态行为；Flutter 统一层只消费宿主提供的 `WindowEnvironment`。研究依据：[Android 自适应窗口尺寸](https://developer.android.com/develop/adaptive-apps/guides/support-different-display-sizes)、[Android FoldingFeature](https://developer.android.com/reference/androidx/window/layout/FoldingFeature)、[Apple iPhone Duo 设计](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)、[Apple iPhone Duo 准备指南](https://developer.apple.com/iphone-duo/prepare/)。

连接屏幕的独立窗口属于控制会话的窗口实例。每个实例拥有唯一窗口身份、设备身份、应用任务、视频捕获和输入焦点；关闭只撤销自己的会话，迟到回执不能更新已关闭窗口。平板、桌面、移动端和鸿蒙分别由宿主的 Android Activity/WindowManager、iPadOS/macOS scene/window、HarmonyOS WindowStage 或对应插件创建和销毁；HarmonyOS 辅助窗口由宿主显式管理，主窗与辅助窗不可共享页面所有权。桌面子 engine 若没有 `window.readEnvironment` 宿主回调，使用 `desktop_multi_window` 当前 `WindowController.windowId` 保持身份隔离。Flutter 官方 view／multi-engine 能力不等于统一的原生窗口 API。宿主不支持额外窗口时回退为同页分栏，但继续使用同一窗口身份和状态边界。

Flutter 侧已交付 `WindowEnvironment`、`WindowEnvironmentCodec` 与显示特征保留区布局：Android 宿主通过 AndroidX `WindowInfoTracker` 的 `FoldingFeature` 事件投影折叠／铰链及 `isSeparating`，并把 Activity 的分屏／画中画事实投影为 `split`／`floating`；WindowManager 回调、配置变化和 Activity 生命周期会重新发送同一窗口的最新模式、边界、安全区 inset、挖孔与折叠特征。iPhone Duo 在 iOS 27.1+ 由 scene 的 `UIView.ReservedRegion` division 和 active occlusion frame 投影折叠与摄像头保留区，铰链交互以及 scene 激活、前后台、尺寸更新和断开前的刷新事件触发布局重新读取；独立 scene 的初始路由和窗口身份通过 `stateRestorationActivity` 保存，系统重建 scene 时恢复同一控制会话。HarmonyOS 宿主可将 FoldSplitContainer 投影为同一 payload；窗口指标变化、平台姿态事件或应用恢复前台时重新读取宿主投影，当前 Flutter view 的尺寸与显示特征保持实时；桌面工作区和折叠导航会为全高折痕／铰链留下真实空区，只有明确分隔的特征才切分窗格。横向全宽铰链进入桌面半折时，`WindowPaneHost` 选择安全子屏并重写该子屏的 MediaQuery，内容不跨铰链。Linux、macOS、Windows 使用 `desktop_multi_window` 创建独立 Flutter engine，并在每个子窗口注册插件；Android 使用 `FlutterEngineGroup` + 独立 `Activity` 任务，iOS/iPadOS 使用 `UIApplicationSupportsMultipleScenes` + `FlutterEngineGroup` + `SceneDelegate` 创建真实窗口。

鸿蒙宿主适配器按以下边界实现：`windowSizeChange` 是尺寸与断点的唯一入口；`windowStatusChange` 只更新 `mode`（全屏、分屏、浮窗等）；`foldStatusChange` 只触发物理折叠／悬停相关布局重新读取，不能当作窗口尺寸事件。API 12 及以上由 `FoldSplitContainer` 管理展开、悬停和折叠分栏，适配器将每次计算得到的窗口 bounds、safe insets、reserved regions、fold posture 和 mode 编码成现有 `WindowEnvironment`，通过 Flutter 的 `EventChannel` 推送快照；窗口销毁前先发送最后一次快照，再解除监听。主窗与辅助窗分别持有 window identity、设备 identity 和 Flutter engine，辅助窗关闭只撤销自己的控制会话。实现依据：[HarmonyOS Window API](https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-window-window/)、[FoldSplitContainer](https://developer.huawei.com/consumer/en/doc/harmonyos-references/ohos-arkui-advanced-foldsplitcontainer/)、[窗口布局](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/window-layout/)、[折叠与显示模式事件](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-display/)。

Flutter 官方主线没有 HarmonyOS 目标；OpenHarmony 社区 fork 需要独立 SDK、`flutter.har` 和 DevEco/HVIGOR 工具链（见 [社区 fork](https://gitee.com/openharmony-sig/flutter_flutter) 与 [Flutter 讨论](https://github.com/flutter/flutter/issues/178206)）。当前仓库已有上述统一 payload、Dart 侧回退契约和规格，但没有可由本仓库编译的 OHOS 宿主工程，因此不能把 HarmonyOS 标记为已交付的原生多窗口；接入时只需实现该适配器，不应在 Flutter 页面层新增厂商分支。

实现时必须在真实窗口创建、调整大小、折叠姿态、切换、恢复、关闭和迟到回执链路中验证；不支持的能力显示实际替代路径，不自动重放打开请求。

## 功能条件与替代路径

| 能力 | 条件与限制 |
| --- | --- |
| 基础连接 | 按协议与授权握手判断，配对和传输方式见[连接规则](device-connection.md) |
| 整机画面与输入 | Android 5／API21 起；仍需捕获、编码与厂商输入权限 |
| 独立窗口、活跃应用 | API29 起；需真实任务能力。窗口不可用时由用户选择手机屏幕 |
| 设备输出声音 | API30 起；Android 11 启动还需满足解锁条件，应用可禁止捕获；不是窗口独立音轨 |
| 剪贴板 | 仅两端实际可读的文字；后台与平台拒绝不能报告同步成功 |
| 文件、搜索、相册 | 仅当前身份可读范围；权限失败、未检查与空内容分别呈现 |
| 预览 | 图片按实际解码及方向显示；视频缩略图需 API27，受限时保留原件入口，不自动下载整段视频 |
| 通知、通话 | 分别检查当前用户、系统接口与权限；不通过 root、APK 或权限绕过补齐 |
| 电话接力目标 | 逐通话控制、下行声音、麦克风上行及声音交接分项验证，并区分主控平台、被控设备与通话类型；单向音频不代表完整接力，见[电话接力](calls.md) |

版本门槛不保证实际可用。单项失败只拦对应操作，未知保留检查入口，设置指引注明操作端。

## 主控差异

无线调试配对／扫码与已有授权的 IP 连接按各宿主的网络和授权结果提供。iOS 当前未交付 USB 设备枚举／授权描述符接入，也未提供 Android 式持续后台保持；不能仅凭统一设计入口暗示可用。USB 及后台入口先核对宿主实际支持，不支持时给出明确原因和无线／返回前台的替代路径。Android USB 仍需系统 USB 许可和被控调试授权；桌面采用实际可用的宿主 ADB 能力。系统提醒还受各宿主实现和权限限制。

桌面连接使用应用独立管理的 ADB 服务，不接管用户已有服务。Android 更新安装沿用原签名，不自动卸载应用或清除本机数据。

## 远控性能验收目标

默认目标为启动至首份真实解码像素不超过 1000 ms，输入响应 P50 不超过 200 ms、P95 不超过 300 ms。输入响应从发出按键计到目标变化出现在解码帧；这两个口径不等同于屏幕实际显示耗时，输入响应也不等同于纯解码耗时。

结果注明主控、被控、解码后端、构建模式、分辨率及连接方式，比较时保持目标内容与负载一致，同时核对实际纹理输出、暂停恢复及活动结束后的资源释放。放宽阈值只用于诊断，不计为达到默认目标；这些是验收目标，已验证组合以实际测量为准。

## 当前交付边界

- 通话当前仅请求打开手机系统通话界面；尚无逐呼叫接听、拒接、挂断及双向语音。系统接受请求不证明界面可见。这是交付现状，不是技术不可行结论；完整接力为待验证目标，未验证组合仅显示原界面路径。
- 自动剪贴板复用 scrcpy；仅当前可见且获焦的控制画面参与，切设备／恢复先建立两端基线，保留本机内容。写入须收到回执并读回一致；读不到文字、权限受限或结果未知时暂停，不报告同步成功。各主控平台与被控组合仍须设备验证。
- 相册检查时渐进展示已发现内容；进程内按设备保留最近集合和位置，再访后台检查，新终态由用户主动更新。进程重启不恢复历史集合；权限及中途失败保留已知结果，不伪装完整图库。
- 截图来自已接收的视频帧，可能降采样；暂停时取最后画面。缩略反馈提供系统保存及分享，系统保存复用同次交付记录，系统接收分享不证明接收应用已保存。
- Android 目录发送使用系统目录授权；Linux 使用原生目录选择和公开文件能力递归发送；iOS 尚未提供目录发送。系统保存当前由 Android 目录授权及 Linux 精确文件能力提供；macOS／Windows 的精确本机文件能力尚未交付，文件仅提供系统分享，目录操作不暗示已可用。iOS 文件交付使用系统分享，不将应用私有暂存说成已保存。
- 通知清除作用远端，批量操作先确认来源与范围；持续通知和未知结果保留核验。当前活动区分正在进行与待核对，未知启动仅核对同次记录，关闭记录保留手机应用任务。
- 应用打开方式按本机设备记录与包名记忆，优先复用尚存会话；能力变化需重新选择。电话入口和真实来电进入同一完整电话页，未验证接力组合明确声音仍在手机。独立设备详情展示设备参数，诊断集中连接与功能检查，检查项直接平铺，画面偏好集中于“画面与控制”。
- 记录导入先预览，按同一内容的持久回执抑制重复追加；默认保留本机设置，只有明确选择才导入全局偏好。设备偏好、应用打开方式和授权身份不由元数据导入覆盖，写入结果未知先核验同次导入。
- 当前应用启动按包名选择任务，不能保证精确恢复某个多实例任务页面；熄屏请求也不保证立即要求强认证解锁。
- 通知与来电系统提醒意图分别保存且默认关闭，仅明确开启时索权；当前设备通知页可见时抑制重复系统提醒。实际送达及点击仍取决于宿主权限与平台支持。
- 原件完整暂存受固定 512 MiB、真实磁盘可用空间及受保护占用限制；新准备前检查容量，空间无法核验时拒绝新准备。当前无通用大文件直接系统保存方案，不能宣称任意大小文件可取回。
- Windows 系统提醒不受支持。各宿主的权限和通知点击须分别验证，提醒不可用仍可查看应用内内容。
- 暂不可见的控制页可停止本地呈现，不能据此推断远端捕获或编码停止。
- 画质是请求上限，最终尺寸、帧率、编码与声音取决于实际协商；静态画面无新帧不等于断连。
- 无光学支持时使用非光学回退；降低透明度或提高对比度使用实体面。Apple 自绘控件使用 `liquid_glass_widgets` 的 iOS 27 regular/clear 光学预设，保留系统可变材质的层级和统一交互；系统首选玻璃外观由 Apple 标准组件自动响应，Flutter 自绘层不读取未公开的偏好值，也不伪造 clear/tinted 状态。自绘层仍必须在系统首选外观、降低透明度、提高对比度和减少动态组合下做真机视觉验收；未完成对应真机验收时不能宣称完全复刻系统玻璃。已声明支持而初始化失败时进入可重试启动错误。

## 数据与授权保护

身份在本机保存，元数据与云备份不恢复授权；显式导入见[授权密钥](device-connection.md#授权密钥)。不宣称硬件不可导出。

密钥、配对码、通知正文和剪贴板不得进入诊断或分享报告。复制、系统分享与远端写入须有明确用户动作。资源不足拒绝新活动或明确暂停所属活动，保留已有数据和其他设备的重要活动。

兼容声明注明实际宿主、被控版本与验证环境；编译、夹具、静态稿和设备运行各自只证明对应层级。

视觉以 [iOS 27 规范](../design.md)为目标；静态设计齐全不表示系统玻璃外观联动、动态字体、读屏、GPU 材料或新增产品动作已完成。媒体暂存的外部读取保护尚不能安全主动解除，满额时不可通过清理受保护文件恢复预算，见[媒体暂存](content-and-transfer.md#媒体暂存与空间准入)。
