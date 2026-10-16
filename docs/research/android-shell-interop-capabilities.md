# Android 临时 shell JAR：通知、短信和通话互联的权限边界

核实日期：2026-10-16。适用前提：**主控端不开调试；被控端已授权 ADB、无 root、不安装额外 APK，允许临时 `app_process` JAR**。本文只做源码与官方文档检索，未连接设备、改权限/AppOps、拨号、发送短信、安装或运行原型。使用 research skill，先查询 Context7 的 Android 官方文档，再沿 AOSP 服务端权限检查核实。已有媒体传输与多会话研究见 [scrcpy、媒体与 server 报告](scrcpy-media-and-server.md)。

这里的“已证”是固定 AOSP 版本的源码事实；“工程推论”是权限链闭合后的实现可能性；“需 POC”是我们负责通过真机实验解决的缺口。它们都不等于所有厂商 ROM 已兼容。

## 核心结论与能力矩阵

**免被控 APK 并不等于只能屏幕模拟操作。** AOSP shell 本来就是系统内置的特权身份，通知实时监听、短信读取/发送、电话状态与接听挂断都有值得实施验证的 Binder/Provider 路径。真正需要区分的是：通知的 listener token 与 action 能力、短信写库的独立 AppOp、电话控制与通话音频、Android 版本与厂商音频实现。

| 能力 | Android 11 对照 | Android 17 固定源码结论 | 工程结论与未证部分 |
| --- | --- | --- | --- |
| 通知当前列表、实时新增/更新/移除 | Shell 有 `STATUS_BAR_SERVICE`；注册入口以该权限放行 | `registerListener` → `registerSystemService` 可直接注册 Binder，未要求已安装的 Service 组件；快照可走 listener token | **有完整候选链路**；临时 JAR 的 Binder callback、重连、ROM 差异需 POC。不能用 dumpsys 轮询替代。[N1]、[N2]、[N3]、[V11] |
| 清除通知 | 同类 listener 接口存在，不以普通应用包名冒充通知拥有者 | `cancelNotificationsFromListener` 检查 token/可见范围；仍有 ongoing、direct-reply 延长生命周期等限制 | 可实现系统允许的清除；不能承诺所有通知均可清除，清除通知也不等于消息已读。[N2] |
| 点击通知/动作 | `PendingIntent` 能力路径存在 | 保留原通知给出的 `contentIntent`/action `PendingIntent`，在目标端发起；creator 与实际 sender 都会进入系统决策 | **有候选链路**；被取消、应用认证、后台启动、锁屏、目标显示等需验证；不能重建普通 Intent 代替原 PI。[N4]、[N5] |
| 通知内直接回复 | 仅适用于原应用确实提供的 `RemoteInput` action | 原 `RemoteInput.resultKey` + `addResultsToIntent` + 原 action PI；immutable PI 不接收 fill-in 内容 | 不能为任意通知制造回复能力；PI 发送完成不是对方应用/服务器确认消息送达。[N4]、[N5]、[N6] |
| SMS 当前数据读取 | Shell 声明 `READ_SMS` | SmsProvider 导出并检查 `READ_SMS`、AppOps；shell 不属于 Provider 的 system/phone/default-SMS 全量豁免身份 | 可读候选成立，但可见集合、用户、解锁、OTP/RCS 特殊保护需探测；不能宣称任意内部表均可读。[S1]、[S2]、[S3] |
| SMS 更新事件 | Provider/ContentObserver 路径，未逐一验证旧版行为 | SmsProvider 对短信 URI 调用 `notifyChange`，可注册观察者后增量重查 | 是真实变更通知，但不是持久事件队列，也不是每条消息完整事件载荷；断连须重新对账。[S2]、[I3] |
| SMS 标已读、删除、插入 | 本轮不推断 Android 11 默认 AppOp 结果 | `OP_WRITE_SMS` 默认 **IGNORED**；shell **没有** AppOps 的 root/system 通用豁免，也不在 SmsApplication 特殊授权包表中 | **默认不能按“shell 特权”直接判写库可用**；shell 有管理 AppOps 的权限，限定启用/恢复是可验证候选，未实际改动。[S4]、[S5]、[S6]、[I1] |
| SMS 发送 | Shell 声明 `SEND_SMS`/`MODIFY_PHONE_STATE` | SmsPermissions 检查 `SEND_SMS` + UID/包名 `OP_SEND_SMS`；另有订阅/用户检查 | 发送与任意写库是两条路径；无额外 APK 不自动构成阻碍。双 SIM、发送/送达回执、失败重试需 POC。[S7]、[S8] |
| SIM 电话状态实时订阅 | 有电话相关 shell 权限；未穷尽事件版本 | TelephonyRegistry 接受 Binder callback，并校验调用 UID 对应包名、事件权限 | 不必用电话 dumpsys 轮询；SIM 状态不等于所有第三方 VoIP 的统一完整通话列表。[C1]、[I1] |
| 拨号、接听、挂断 | Telecom 同样有 MODIFY_PHONE_STATE / ANSWER_PHONE_CALLS 路径 | 拨号检查包名、CALL_PHONE/AppOp；接听/挂断优先接受 MODIFY_PHONE_STATE；紧急电话等另有限制 | 有无额外 APK 的候选链路。被选中的通话、用户、电话账户需明确；不能推广为任意聊天 App 的接听 API。[C2]、[C3] |
| 主控听到目标 PSTN 下行、主控麦克风注入目标上行 | 本轮比较的 AudioManager 没有右列三项 API；**未证明 Android 11 必然做不到** | 有 `isPstnCallAudioInterceptable`、`getCallDownlinkExtractionAudioRecord`、`getCallUplinkInjectionAudioTrack`；Shell 声明 `CALL_AUDIO_INTERCEPTION` | **有强候选，不是通用已支持**：还依赖当前通话模式、音频设备/策略/HAL 和真实路由；必须真机双向通话 POC。[A1]、[A2]、[A3]、[A4] |
| 通用 VoIP 双向通话 | 未证 | 新音频 API 分辨 PSTN 与 communication 模式，不能证明每个 App 都走兼容路径 | 需按实际 App、音频焦点、蓝牙/有线/扬声器、麦克风并发验证；不等同于全系统虚拟麦克风。[A1]、[A3] |

## 共同前提：UID、包名、已授权限和 SELinux 必须同时成立

**已证。** AOSP `com.android.shell` 是设备原有 APK，`sharedUserId=android.uid.shell`；构建配置为 platform 签名且 privileged。通过已授权 ADB 启动的非 root shell JAR 仍是 shell UID 2000，不会因为 JAR 自己没有 Manifest 而失去该 UID，也不会因为使用 `SystemContext` 就变成 UID 1000。Shell Manifest 的声明、平台签名权限与系统组件默认运行时授权逻辑必须一起看；仅发现某个 `<uses-permission>` 不足以推出某台 ROM 当前已经放行。[I1]、[I2]

**已证。** 官方 `content` 命令就使用 `getContentProviderExternal`，将 UID 2000 对应包名解析为 `com.android.shell`，传入真实 `AttributionSource`，最后释放 provider。这是免 APK Provider 访问的具体先例，不是读 `/data` 数据库文件的许可。TelephonyRegistry 的 `mAppOps.checkPackage`、Telecom 的 `enforceCallingPackage` 和 AppOps 的 UID/包名核对仍然生效。自行把包名写成短信应用或 `android` 不会获得对方身份；远端 shell 的权力也不会赋给主控 App。[I3]、[C1]、[C2]、[S5]

**已证。** AOSP SELinux 的 `shell.te` 明确允许 `app_process` 并调用 `app_domain(shell)`；`seapp_contexts` 限制 shell domain 的 UID/包对应关系；`app.te` 允许 appdomain 与系统 Binder 服务、应用 Binder 的必要通信。它们支持这类 IPC 路径，**没有**赋予任意私有文件读取、radio socket 或任意 Binder 方法的免检权。ROM 可改 SELinux、服务权限、AppOps 与音频策略，必须记录设备实际状态。[I4]、[I5]、[I6]

**工程推论。** 临时 JAR 应使用目标版本匹配的 hidden Binder 适配、真实 shell 身份和可正确归因的 Context；fake Context 只解决 attribution/包名和 API 兼容问题，不是提权。主控端仅通过自有传输与该进程通信，不需开启 USB/无线调试。

## 四条影响实现的证据链

### 1. 通知：直接 listener Binder 可以成立，token 与原 action 必须保留在目标端

**已证。** Android 17 `NotificationManagerService.registerListener`（6164–6167）调用 `enforceSystemOrSystemUI`，后者（7004–7007）实际允许持有 `STATUS_BAR_SERVICE` 的调用者；Shell 有此权限。`ManagedServices.registerSystemService`（1372–1379）直接接收接口与调用者 UID；对应 `registerServiceImpl`（2101–2116）创建 `isSystem=true`、无 service connection 的记录并 `linkToDeath`。这条重载没有“必须安装一个 NotificationListenerService APK”的组件解析步骤。Android 11 固定源码与 Shell 权限也保留了同类路径。[N1]、[N2]、[N3]、[V11]

**已证。** 注册的 `INotificationListener` Binder 本身是后续能力 token。`getActiveNotificationsFromListener`（6516–6527）和 `cancelNotificationsFromListener` 通过 `checkServiceTokenLocked` 找到注册信息，再按用户/profile/可见范围处理。直接 `getActiveNotifications(callingPkg)` 则走另一个 `ACCESS_NOTIFICATIONS` + AppOp 入口；不能把两条路径混为一谈，Shell Manifest 中也没有声明这个 `ACCESS_NOTIFICATIONS`。进程死亡触发 Binder death 清理；重连须新注册、取快照、对齐回调。[N2]、[N3]、[N1]

**已证。** Android 17 trusted-listener 判定会考虑 `RECEIVE_SENSITIVE_NOTIFICATIONS`、平台签名与相关 AppOp，Shell 声明了该敏感通知权限；因此不能直接套用“普通第三方 listener 看不到 OTP”判 shell 一定读不到。反过来，应用锁通知路径还会对普通 listener 做额外脱敏，不能承诺所有私密正文均可获得。[N1]、[N2]

**已证。** `PendingIntentRecord.sendInner` 记录真实发送者 UID/PID，同时保留创建者 UID/包名；它不是让临时 JAR 变成原应用。immutable PI 忽略 fill-in；Activity PI 把两方身份、启动 options 和后台启动权限交给 ActivityTaskManager。Shell 的 `START_ACTIVITIES_FROM_BACKGROUND` 是有利条件，但不证明任意通知点击都可绕过应用自身认证、锁屏或展示约束。RemoteInput 只能使用原 action 提供的 key、输入约束和 PI；`isAuthenticationRequired` 应在跨端交互中尊重，不能用直接 Binder 发送当作绕开认证的产品契约。[N1]、[N4]、[N5]、[N6]

**工程推论。** 留在目标端的注册 Binder、notification key 与原 PI/action 才是有效操作引用；传给主控的是有会话与版本边界的引用。通知更新、撤回、用户切换、JAR 重启后旧引用可能失效。回复操作必须区分“系统接受 action”“应用处理”“网络发送/送达”；系统并不统一提供后两者回执。

### 2. SMS：读、观察、发送和写库必须分别判定，shell 没有通用 AppOps 豁免

**已证。** SmsProvider 导出读取权限为 `READ_SMS`，并 `setAppOps(OP_READ_SMS, OP_WRITE_SMS)`。ProviderUtil 的全量访问判断只优待 system/phone UID 与默认短信应用；UID 2000 不在其中。查询还可能进入 OTP、受限 RCS 等过滤路径，credential-encrypted 数据与目标用户也影响结果；“能查短信”不等于能读全部内部表、短信数据库附件或通用 RCS 会话。[S1]、[S2]、[S3]

**已证。** `ContentProvider.Transport.enforceWritePermission` 在权限检查后独立执行写 AppOp；Android 17 `OP_WRITE_SMS` 默认值为 `MODE_IGNORED`。`AppOpsService.isOpAllowedForUid`（2972–2974）只把 root/system 放进通用直接放行集合，**不包含 shell**；`com.android.shell` 的特殊分支是 attribution tag/包名验证的兼容处理，不是跳过 AppOp 模式。`NON_PACKAGE_UIDS` 出现 shell 也只是维护 UID state，不是授予所有操作。SmsApplication 的特殊系统包写权限授予表没有 shell，UID 1001 的显式授权也不覆盖 UID 2000。[S4]、[S5]、[S6]

**已证与推论边界。** Shell 自身声明 `MANAGE_APP_OPS_MODES`；AppOpsService 的 `setUidMode`/`setMode` 以这个权限为检查条件，并额外限制设备 provisioning 包。因此 **AOSP 存在无需安装默认短信应用、为现有 shell UID 启用相关 AppOp 的候选管理路径**，不能据默认 IGNORED 下“短信写入必然不可能”的结论。但本轮未执行启用、写库、恢复；ROM、用户限制和 Provider 业务限制仍须 POC。UID 级变更影响该目标上同 UID 的其他 shell 客户端，可能在进程退出后继续存在；工程上必须核对原值、限定用途、处理恢复失败，不能称为只存在于临时 JAR 内的授权。[I1]、[S5]、[S6]

**已证。** 发短信走 SmsController/SmsPermissions，明确检查 `SEND_SMS` 与 caller UID/包名的 `OP_SEND_SMS`。非持久化发送另有 carrier/IMS 或 `MODIFY_PHONE_STATE` 条件；订阅与用户也有检查。由发送路径保存已发记录与取得任意 Provider 写权限不是一回事。回调的系统发送结果、可选运营商送达结果、对方实际阅读也不是同一状态。[S7]、[S8]

**工程推论。** SMS 更新可走 ContentObserver 的失效通知再查询；它不能补回进程没运行时的每个瞬时中间状态。标已读/删除如果要求双端一致，必须以目标端实际更新结果确认；断连后的发送不能仅凭客户端超时自动重试，否则可能重复扣费/重复发信。通知回复也不能替代完整 SMS 数据接口。

### 3. 电话：shell 可以满足控制权限，但“某个电话”与“任意 App 的通话”不同

**已证。** Android 17 TelephonyRegistry 的 `listenWithEventList` 进入 `listen` 后校验真实 UID 与包名，再按事件检查 READ_PHONE_STATE 等权限。Shell 拥有电话状态相关声明；可实现真实 Binder 回调，不能把它包装成所有第三方通信 App 的完整通话数据库。[C1]、[I1]

**已证。** Telecom 接听/挂断的 `enforceAnswerCallPermission` 先接受 `MODIFY_PHONE_STATE`，否则检查 `ANSWER_PHONE_CALLS` 和相应 AppOp。Shell 有前者，Android 11 对照也有同类路径。拨号另外检查包名对应调用 UID，再走 CALL_PHONE/AppOp 等条件；传 `com.android.shell`，不能伪造默认拨号器包名。`endCallInternal` 拒绝紧急通话；接听选择 ringing/simulated-ringing 通话，其他路径也检查用户与 self-managed 等条件。方法返回成功不等于任何指定第三方 VoIP 已被控制。[C2]、[C3]、[I1]

**工程推论。** 多 SIM、来电等待、正在通话又来电、多个被控设备同时来电，都需要产品通话对象和设备归属，不能只给全局“接听/挂断”按钮。第三方 App 没有接入 Telecom 的呼叫，可能只能走它提供的通知 action 或界面控制；本轮没有证明通用私有接口路径。

### 4. 双向通话音频：Android 17 已有显式路径，PSTN 仍依赖目标音频栈

**已证。** Android 17 AudioManager 有两个直接对应需求的 API：上行注入 `getCallUplinkInjectionAudioTrack` 与下行抽取 `getCallDownlinkExtractionAudioRecord`。它们检查 PCM 格式/采样率/声道、当前 call/communication 模式；无相应模式时抛异常；PSTN 模式下若 `isPstnCallAudioInterceptable` 为 false 则拒绝构造。AudioService 的该查询（7738–7757）要求 `CALL_AUDIO_INTERCEPTION`，并检查是否同时枚举到 `DEVICE_OUT_TELEPHONY_TX` 与 `DEVICE_IN_TELEPHONY_RX`。Shell Manifest 有该权限。[A1]、[A2]、[I1]

**已证。** native AudioPolicyService 对 call-redirection/VOICE_DOWNLINK 等路径继续检查 `CALL_AUDIO_INTERCEPTION`，部分 telephony 路径还有 `MODIFY_PHONE_STATE`，不是 Java 接口返回对象就没有后续检查。AOSP CTS 的 CallAudioInterceptionTest 采用 shell 权限并测试构造路径，而且仅在 PSTN interceptable 时跑相应成功分支。这支持权限链存在，也恰好说明设备音频能力是条件。[A3]、[A4]

**工程推论。** PSTN TX/RX 设备暴露、AudioPolicy/HAL/基带实际通路由厂商设备实现决定；“Android 17”本身不能保证两路真实声音可用。VoIP 分支也不证明每个 App 的私有采集、通信模式、路由与音频焦点都会兼容。必须验证通话双方实际可听见、蓝牙切换/通话结束可恢复、设备端不发生额外本地回放或双重拾音。不能把系统普通扬声器播放当作上行注入成功。

**工程推论。** scrcpy 已有的音频流是目标向主控的媒体链路，没有主控麦克风回传到目标通话上行的协议；需独立扩展双向音频传输、目标 API 适配与生命周期。主控 App 的麦克风权限、后台运行与蓝牙路由是另一侧普通 App 的要求，不需要主控 ADB。Android 11 对照文件没有上述现代三个 API，本轮没有找到足以确认同等能力的旧版可用链路；应标未证，不能宣称所有 Android 11+ 都有完整免 root 通话音频。[A1]、[V11A]；媒体协议边界见 [既有媒体报告](scrcpy-media-and-server.md)。

## 需 POC：工程验证清单，不交给用户证明技术能力

1. **身份与权限链**：记录目标 build/SDK、进程真实 UID/SELinux domain、shell 实际 permission/AppOps；对包名正确/错误做可控对照，确认 callback 与 AttributionSource 能工作。源码签名/权限与 ROM 实际值分别记录。
2. **通知链路**：临时 JAR 注册 Binder、listener-connected 后快照、实时更新/移除、清除可清/不可清通知；更换用户、应用锁/OTP、断开重连、进程死亡清理；分别验证原 PI 点击和可回复/不可回复 action、immutable/cancelled PI、锁屏与应用认证，不误报消息送达。
3. **SMS 数据服务研究已归档，不执行**：保留上述源码事实，不为本产品读取短信数据库、修改 SMS AppOps 或写库。短信只保留通知动作与原应用接续；其验证并入通知链路。此前写库实验没有执行，不再生成相应实施任务。
4. **电话与双向音频分开验收**：PSTN 拨号/接听/挂断/多通话；再测 interceptable、真实下行/上行、VoIP 指定应用、蓝牙/有线/扬声器、音频焦点、主控休眠、目标屏幕关闭、ADB 断开与重新接入。API 构造成功不能替代双方听音及路由恢复的证据。

## 会影响产品契约的设计点

以下保留研究时识别的设计点，不是等待用户逐项回答的问卷。用户随后在 Q35 明确授权代理自行取舍常规功能；后续由产品规格给出默认，并通过 POC 检查，只有现有授权未覆盖的实质取舍才需要重新沟通。既有编辑回写、相册与内容接续问题不重复。

- **通知的“处理完成”具体同步什么？** 本地主控隐藏、目标通知消除、原应用消息已读是三个结果；前提是目标 action/清除能力的真实回执可区分。
- **锁屏、应用锁和需要认证的通知动作如何交还用户？** 前提是尊重目标应用认证边界；决定在目标解锁后继续、引导到目标界面，还是让这次动作失败，而非承诺后台必达。
- **短信写回分支已关闭：**不调整相关 AppOps，不再将该问题列为待问或待实现。
- **一次原通知快捷回复失去回执时，用户看到什么状态、何时允许再次发送？** 前提是系统通常不能给出第三方服务已送达确认；产品要区分未发送、提交中、结果未知与可重试，不把超时当作明确失败。
- **多个目标同时来电时，哪台获得主控麦克风与耳机？** 前提是每台目标控制可分别成立，而主控通常只有一套当前音频交互；还应明确切换是否保留另一通、静音还是提示人工接管。
- **某设备电话控制成功但通话音频不兼容时，如何保持完整目标可见？** 前提是 HAL/ROM 能力分级结果可靠；需要明确仍可控制、改由目标接听/输出及不可用原因的展示，不把缺失音频伪装成已接通跨端通话。

## 固定来源与复核位置

所有 Android 17 引用固定为 `android-17.0.0_r1` 对应各仓库 commit；不是把 `main` 当已发布设备行为。Android 11 对照固定 `android-11.0.0_r48`。除明确对照处，不外推 Android 5–10，也不声称已覆盖 Android 12–16 的逐版差异。

| 仓库 | Android 17 固定 commit |
| --- | --- |
| frameworks/base | `94b4c163b7dfe5ce3607f7bb8456f9573f7de57d` |
| packages/providers/TelephonyProvider | `013b803626164c026025897b7dec45521c2cccab` |
| frameworks/opt/telephony | `aef289516bea6118d88cd45c63742cd4abe2c596` |
| packages/services/Telecomm | `2353977dc28ff88d3cdc1ec636fa9c3251d2ff86` |
| system/sepolicy | `e066568e98d86db31a9346d30977f3632fa7073c` |
| frameworks/av | `475269ec44acec82792be6b01fb8e16357d4d2c8` |

- [I1] Shell Manifest：包名/sharedUserId，SMS/电话/音频/通知与 AppOps 权限；[Shell Android.bp](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/packages/Shell/Android.bp) 的 platform 签名/privileged。
- [I2] DefaultPermissionGrantPolicy：`grantPermissionsToSysComponentsAndPrivApps`、`isSysComponentOrPersistentPlatformSignedPrivApp`。
- [I3] 官方 content 命令：`resolveCallingPackage`、`getContentProviderExternal`、`AttributionSource`。
- [I4] shell.te：`app_domain(shell)` 与 service_manager 查找边界。
- [I5] app.te：`binder_use`/`binder_call` 及文件、radio 约束。
- [I6] seapp_contexts：shell UID/domain 对应约束。
- [N1] 同 [I1]，重点 `STATUS_BAR_SERVICE`、`RECEIVE_SENSITIVE_NOTIFICATIONS`、`START_ACTIVITIES_FROM_BACKGROUND`；对照 `ACCESS_NOTIFICATIONS` 未声明。
- [N2] NotificationManagerService：`registerListener`、`enforceSystemOrSystemUI`、`getActiveNotificationsFromListener`、`cancelNotificationsFromListener`、`cancelNotificationFromListenerLocked`、`isAppTrustedNotificationListenerService`、app-lock redaction。
- [N3] ManagedServices：直接 `registerSystemService(IInterface, ComponentName, int, int)` 与 `registerServiceImpl`。
- [N4] PendingIntent：`sendAndReturnResult`、`getCreatorUid`、`isImmutable`。
- [N5] PendingIntentRecord：`sendInner` 的实际 caller、immutable、creator 与后台启动分支。
- [N6] RemoteInput：`addResultsToIntent`；[Notification.Action.isAuthenticationRequired 官方说明](https://developer.android.com/reference/android/app/Notification.Action#isAuthenticationRequired())。
- [S1] TelephonyProvider Manifest：SmsProvider 的 exported/readPermission。
- [S2] SmsProvider：`setAppOps`、查询过滤、OTP、cursor notification URI 与 `notifyChange`。
- [S3] ProviderUtil：`isAccessRestricted`、`canReadRestrictedMessages`、`canReadOtpSms`。
- [S4] ContentProvider：Transport 的 `enforceWritePermission` 独立 AppOp。
- [S5] AppOpsService：`isOpAllowedForUid`、`verifyAndGetBypass`、`NON_PACKAGE_UIDS`、`setUidMode`、`setMode`。
- [S6] [AppOpsManager 的 OP_WRITE_SMS 默认模式](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/app/AppOpsManager.java#3122)；SmsApplication 的特殊系统包/UID 授权与默认短信应用 AppOps。
- [S7] SmsPermissions：`checkCallingCanSendText`、`checkCallingCanSendSms`。
- [S8] SmsController：`sendTextForSubscriber` 与订阅/用户检查。
- [C1] TelephonyRegistry：`listenWithEventList`、`listen`、`checkListenerPermission`。
- [C2] TelecomServiceImpl：`getCallStateUsingPackage`、`placeCall`、`endCall`、`acceptRingingCall`、`enforceAnswerCallPermission`、`enforceCallingPackage`、`endCallInternal`。
- [C3] Android 11 TelecomServiceImpl：相同接听/挂断权限链对照。
- [A1] AudioManager：`isPstnCallAudioInterceptable`、`getCallRedirectMode`、`checkCallRedirectionFormat`、两个 uplink/downlink 构造 API。
- [A2] AudioService：`isPstnCallAudioInterceptable` 与 telephony TX/RX 设备枚举。
- [A3] AudioPolicyInterfaceImpl：call redirection、telephony TX 与 VOICE_DOWNLINK 权限分支。
- [A4] CTS CallAudioInterceptionTest：shell 采用权限、模式与 interceptable 前提；测试证明范围不等于真实通话端到端质量。
- [V11] Android 11 NotificationManagerService：listener 注册链；[Android 11 Shell Manifest](https://android.googlesource.com/platform/frameworks/base/+/1d9b9ab57d844b18b3b1b4297725141e7788109b/packages/Shell/AndroidManifest.xml) 的 `STATUS_BAR_SERVICE` 声明对照。
- [V11A] Android 11 AudioManager：本轮未发现上述三个现代 API；仅作存在性差异证据。

[I1]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/packages/Shell/AndroidManifest.xml
[I2]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/services/core/java/com/android/server/pm/permission/DefaultPermissionGrantPolicy.java
[I3]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/cmds/content/src/com/android/commands/content/Content.java
[I4]: https://android.googlesource.com/platform/system/sepolicy/+/e066568e98d86db31a9346d30977f3632fa7073c/private/shell.te
[I5]: https://android.googlesource.com/platform/system/sepolicy/+/e066568e98d86db31a9346d30977f3632fa7073c/private/app.te
[I6]: https://android.googlesource.com/platform/system/sepolicy/+/e066568e98d86db31a9346d30977f3632fa7073c/private/seapp_contexts
[N1]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/packages/Shell/AndroidManifest.xml
[N2]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/services/core/java/com/android/server/notification/NotificationManagerService.java
[N3]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/services/core/java/com/android/server/notification/ManagedServices.java
[N4]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/app/PendingIntent.java
[N5]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/services/core/java/com/android/server/am/PendingIntentRecord.java
[N6]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/app/RemoteInput.java
[S1]: https://android.googlesource.com/platform/packages/providers/TelephonyProvider/+/013b803626164c026025897b7dec45521c2cccab/AndroidManifest.xml
[S2]: https://android.googlesource.com/platform/packages/providers/TelephonyProvider/+/013b803626164c026025897b7dec45521c2cccab/src/com/android/providers/telephony/SmsProvider.java
[S3]: https://android.googlesource.com/platform/packages/providers/TelephonyProvider/+/013b803626164c026025897b7dec45521c2cccab/src/com/android/providers/telephony/ProviderUtil.java
[S4]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/content/ContentProvider.java
[S5]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/services/core/java/com/android/server/appop/AppOpsService.java
[S6]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/telephony/common/com/android/internal/telephony/SmsApplication.java
[S7]: https://android.googlesource.com/platform/frameworks/opt/telephony/+/aef289516bea6118d88cd45c63742cd4abe2c596/src/java/com/android/internal/telephony/SmsPermissions.java
[S8]: https://android.googlesource.com/platform/frameworks/opt/telephony/+/aef289516bea6118d88cd45c63742cd4abe2c596/src/java/com/android/internal/telephony/SmsController.java
[C1]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/services/core/java/com/android/server/TelephonyRegistry.java
[C2]: https://android.googlesource.com/platform/packages/services/Telecomm/+/2353977dc28ff88d3cdc1ec636fa9c3251d2ff86/src/com/android/server/telecom/TelecomServiceImpl.java
[C3]: https://android.googlesource.com/platform/packages/services/Telecomm/+/refs/tags/android-11.0.0_r48/src/com/android/server/telecom/TelecomServiceImpl.java
[A1]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/media/java/android/media/AudioManager.java
[A2]: https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/services/core/java/com/android/server/audio/AudioService.java
[A3]: https://android.googlesource.com/platform/frameworks/av/+/475269ec44acec82792be6b01fb8e16357d4d2c8/services/audiopolicy/service/AudioPolicyInterfaceImpl.cpp
[A4]: https://android.googlesource.com/platform/cts/+/refs/tags/android-17.0.0_r1/tests/tests/media/audio/src/android/media/audio/cts/CallAudioInterceptionTest.java
[V11]: https://android.googlesource.com/platform/frameworks/base/+/1d9b9ab57d844b18b3b1b4297725141e7788109b/services/core/java/com/android/server/notification/NotificationManagerService.java
[V11A]: https://android.googlesource.com/platform/frameworks/base/+/1d9b9ab57d844b18b3b1b4297725141e7788109b/media/java/android/media/AudioManager.java
