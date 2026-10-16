# 临时 Android Binder companion

实现源码位于 `src/com/interop/companion/Main.java`，Rust 编排位于
`crates/interop_core/src/companion.rs`。它是经已授权 ADB 推送的临时 DEX JAR，
以实际 shell UID 2000 运行；不安装 APK、不请求 root、不授予通知 listener
组件权限、不修改 AppOps，也不访问短信数据库。主控本身不需要开启调试。

本记录核实于 2026-10-17。源码依据固定为 AOSP `android-16.0.0_r1`，
frameworks/base commit `99b01a65cc4c104933788b3143285ab6bae65827`。
Android 11 对照和更广泛权限研究见
[`android-shell-interop-capabilities.md`](../../docs/research/android-shell-interop-capabilities.md)。
源码路径可行、实际运行通过、跨 ROM 支持是三个不同结论。

## 已实现的路径

通知通过动态 `INotificationListener` Binder 注册。AOSP
[`registerListener`](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/services/core/java/com/android/server/notification/NotificationManagerService.java#5629)
检查 `STATUS_BAR_SERVICE`，并将调用 UID 与 Binder 直接注册到系统服务；
[`Shell Manifest`](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/packages/Shell/AndroidManifest.xml#299)
声明该权限。该路径没有安装额外 NotificationListenerService APK。

当前快照和清除使用注册 Binder token，分别调用
[`getActiveNotificationsFromListener` 和 `cancelNotificationsFromListener`](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/core/java/android/app/INotificationManager.aidl#152)。
实时变化由 Binder callback 触发快照对账，没有 dumpsys 轮询或历史通知数据库。
服务重新启动、通知更新或移除后，原动作引用会失效。

打开使用原通知的 `contentIntent`，回复使用原 action 的 `RemoteInput`
result key 和原 `PendingIntent`。仅有 mutable/free-form 原动作时返回
`canReply=true`。`PendingIntent.send` 使用真实已安装 `com.android.shell`
PackageContext，且校验 context 的包名与 UID 2000 归因；没有冒充 `android`
包。锁屏和 action 的认证要求会阻止后台发送，不绕过目标应用认证。
[RemoteInput 官方 API](https://developer.android.com/reference/android/app/RemoteInput#addResultsToIntent(android.app.RemoteInput%5B%5D,android.content.Intent,android.os.Bundle))、
[原 action 的认证标记](https://developer.android.com/reference/android/app/Notification.Action#isAuthenticationRequired())
是填充内容和认证边界的依据。

回复回执是 `status=acceptedBySystem, acceptedBySystem=true, delivered=null`。
这只表示系统接受原动作，无法确认应用处理或消息服务送达；超时返回
`result_unknown`，不自动重发，草稿由主控界面保留。
清除单独返回 `dismissed` 和 `markedRead=false`，不把移除通知说成消息已读。

通话状态通过真实 shell 包归因注册
[`ITelephonyRegistry.listenWithEventList`](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/core/java/com/android/internal/telephony/ITelephonyRegistry.aidl#54)
回调，读取
[`ITelecomService.getCallStateUsingPackage`](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/telecomm/java/com/android/internal/telecom/ITelecomService.aidl#224)
的系统聚合状态。原始已交付 call-state 转换会先更新 observation generation，
再合并快照工作。系统聚合 API 和异步回调没有提供完整、原子的逐通话对象，
本地 generation 不能补出未交付的转换，也不能保证观察引用唯一对应一次通话。
这些 ID 是观察引用，`aggregate=true`，并非 Telecom 的具体 call 对象。

**产品没有开放全局接听、拒接或挂断。** 同一 AIDL 的 `endCall` 和
`acceptRingingCall` 不接受具体 call ID；先核对状态再执行仍存在两次 Binder
调用间的替换竞争。观察 UUID 和 generation 不能解决这个原子性问题。
所有 `calls.action` 返回 `call_targeting_unavailable`，三个危险按钮能力均为
false，`controlStatus=limited`，引导到手机原电话应用。这是尚未实现安全定位，
不代表设备系统不支持通话。具体通话／SIM、等待来电、第三方 VoIP 和双向
通话音频仍未完成；音频始终 `audioStatus=unknown`。

## 无控制会话的剪贴板

用户首次请求 `clipboard.get/set` 时才初始化 `IClipboard` 并注册
`IOnPrimaryClipChangedListener`；通知服务单独启动不自动读取剪贴板。
Rust 优先复用已有 scrcpy 控制通道，无控制会话时走同一认证 companion，
不启动视频、不安装 APK、不要求普通 Android 主控在后台获得读取权限。

所有 Binder 调用归因真实 `com.android.shell`、实际 UID 2000、当前用户和默认
设备 ID 0，不构造 `android` 包身份。固定 AOSP
[`IClipboard`](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/core/java/android/content/IClipboard.aidl)
定义带包名、attribution tag、用户与设备 ID 的签名；兼容的旧签名按实际
参数类型选择，未知签名返回 `clipboard_api_unavailable`。
[`Shell Manifest`](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/packages/Shell/AndroidManifest.xml#341)
声明 `READ_CLIPBOARD_IN_BACKGROUND`；
[`ClipboardService`](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/services/core/java/com/android/server/clipboard/ClipboardService.java#1301)
仍校验包归属、AppOps、焦点／后台读取权限；读取还受设备锁定限制。
产品检查真实权限、AppOps 和 Keyguard，不修改它们，也不解锁或点亮屏幕。

`get` 返回 `{text, hasText, available:true, live:true, source:"companion"}`；
只读取第一项已存在的文本，不将 URI 或 Intent 转成文本、不访问其内容提供方。
非文本返回 `clipboard_not_text`，设备锁定返回 `clipboard_locked`，权限拒绝
返回 `permission_denied`。`set` 写入普通文本并读回核对后才返回
`{applied:true, source:"companion"}`；系统静默拒绝或期间内容被替换不会伪报成功。
结果未知的写入不会自动重试。

文字 UTF-8 上限 262130 字节，JSON 转义后还须容纳在 1 MiB 消息边界内；
超限拒绝，不截断剪贴板。实时 `clipboard.changed` 与 get 使用同一数据结构，
由原生 Binder callback 触发，不轮询。读取变化受限时单独发
`clipboard.unavailable`，不终止通知服务。断开会注销 listener 并清除临时进程。
内容仅在当前 RPC、内存与实时事件里传输，不写日志或持久化存储。

实际 API 36 AVD 已通过：无视频 session 的 Unicode／换行／引号文本往返，
第二个独立 companion 写入触发第一个实例实时事件，启动期间断开取消，
以及断开后的读取拒绝。旧 Android 签名、OEM、锁屏及多用户矩阵尚未运行验证。

## 目标端媒体缩略图

`media.stat` 和 `media.thumbnail` 使用独立的有界媒体队列：一个正在运行的
解码进程、一个排队项。每次通过 `ProcessBuilder` 启动同 JAR 的独立 shell
`app_process` 子进程，不经过 shell 拼接。通知、通话和剪贴板的原队列保持独立。
子进程只返回最大 256 KiB 的 JPEG（64–512 像素，默认 256），不把原图或视频
传回主控，不授予额外权限。图片先解析尺寸并按 `inSampleSize` 解码，处理全部
八种 EXIF 方向；视频用 `MediaDataSource` + `getScaledFrameAtTime`，保留平台已
应用的视频旋转。图片像素上限 100 MP、输入 256 MiB；视频输入上限 64 GiB。

打开源文件使用 `O_NOFOLLOW`，拒绝末端符号链接和非普通文件。解码前后核对
打开的描述符和当前路径的 dev/inode/mode/size/mtime/ctime；纳秒字段只在平台
真实提供时使用，不声称文件系统具备纳秒精度。Rust 再核对源戳、JPEG 摘要和
尺寸，缓存只含小 JPEG 及元数据；每次缓存命中仍校验目标源戳。

媒体操作使用一次性 UUID；取消和完成后不能复用。关闭 stdin 会由子进程独立
监视线程杀死自身，8 秒独立 watchdog 限制 native 解码，父进程确认退出并回收
后才回报取消；无法确认则返回 `media_cleanup_unknown`。不会按过期的数字 PID
杀进程。Android <26 的有界进程生命周期、Android 26 的有界视频取帧尚未实现，
返回 `thumbnail_api_pending`，不伪称系统不支持。OOM、损坏、无帧、权限拒绝和
源变化均显式失败，不自动下载原件补救。详细边界和实测见
[媒体缩略图管线](../../docs/research/media-thumbnail-pipeline.md)。

## 协议与生命周期

- 随机 abstract socket 名加 256 位随机认证 token；token 不落盘、不写日志。
- 协议版本 1，UTF-8 JSON line，请求带 `requestId`；响应或实时 event 独立传输。
- 单消息上限 1 MiB，通知快照控制在 768 KiB；截断返回 `truncated=true`
  和受限说明。正文为有界纯文本，完整内容交回原应用。
- `notificationId` 是当前进程和修订绑定的不透明引用；不能按包名、标题或地址替换。
- 通知内容、原 PendingIntent、回复草稿和当前通话仅留内存，没有长期归档。
- Rust 独立序列化每台设备的启动；共享设备表不跨网络 await。
  `device_operations["companion:<deviceId>"]` 可在启动中取消，保存连接前再核对状态。
- 关闭 socket 后 JAR 注销监听并退出；启动未连接有 20 秒期限。
  Rust 保持进程 shell stream、等待退出并删除本次临时 JAR。断开后不返回旧通知快照。
- 产品代码完全使用 Rust ADB host；官方 `adb` 仅存在于 opt-in 测试 harness。

## 构建与验证

`build.sh` 使用现有 Java 21、Android SDK 36 和 build-tools 36.0.0 的 javac/d8，
输出固定 ZIP 时间戳的 `companion.jar`；不联网安装工具。Rust 内嵌 JAR 并校验
SHA-256；修改源码后需重新构建并同步 `SERVER_SHA`。测试 Fixture 不编入产品 JAR。
当前产品 JAR 的 SHA-256 为
`719e57e3317d91d0858aa722f86770275d3af6130ad2ff0cd4334a5f7722b828`。

```sh
bash servers/companion/build.sh
bash servers/companion/tests/build-fixture.sh
python3 servers/companion/tests/android-probe.py \
  --adb "$ANDROID_ADB" --serial emulator-5556 --calls --skip-receiver

INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 \
ANDROID_ADB="$ANDROID_ADB" ANDROID_TARGET_SERIAL=emulator-5556 \
cargo test -p interop-core --test companion_android -- --ignored --nocapture --test-threads=1

INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 \
cargo test -p interop-core --test companion_clipboard -- --ignored --nocapture --test-threads=1
```

实际目标是 API 36 / Android 16，fingerprint：
`google/sdk_gphone64_x86_64/emu64xa:16/BE2A.250530.026.F3/13894323:userdebug/dev-keys`。
只有 target `emulator-5556` 被操作；没有操作主控 AVD、安装 APK、改权限或 AppOps。

真实证据包括：UID 2000、通知 listener 注册和实时 Binder 事件、原 PI 打开
Settings、原通知更新后的旧引用拒绝、实际远端清除、immutable 无回复能力、
认证 action 拒绝、已取消 PI 拒绝、启动中断开不复活，以及虚拟 modem 的来电状态。
快速结束来电再产生新来电的回归要求旧动作不能结束新来电，并通过真实 Telecom
状态确认仍 ringing、测试结束后恢复 idle；产品全局动作始终拒绝。测试 harness
仅通过官方 dumpsys 等待 modem 完成取消，再发起下一通，不在间隔调用 Rust 刷新。
此 AVD 在取消后立即发起下一通时会返回 OK，但 Telecom 可能拒绝创建新来电，
因此这种早期尝试不作为真实替换证据。观察引用始终不当作安全通话引用。

`--skip-receiver` 是明确未证项：RemoteInput 原动作已由系统接受，但无 APK 的
测试动态广播 receiver 没有确认收到，不能声称应用送达。取消该参数会执行这条
当前未通过的更强断言。真实第三方消息应用的接收／认证／锁屏与 ROM 矩阵尚未验证。

此前实验曾以虚拟 modem 验证 Telecom 全局接听／挂断 API 可以调用，并观察到
active/idle；安全审查发现它们无法可靠绑定具体通话，产品路径已删除。这段实验
只能作为底层可行性证据，不能计作安全产品通话控制通过。

还需验证系统服务重启、多用户/工作资料、真实 OEM 权限与 SELinux 差异、
敏感通知脱敏、应用认证、通知权限拒绝、平台锁屏隐私投影和长期运行资源表现。
当前声明限于上述实际 AVD，不外推所有 Android 或所有应用。
