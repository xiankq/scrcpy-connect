# CallStyle 原通知动作与具体通话目标隔离

研究日期：2026-10-17。固定源码版本：AOSP `android-11.0.0_r1`、`android-16.0.0_r1`；开发者文档用于 API 契约对照。仅作只读源码调查，没有改变被控设备状态，没有新增通话控制实现或运行来电实验。

## 结论与实施边界

**CallStyle 的 typed answer / decline / hang-up PendingIntent 可以识别发布者提供的动作角色，但不能证明动作绑定用户所见的具体通话。** Framework 不给这些 PI 添加通话 identity 或目标校验。更直接的反例是固定 Android 11、16 AOSP Dialer：PI 本身没有 callId，receiver 到执行时才选择当前来电或当前活动通话。因此当前 `canAnswer/canReject/canHangup=false` 不能仅因发现这些 extras 而解锁。[Framework CallStyle](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/java/android/app/Notification.java#10949)、[Android 16 Dialer receiver](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-16.0.0_r1/java/com/android/incallui/NotificationBroadcastReceiver.java#140)

这不是“Android 不支持通话控制”的结论。它说明本项目尚未证明通用、逐通话且拒绝旧动作的控制契约。某个发布者若确实提供不可复用的通话 identity，并在接收方执行时校验该 identity，仍可独立验证其动作。AOSP Dialer 的结论也不能直接套用到未审计的 Google Dialer、厂商拨号器或 VoIP 应用。保留实时通话观察和原应用接续，符合免 APK ADR 对实际设备验证的要求。[免安装约束](../adr/0001-apk-free-controlled-device.md)

## Framework 提供了什么

Android 12 / API 31 起提供 `Notification.CallStyle` 和三个 PI extras：`android.answerIntent`、`android.declineIntent`、`android.hangUpIntent`。固定 Android 16 源码的构造函数保存调用方 PI，`addExtras` 序列化相同引用，系统按钮继续使用这些 PI；没有新增每通话调用接口。Android 11 Framework 没有 CallStyle 或这三个常量，因此不能把 API 31 的模板当成 Android 11 原生通知必备字段。也不能凭本地化按钮文字推断某个普通 Action 就有安全逐通话语义。[Android 16 构造与 extras](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/java/android/app/Notification.java#10949)、[生成按钮](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/java/android/app/Notification.java#11119)、[Android 11 Notification](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-11.0.0_r1/core/java/android/app/Notification.java)、[API 版本契约](https://developer.android.com/reference/android/app/Notification.CallStyle)

## AOSP Dialer：旧 PI 可以命中新通话

| 行为 | Android 11 固定源码 | Android 16 固定源码 |
| --- | --- | --- |
| 创建通知动作 PI | [StatusBarNotifier.java:172](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-11.0.0_r1/java/com/android/incallui/StatusBarNotifier.java#172) | [StatusBarNotifier.java:176](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-16.0.0_r1/java/com/android/incallui/StatusBarNotifier.java#176) |
| 执行时选择接听目标 | [NotificationBroadcastReceiver.java:167](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-11.0.0_r1/java/com/android/incallui/NotificationBroadcastReceiver.java#167) | [NotificationBroadcastReceiver.java:171](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-16.0.0_r1/java/com/android/incallui/NotificationBroadcastReceiver.java#171) |
| 执行时选择拒接目标 | [同文件:211](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-11.0.0_r1/java/com/android/incallui/NotificationBroadcastReceiver.java#211) | [同文件:215](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-16.0.0_r1/java/com/android/incallui/NotificationBroadcastReceiver.java#215) |
| 执行时选择挂断目标 | [同文件:136](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-11.0.0_r1/java/com/android/incallui/NotificationBroadcastReceiver.java#136) | [同文件:140](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-16.0.0_r1/java/com/android/incallui/NotificationBroadcastReceiver.java#140) |
| 更新同一个通知 ID | [StatusBarNotifier.java:430](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-11.0.0_r1/java/com/android/incallui/StatusBarNotifier.java#430) | [StatusBarNotifier.java:434](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-16.0.0_r1/java/com/android/incallui/StatusBarNotifier.java#434) |

两版 PI factory 都采用显式 receiver、按动作区分的 Intent、requestCode 0、flags 0，没有每通话 callId、唯一 data 或每通话 requestCode。接听、拒接 receiver 查询 `CallList.getIncomingCall()`；挂断先选 outgoing，之后选 active/background。接收方没有校验主控所见通知 revision。固定 Android 16 的此 AOSP Dialer 仍使用普通通知 Actions，不能假设新版系统所有电话通知必为 CallStyle。[Android 11 动作构建](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-11.0.0_r1/java/com/android/incallui/StatusBarNotifier.java#443)、[Android 16 动作构建](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/tags/android-16.0.0_r1/java/com/android/incallui/StatusBarNotifier.java#447)

**工程推论：** A 来电显示后用户提交旧按钮；主控发送前仍可能观察到 A，但 A 在 receiver 运行前结束，B 成为当前来电，旧 PI 就可能作用于 B。通知 key、修订号、PI token identity、主控生成的 episode UUID 都不能补足 receiver 缺少目标身份的问题。这里甚至不需要 PI extras 被更新。

为便于复查，Gitiles 目录报告的 blob 如下；两版不是同一文件 blob，只是上述关键逻辑一致。

| 文件 | Android 11 blob | Android 16 blob |
| --- | --- | --- |
| StatusBarNotifier.java | `99ff7255eae88386ec51aa106724105e5ffc0c28` | `39428512b72a368cbb8da118a97ec92600517f25` |
| NotificationBroadcastReceiver.java | `241d8ed4840038a463c290c33935df2e31c8e1b6` | `91421ea1bc96c2ea3e846d66b32058583aaae037` |

## PendingIntent 的失效、更新与结果

PI identity 不包含仅在 Intent extras 中变化的内容；`FLAG_UPDATE_CURRENT` 可以让旧持有者发送创建方更新后的 extras，`FLAG_IMMUTABLE` 也不会阻止创建方更新。因此 immutable 不等于“永远绑定原通话”。`FLAG_CANCEL_CURRENT` 则取消旧 token 后创建新的 token，不是把旧引用转到新 token；`FLAG_ONE_SHOT` 限制发送次数，也不能证明接收方会选原目标。[固定 Android 16 PI 契约](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/java/android/app/PendingIntent.java#98)、[创建方更新实现](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/services/core/java/com/android/server/am/PendingIntentController.java#152)、[one-shot 与 immutable 执行实现](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/services/core/java/com/android/server/am/PendingIntentRecord.java#480)

通知撤回和 PI 创建方取消应分别处理，不能只凭通知消失推断所有外部 PI 引用已经被系统取消。应用进程结束也不自然使 PI token 失效。`send` 正常返回至多报告系统已接受分发请求；receiver 可以发现没有可操作 call 后不执行。`OnFinished` 是发送/广播完成通知，不是统一的“原电话已接听”回执。[官方 PI 生命周期](https://developer.android.com/reference/android/app/PendingIntent)、[固定 send 与 OnFinished 实现](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/java/android/app/PendingIntent.java#323)

Telecom 还有一条专用于 self-managed 来电与其他 ConnectionService 通话并存时的通知路径。Android 16 给它的 PI 加了 cancel-current 与 immutable，但 receiver 仍在执行时读取 notifier 当前 incoming call；不能用这一局部 UX 证明所有电话通知安全，也不能把 cancel-current 当成每 call 对象绑定。[通知器与状态更新](https://android.googlesource.com/platform/packages/services/Telecomm/+/refs/tags/android-16.0.0_r1/src/com/android/server/telecom/ui/IncomingCallNotifier.java#159)、[PI 创建](https://android.googlesource.com/platform/packages/services/Telecomm/+/refs/tags/android-16.0.0_r1/src/com/android/server/telecom/ui/IncomingCallNotifier.java#214)、[receiver 选目标](https://android.googlesource.com/platform/packages/services/Telecomm/+/refs/tags/android-16.0.0_r1/src/com/android/server/telecom/TelecomBroadcastIntentProcessor.java#181)

## 锁屏与调用身份

原 PI 授予按创建方身份执行所指定操作的能力，不授予通用 Telecom 权限，也不是允许绕过原动作认证策略的证明。API 31 Action 的 `isAuthenticationRequired` 要求系统解锁后执行。固定 Android 16 SystemUI 会把该元数据传给回调，并对 activity 或需要认证的动作先走 keyguard；直接由 shell 调用 PI 不经过这段 SystemUI 回调。因此未来即使有目标隔离可靠的发布者，也应在被控设备锁屏、用户/profile 无法核实、原动作要求认证或相关策略未知时拒绝远程发送，交回原应用。不要把一次 `isDeviceLocked=false` 查询当成与后续 send 原子联动的保证。[Action 契约](https://developer.android.com/reference/android/app/Notification.Action#isAuthenticationRequired())、[SystemUI 读取原 Action](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/packages/SystemUI/src/com/android/systemui/statusbar/NotificationRemoteInputManager.java#162)、[SystemUI keyguard 路径](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/packages/SystemUI/src/com/android/systemui/statusbar/phone/StatusBarRemoteInputCallback.java#327)

## 可继续实施的明确条件

下列是后续实施与验收条件，尚未完成，不代表已有能力：

- 可先只读提取 CallStyle 的角色与原 PI 可用性；将其视为 notification action 候选，不能直接关联到聚合 telephony episode，或仅按名称、号码匹配通话对象。
- 逐发布者核查接收方：不可复用的 call identity 进入 PI 的不可被其他 call 改写的身份；执行时按原 identity 找对象、校验状态，消失时拒绝，绝不回退当前 call。仅检查 creator package、签名、immutable 或 PI 相等不充分。
- 如将来通过验证，对外操作引用至少含设备、helper generation、用户、通知 key/revision、动作角色；断线、撤回、替换、helper 重启即失效。发送前重取实时通知可减少陈旧操作，但不能代替发布者的执行时目标校验。
- 显式区分 `systemAccepted`、`expired`、`authenticationRequired`、`resultUnknown` 与有独立具体 call 证据的实际结果。超时或断线后不自动重发破坏性动作。
- 必须验证 rapid A 结束/B 到达、来电等待、多 SIM、多通知、通知更新复用 token、取消 token、锁屏、profile 切换和 receiver 延迟。测试应直接证明旧动作不会作用于 B；仅看到旧通知 key 被拒绝不足以覆盖分发后的竞态。

本次没有给任何发布者建立可安全解锁逐通话按钮的白名单，也没有把原通知可发送误报为通话控制已完成。临时 JAR、Rust core 和 UI 均保持当前实现。
