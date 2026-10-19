# 主控系统本地通知：Flutter 共享实现与隐私边界

核对日期：2026-10-17。范围是主控设备把已取得的实时通知／来电观察结果发布到自己的系统通知区；不研究取得被控通知权限，不实现依赖或业务代码。事实、工程建议和未验证项分开记录。依据 [ADR 0002](../adr/0002-rust-adb-and-flutter-monorepo.md) 的四端编译要求与 [ADR 0006](../adr/0006-controller-without-debugging.md)，不引入主控调试授权。

## 结论与版本基线

**推荐候选：`flutter_local_notifications: 22.3.2`，先采用普通即时通知和只导航的点击响应。** 通知策略、隐私裁剪、去重和路由放在共享 Dart；插件承担 OS 发布。先不加后台通知动作、CallKit／Telecom、全屏来电、定时通知或新保活服务。它们不是普通提醒的必要条件。此选择尚未经过本项目依赖解析、四端构建或真机运行。

2026-10-17 查询 [pub.dev 官方包元数据](https://pub.dev/api/packages/flutter_local_notifications)，最新稳定版为 **22.3.2**，发布时间 **2026-10-12T09:13:53.013844Z**；预发布为 23.0.0-dev.4，不作为本次候选。[22.3.2 版本页](https://pub.dev/packages/flutter_local_notifications/versions/22.3.2)

已直接读取发布归档，计算出的 SHA-256 与元数据一致；另逐字节核对标签的 pubspec、Android Gradle、Dart平台实现和Android插件实现与归档一致：

```text
https://pub.dev/api/archives/flutter_local_notifications-22.3.2.tar.gz
9ee28742343dd13df758bb4185e8ded37ac2d1aeca6648c3ba7862c99797517e
```

Context7 已查询 `/maikub/flutter_local_notifications`，但索引和 `master` 有版本时差，最终以以上归档和版本标签为准。当前 master 已提高到 Flutter 3.44 / compileSdk 37 / AGP 9.1.1；这些不能倒推为稳定版要求。[master README](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/README.md)

## 四端实际支持与构建条件

| 平台 | 22.3.2 已有实现与边界 | 依据 |
| --- | --- | --- |
| Android | NotificationCompat；发布包 `minSdkVersion 24`、`compileSdk 36`、Java source/target 17。 | [版本化 Gradle 源码](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/android/build.gradle) |
| iOS | UserNotifications；CocoaPods deployment target **13.0**。不是依赖旧版 iOS 10 就可交付。 | [版本化 podspec](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/ios/flutter_local_notifications.podspec) |
| macOS | UserNotifications；CocoaPods最低 **10.15**，Swift 5。 | [版本化 podspec](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/macos/flutter_local_notifications.podspec) |
| Windows | 联邦插件 `flutter_local_notifications_windows ^3.1.1`；当前稳定 Windows 包为 **3.1.1**，使用 C++/WinRT 和 Dart FFI。Flutter 3.38.1 支持 Windows 10/11，插件原生构建使用 C++17，Windows CMake >=3.14。没有在本机验证特定 Windows build 的通知激活。 | [Windows 元数据](https://pub.dev/api/packages/flutter_local_notifications_windows)、[3.1.1 发布归档](https://pub.dev/api/archives/flutter_local_notifications_windows-3.1.1.tar.gz) 的 `src/CMakeLists.txt`、`windows/CMakeLists.txt`；[插件 README 引用的 Flutter 支持表](https://github.com/flutter/website/blob/6150d58df2f39275ffd589ba32f25557a27e2384/src/content/reference/supported-platforms.md) |

共享最低 **Dart ^3.10.0、Flutter >=3.38.1**，来自 22.3.2 发布包 `pubspec.yaml`，不是截图或平台徽章推断。[版本化 pubspec](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/pubspec.yaml)

Android 还需要应用开启 core library desugaring，配置 `com.android.tools:desugar_jdk_libs:2.1.4`；即时 `show` 也不能省略这个构建要求。稳定版 README 建议 AGP 至少使用其自身的 **8.11.1**。README文字仍写 compileSdk 最低35，而同页示例及实际 Gradle 使用36；采用36作为本项目候选基线，不能把这个文档差异当成已证明35能编译。[22.3.2 Gradle 设置](https://pub.dev/packages/flutter_local_notifications/versions/22.3.2#gradle-setup)、[实际 Gradle](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/android/build.gradle)

本项目只读核对：`pubspec.yaml` 为 Dart ^3.13.5；Android应用已有Java/JVM17、AGP9.1.0，并使用当前本地 Flutter 的默认 compileSdk36/minSdk24/targetSdk36。应用尚无 desugaring 配置；接入时仍需改构建配置并实际构建验证，不能宣称现在已兼容插件。iOS当前 AppDelegate 也没有设置 UNUserNotificationCenter delegate；按插件官方设置需加一处 delegate 连接，使用当前 UIScene/implicit-engine 生命周期验证点击回调。macOS和Windows工程存在，但本次没有构建。[本地应用 Gradle](../../app/android/app/build.gradle.kts)、[本地插件版本](../../app/android/settings.gradle.kts)、[本地 iOS AppDelegate](../../app/ios/Runner/AppDelegate.swift)、[官方 iOS 设置](https://pub.dev/packages/flutter_local_notifications/versions/22.3.2#ios-setup)

## 可直接使用的 Dart API

以下接口均按22.3.2发布源码核对，参数名不是旧版本示例：

| 用途 | 可用接口 | 产品解释 |
| --- | --- | --- |
| 一次初始化 | `FlutterLocalNotificationsPlugin.initialize(settings: InitializationSettings(...), onDidReceiveNotificationResponse: ...)` | 初始化放在共享服务，不随页面重建重复绑定。 |
| 即时发布 | `show(id: ..., title: ..., body: ..., notificationDetails: NotificationDetails(...), payload: ...)` | 发布请求成功不是用户看见或读过。 |
| 撤回／失效 | `cancel(id: ...)`；Android还有 `tag` | 同一远端对象更新沿用本地标识；ID命名空间避开已有前台服务2101。来源撤回、停止观察、失去授权时撤回对应本地项，避免全局 `cancelAll()` 误删其他所有者。 |
| 正在运行的点击 | `onDidReceiveNotificationResponse` | 转交共享路由协调器；不在回调里直接执行远端动作。 |
| 冷启动点击 | `getNotificationAppLaunchDetails()` → `didNotificationLaunchApp` / `notificationResponse` | 在初始化和路由就绪后读取；与运行中回调归一、去重。 |
| Android权限 | `requestNotificationsPermission()`、`areNotificationsEnabled()` | 通过 `resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()` 获取。 |
| Android渠道 | `createNotificationChannel(...)`、`getNotificationChannels()` | 明确区分应用整体允许和单渠道被用户关闭。 |
| 系统设置 | `openAppNotificationSettings()` | Android/iOS/macOS实现已核对；Windows本次没有确认同等接口，不伪造统一可用状态。 |
| Apple权限 | `IOSFlutterLocalNotificationsPlugin` / `MacOSFlutterLocalNotificationsPlugin` 的 `requestPermissions(alert: ..., sound: ..., badge: ...)`、`checkPermissions()` | 初始化用 `DarwinInitializationSettings(requestAlertPermission: false, requestSoundPermission: false, requestBadgePermission: false)` 推迟弹窗，用户启用提醒时再请求。 |

接口证据：[共享插件入口源码](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/lib/src/flutter_local_notifications_plugin.dart)、[各平台 Dart 实现](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/lib/src/platform_flutter_local_notifications.dart)。Windows冷启动／点击缓存见 [Windows发布归档](https://pub.dev/api/archives/flutter_local_notifications_windows-3.1.1.tar.gz) `lib/src/plugin/ffi.dart:54–67,119–133,193–213`；缓存由原生激活回调填入，不能假定所有平台首次读取时都已收到激活事件，需实测启动时序。

Windows初始化需要稳定的 `WindowsInitializationSettings(appName: ..., appUserModelId: ..., guid: ...)`。**未打包为MSIX／没有package identity时，插件 `cancel` 不生效，`getActiveNotifications` 返回空列表**。这是实时通知失效清理的实质限制；Windows候选交付必须选择并验证有身份的打包方式，否则不能承诺旧通知随撤回消失。Windows也不支持插件的周期通知。[Windows 3.1.1 官方 README](https://pub.dev/packages/flutter_local_notifications_windows/versions/3.1.1)、[Windows API发布源码](https://pub.dev/api/archives/flutter_local_notifications_windows-3.1.1.tar.gz)

## 权限、渠道与后台边界

Android13/API33+ 的普通通知需要 `POST_NOTIFICATIONS`；拒绝后普通通知被阻止。权限不授予读取别的应用通知的能力。Android8/API26+必须使用渠道；渠道建立后的声音、重要性等由用户控制，不能靠重复创建或换渠道绕过关闭。应用允许、渠道允许、用户可见是三个不同结果。[Android通知权限](https://developer.android.com/develop/ui/compose/notifications/notification-permission)、[Android渠道](https://developer.android.com/develop/ui/compose/notifications/channels)

建议分开“远端实时通知”和“来电提醒”渠道，继续保留已有低重要性的 `connections` 后台保持渠道及其前台服务通知。显示“系统通知已关闭／渠道已关闭／权限待授权／未知”之类准确状态，并提供系统设置入口；不把静默或未投递视为设备连接错误。渠道级检查不适用于API24/25，需按平台能力降级。

Apple用户可随时修改授权和展示类型；首次请求后再调用不一定重弹系统对话框，应读取状态并提供设置入口。provisional授权只安静进入Notification Center历史，不是无历史投递方案。[Apple官方授权说明](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)

插件负责调用本机通知系统，**不会让已死亡的主控进程继续接收Rust观察事件，也不提供永久后台运行**。本地通知点击可以启动应用，与进程死亡期间仍能观察被控设备是两回事。不得为了通知发布自动开启设备连接／helper／控制会话；后台接收仍服从已有后台保持和观察意图。[插件入口实现](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/lib/src/flutter_local_notifications_plugin.dart)、[当前进程引擎说明](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/ProcessFlutterHost.kt)

## 锁屏、敏感正文与不落盘

**事实：** Android `VISIBILITY_PRIVATE` 隐藏敏感详情，但不能替代正文裁剪；当前官方指南把基础信息中的标题也列为可能公开的信息。`setPublicVersion(Notification)` 可以提供明确的安全替代版本，最终锁屏可见性仍受用户设置影响。[锁屏指南](https://developer.android.com/develop/ui/compose/notifications/create-notification#set-lockscreen-visibility)、[publicVersion API](https://developer.android.com/reference/android/app/Notification.Builder#setPublicVersion(android.app.Notification))

**插件缺口：** 22.3.2 `AndroidNotificationDetails.visibility` 暴露 private/public/secret，原生只调用 `builder.setVisibility(...)`；Dart DTO、映射和Android实现没有 `publicVersion` / `setPublicVersion`。不能把设置private描述为已经发布自定义公开版本。[Dart字段](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/lib/src/platform_specifics/android/notification_details.dart)、[Android实现](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/android/src/main/java/com/dexterous/flutterlocalnotifications/FlutterLocalNotificationsPlugin.java)

**推荐策略：** 默认系统通知只给通用标题和正文，例如“设备有新通知，请打开邻接查看”；避免联系人、电话号码、短信正文、OTP、截图、附件路径以及正文派生的ticker/subtitle。即使用户在系统锁屏设置中允许全部展示，也只会公开这份已裁剪内容。系统payload只携带不含秘密的目标标识／路由版本；被控对象可能已撤回，打开后重新读取当前状态。用户明确开启预览也不能消除系统历史风险；OTP等高度敏感内容建议始终不进入主控OS通知。

**事实：** Android15对含OTP通知限制的是“不可信通知监听器读取未裁剪内容”，可信关联应用等存在豁免；屏幕共享对敏感通知也有裁剪／publicVersion行为。这不是本产品可靠识别OTP或安全转发正文的证明。[Android15行为变化](https://developer.android.com/about/versions/15/behavior-changes-all#otp-redaction)

**“不落盘”必须限定主体。** 插件Android即时 `show` 走 `showNotification`，没有调用调度通知的JSON缓存；初始化仍写默认图标等设置，payload进入PendingIntent。定时通知则把NotificationDetails序列化进SharedPreferences。应只用即时发布、不保存应用通知历史、不把正文放payload／日志／持久化去重表。[发布包Android源码](https://pub.dev/api/archives/flutter_local_notifications-22.3.2.tar.gz) `FlutterLocalNotificationsPlugin.java:264–277,536–556,1707–1754`

Android系统通知历史是可选OEM功能、用户开启后默认保留24小时；AOSP实现用AtomicFile写历史，包含title/text。`cancel`、`timeoutAfter`或private没有提供“从未写入磁盘”的保证。Apple的Notification Center和Windows通知区也不应被当成应用的内存缓存。**可承诺应用自身不建立通知历史；不能承诺交给OS后的敏感正文永不落盘。** 若需求是任何层都不落敏感内容，只发布通用通知，或完全不向OS发布这类提醒。[AOSP历史说明](https://source.android.com/docs/core/display/notification-history)、[历史数据库](https://android.googlesource.com/platform/frameworks/base/+/master/services/core/java/com/android/server/notification/NotificationHistoryDatabase.java)、[历史字段序列化](https://android.googlesource.com/platform/frameworks/base/+/master/services/core/java/com/android/server/notification/NotificationHistoryProtoHelper.java)、[Apple授权／历史说明](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)

## 来电与点击的安全职责

普通来电观察提醒可以用普通 `show`，`fullScreenIntent: false`，默认 `AudioAttributesUsage.notification`；不启动麦克风、不添加接听／拒接后台动作，不采用插件Windows的incomingCall/urgent场景，也不启用Apple critical告警。系统声音可能影响其他播放的体验，是否静音按用户设置选择；本次未验证音频焦点交互。[Android详情默认值](https://github.com/MaikuB/flutter_local_notifications/blob/flutter_local_notifications-v22.3.2/flutter_local_notifications/lib/src/platform_specifics/android/notification_details.dart)、[Windows详情发布源码](https://pub.dev/api/archives/flutter_local_notifications_windows-3.1.1.tar.gz) `lib/src/details/notification_details.dart`

Android普通提醒只需普通发布条件；`USE_FULL_SCREEN_INTENT`、录音权限、Telecom自管理通话是另外的能力。仅做提醒无需取得这些权限；`POST_NOTIFICATIONS`的自管理通话豁免要求MANAGE_OWN_CALLS、ConnectionService和注册PhoneAccount，不能借“来电”类别绕过通知权限。[Android普通与紧急通知](https://developer.android.com/develop/ui/compose/notifications/create-notification)、[自管理通话豁免](https://developer.android.com/develop/ui/compose/notifications/notification-permission#apps-configured-to-self-manage-phone-calls)、[录音权限](https://developer.android.com/media/platform/mediarecorder#requesting-permission-to-record-audio)

建议点击只导航到该设备的通知／通话专用功能页；route协调器验证配对身份、精确目标、当前连接／观察代次与当前实时对象。冷启动恢复期间只暂存路由意图，待权威状态可用后显示；目标不存在则明确失效，不靠旧payload新建控制会话、重发通知动作、全局接听或自动开启麦克风。运行中回调与冷启动详情可能重复到达，应只消费一次导航意图。此段是产品集成建议，不是插件自动保证的行为。

## 与极小OS适配的比较

| 候选 | 能解决什么 | 代价与选择 |
| --- | --- | --- |
| 共享Dart + 原版22.3.2 | 四端发布／点击的现成实现；通用安全正文不需要publicVersion。 | **优先。** Android只补必要Gradle配置／资源，Apple接delegate，Windows验证MSIX。不是零原生依赖，但不新增整套应用Kotlin通知实现。 |
| 极小插件扩展 | 若产品确实要求“解锁后有正文、锁屏自定义安全版本”，在插件Android DTO／映射／builder加结构化publicVersion。 | 候选，尚未实施或验证。优先上游PR或受控最小patch；不得允许任意Intent／任意通知动作。仍无法保证正文不落系统历史。 |
| 复用现有平台通道独立实现 | Android现有 `ConnectionService` 已能发布通知，理论上可另加show/cancel和路由。 | 不推荐作四端主路径：当前仅前台服务固定通知，无实时对象／冷启动路由合同；iOS/macOS/Windows还要各写实现。现有 `ProcessFlutterHost` 多数平台方法在无Activity时拒绝，后台发布还需改进程级分派。即使Android代码少，也会重复插件生命周期职责。[现有服务](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/ConnectionService.kt)、[现有通道](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/ProcessFlutterHost.kt) |

## 尚待实际验证的验收点

本次只读源码与官方资料，**未执行pubget、生成、构建、Flutter测试或AVD／真机操作**。下列是后续候选验收，不是已通过结论：

1. 固定版本解析后四端编译，Android release资源裁剪／desugar，当前AGP9.1与Flutter项目的实际兼容性。
2. Android API24/26/33+和主流OEM：应用拒绝、单渠道关闭、DND、锁屏各种用户选项，默认通用内容始终不泄漏正文；权限拒绝不会误报观察失效。
3. 前台／后台／Activity重建／进程冷启动点击；iOS UIScene implicit-engine与Windows COM激活时序；同一点击只导航一次。
4. 来源撤回、断连、resync失败／成功、授权撤销、快速切换设备、更新后旧点击：只校验当前对象，不重放动作；晚回调不能恢复旧owner或发布旧通知。
5. Windows MSIX身份下show/update/cancel和实际清理；未打包模式明确不承诺撤回。Apple权限关闭、预览及Notification Center表现分别验证。
6. 关闭应用后不声称仍能接收；系统已有安全提醒的点击可进入应用，失效目标不执行操作。日志、payload、持久化存储不含敏感正文和OTP。

后续实施已采用22.3.2并取得Android构建、公开系统源双AVD发布/撤回/点击证据；本报告前述“未执行”指研究当时，不覆盖后续交付。当前实现与尚未验证矩阵见[实现记录](../implementation/system-notifications.md)及[运行验证](../implementation/validation.md#画质实像素与主控系统通知)。
