# Flutter／Rust 主控运行时与平台边界研究

研究日期：2026-10-16。依据 Flutter、FRB、Riverpod 与平台官方文档，记录权限、资源和生命周期的独立边界。当前目录、所有权与恢复契约见[架构](../implementation/architecture.md)和[状态恢复](../implementation/state-recovery.md)；下面的版本快照及验证方法不承担当前支持矩阵。

## 先确定哪些边界不能混在一起

| 边界 | 已核实的结论 | 产品影响 |
| --- | --- | --- |
| 主控系统版本／被控系统版本 | 研究时 Flutter 3.47 主控 Android 支持 API 24–37；scrcpy 被控端基础要求 API 21，音频转发 API 30+ | 「控制 Android 5.0+」不等于「主控 App 能装 Android 5.0」；各能力仍需另报支持范围 |
| Android 进程／Flutter engine／Dart isolate／页面 | 生命周期彼此不同，页面 dispose 也不是用户断开连接 | 会话不能绑定页面或单个 provider 的存活 |
| 本机捕屏／接收远端视频 | MediaProjection 管主控本机屏幕捕获；远端 shell/JAR 发送的视频不是主控的 MediaProjection 会话 | 不能为了常驻而声明与实际工作不匹配的 mediaProjection FGS |
| Android 公共平台 API／AOSP 内部实现 | AOSP 有代码不代表第三方 App 有调用权限和稳定 ABI | Rust 核心仍需要平台适配；「Rust 全包」不能意味着绕开权限与生命周期 |
| 可读路径／可写路径／SAF URI | 三者的访问范围与操作能力不同 | 文件管理必须呈现实际能力，而非把目录列表当全盘写权限 |

来源：[Flutter 平台支持矩阵](https://docs.flutter.dev/reference/supported-platforms)、[scrcpy prerequisites](https://github.com/Genymobile/scrcpy#prerequisites)、[Flutter 生命周期](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html)、[Android NDK 公共 API](https://developer.android.com/ndk/guides/stable_apis)。

## Android 主控后台：保持会话是一项平台功能

### FGS 的用途和版本限制

**事实。** target API 31+ 原则上禁止应用从后台启动 FGS，只有规定的例外；target 34+ 必须声明实际使用的服务类型和对应权限。不要把「已经从前台合法启动，随后进入后台」与「断线以后在后台新启动服务」当成同一条件。[FGS 启动限制](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)、[版本变更](https://developer.android.com/develop/background-work/services/fgs/changes)。

| 工作 | 平台文档与适用判断 |
| --- | --- |
| 外部 Android 设备的 USB／网络连接 | **事实：** `connectedDevice` 覆盖外设 USB／网络交互，要求满足列举的网络权限、蓝牙等运行时权限或调用 `UsbManager.requestPermission()` 等先决条件之一。**推论：** 它是本产品持续设备连接的主要候选，但必须在实际用途和发布渠道审核下验证，不能把它当任意后台任务的通行证 |
| 主控自身屏幕投射 | **事实：** `mediaProjection` 需要主控先经 `createScreenCaptureIntent()` 获取用户捕屏授权。**结论：** 仅接收被控端视频不建立这种会话；远端如何捕屏由被控端方案研究负责 |
| 有限的文件同步／导入导出 | **事实：** `dataSync` 覆盖数据传输等工作。**推论：** 可以作为独立工作类别评估，不能用来承诺永久连接 |
| 通知事件转发 | **事实：** `remoteMessaging` 的说明是设备间文本消息连续性。**推论：** 任意通知镜像不能未经论证就归为该类型 |

上述类型定义与前置条件见 [Android FGS service types](https://developer.android.com/develop/background-work/services/fgs/service-types)。同一服务若使用多个类型，要同时满足所有所选类型的限制。

**事实。** target 35+ 时，应用在后台的 `dataSync`、`mediaProcessing` 各有每 24 小时共计 6 小时配额；到期收到 `onTimeout` 后须及时停止。target 35+ 的 `BOOT_COMPLETED` 不能启动包括 dataSync、mediaPlayback、mediaProjection 在内的列举类型。Android 16 起，FGS 内启动的 JobScheduler／WorkManager／DownloadManager 工作也遵守各自任务配额；这不是 Tokio socket 被直接套上 JobScheduler 配额。[FGS timeout](https://developer.android.com/develop/background-work/services/fgs/timeout)、[FGS 版本变更](https://developer.android.com/develop/background-work/services/fgs/changes)、[各类型 BOOT 限制](https://developer.android.com/develop/background-work/services/fgs/service-types)。

**事实边界。** 截至研究日，Android 官方 FGS 变更页列到 Android 16，没有给出「Android 17 的所有 connectedDevice 行为都不变」这种保证；Android 17 新的本地网络权限另见下节。需要 target 37 真机覆盖，不能从变更页未列出推导永久兼容。

### Doze、用户停止、进程死亡与重启

**事实。** Doze 可挂起网络并忽略普通 wake lock；电池优化豁免能解除部分网络／唤醒限制，但不解除所有系统约束。FGS 可避免部分 App Standby 条件，不能据此笼统承诺消灭 Doze。Android 13+ 的任务管理器 Stop 会移除整个 App 进程，并且不给应用停止回调；Flutter 同样明确生命周期通知可能被跳过。[Doze 与 App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)、[用户停止 FGS](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping)、[Flutter AppLifecycleState](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html)。

**推论：** 后台契约至少拆成以下状态，UI 必须知道实际是哪一种：

- **运行中，UI 离开：** 平台 Service 拥有后台执行资格；Rust 会话继续；Flutter 渲染资源按策略释放或降级。
- **网络暂断／Doze：** 会话保留用户意图与重连预算，不能显示「仍在线」掩盖不可达；恢复时重新验证连接与远端状态。
- **系统回收进程：** socket、Tokio task、USB fd、texture、FRB channel 全部已失效；恢复只能从持久化意图建立新资源。
- **用户明确停止／force-stop：** 尊重停止意图，不以 watchdog 立即拉起。任务管理器 Stop 与设置中的 Force stop 机制也应分别测，不能统称「划掉后台」。
- **主控重启：** BOOT receiver 只是受限制的入口，不是恢复成功保证。USB 权限、设备是否插着、解锁前存储可用性、远端授权、网络权限与可达性都必须重新检查。

**POC R1：** 在 AOSP／Pixel 和实际支持的 OEM 真机上验证：前台连接→锁屏 30 分钟／2 小时→Doze→切网→解锁、系统回收、任务管理器 Stop、设置 Force stop、双方重启。记录会话连续性、重新握手时间、功耗、错误分类；必须分别覆盖 USB 与 TCP，不能用模拟器一次成功替代后台承诺。

## Rust 与 Flutter 的存活关系

### 不把 StreamSink 当作会话本身

**事实。** Flutter `detached` 表示 engine 仍在运行但没有附着的 host view，既不是进程退出，也不是 engine 必然已销毁。FRB 非 Web 的默认异步运行时基于 Tokio；`StreamSinkBase.add_raw` 返回发送结果，Dart channel 关闭时发送会失败。FRB 文档要求每个 Dart isolate 启动／停止时执行相应 `RustLib.init()`／`dispose()`。[Flutter detached 定义](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html)、[FRB Tokio 运行时源码](https://github.com/fzyzcjy/flutter_rust_bridge/blob/master/frb_rust/src/rust_async/io.rs)、[StreamSink 源码](https://github.com/fzyzcjy/flutter_rust_bridge/blob/master/frb_rust/src/stream/stream_sink.rs)、[FRB isolates](https://cjycode.com/flutter_rust_bridge/guides/miscellaneous/isolates)。

**事实。** FRB Dart entrypoint 的 dispose 会清空该入口的 Dart state；这不是它承诺替业务关闭全局 Rust 会话管理器。RustOpaque 示例通过 Dart 对象与 Rust `Arc` 共享资源，显式 dispose 改变引用计数；资源何时真正 Drop 仍取决于其他 Rust 所有者。[入口 dispose 源码](https://github.com/fzyzcjy/flutter_rust_bridge/blob/master/frb_dart/lib/src/main_components/entrypoint.dart)、[RustOpaque 所有权说明](https://cjycode.com/flutter_rust_bridge/guides/contributing/submodules/rust-opaque)。

**推论：** 给 Rust 进程内会话管理器独立所有权，Android Service 负责建立与终止其平台运行条件；FRB 是可反复附着的客户接口。UI stream 取消只解除这个订阅。关闭会话必须是明确命令。发送错误应移除失效 subscriber，而不是停止整个设备会话，也不能无休止向旧 sink 发送。

建议桥接契约是：先 `attachClient` 分配 client generation，再返回一致快照和事件 cursor，然后订阅带序号的增量；重建 isolate 后申请新 generation，拒绝旧回调。离屏时统计等高频事件采用最新值覆盖或有界缓冲；完成、失败、权限撤销等事件须能从快照／操作记录重建。FRB 的 stream 便利接口不是持久化日志，也不是端到端背压策略。

### Native handle 和 GPU 资源不可跨重建复用

**推论：** `SessionId` 是领域身份；fd、裸指针、RustOpaque、textureId 是有生命周期的资源引用。后者不能写入持久化后恢复、不能跨进程使用、不能在 hot restart 后从旧 Dart 对象继续使用。每个 native adapter 必须定义「创建者、唯一 close 者、借用者、失效回调、generation、先停生产再释放 surface／callback」的顺序。跨 JNI 调用还需正确 attach Rust 工作线程，并用合适的全局引用代替 Activity 局部引用。

**事实／POC 边界。** hot reload 保留 Dart 状态，hot restart 重置 Dart 状态；改 native Rust／Kotlin 后需要完整重新运行构建。文档不能证明本产品的 Service、FRB、fvp、JNI 回调在 engine detach／destroy／restart 的组合下安全。[Flutter hot reload 特殊情况](https://docs.flutter.dev/tools/hot-reload#special-cases)。

**POC R2：** 多会话活动期间循环 push/pop 页面、provider invalidate、旋转、Activity 重建、engine detach／重建、hot restart；验证会话按意图继续、失效 stream 不累积、无双重 close／use-after-free、订阅重绑后状态完整。此项先于把播放器 nativeHandle 直接暴露给上层的方案。

## USB、网络权限和身份密钥的平台适配

### Android USB 可以让 Rust 承担数据面，但权限入口仍属 Android

**事实。** 无 root Android USB host 路径由 UsbManager 枚举、请求用户权限、打开 UsbDeviceConnection，再把 `getFileDescriptor()` 返回的 fd 交给 native code。官方 USB host 流程要求设备脱离时清理接口与连接。libusb 官方 Android 示例也采用 Java UsbManager→fd→`libusb_wrap_sys_device`，并提供跳过直接设备发现的选项。[USB host](https://developer.android.com/develop/connectivity/usb/host)、[UsbDeviceConnection](https://developer.android.com/reference/android/hardware/usb/UsbDeviceConnection)、[libusb Android README](https://github.com/libusb/libusb/blob/master/android/README)。

**事实。** `UsbDeviceConnection.getFileDescriptor()` 不等于向 Rust 转移所有权。`ParcelFileDescriptor.fromFd()` 会 dup，`detachFd()` 才从该 ParcelFileDescriptor 脱离 fd 并由接收者负责关闭；不能给 UsbDeviceConnection 臆造一个 detachFd 方法。libusb wrap 要求原系统 handle 在 `libusb_close()` 前保持打开，且 libusb_close 不关闭这个系统 handle。[ParcelFileDescriptor API](https://developer.android.com/reference/android/os/ParcelFileDescriptor)、[libusb wrap_sys_device 官方源码契约](https://github.com/libusb/libusb/blob/master/libusb/core.c)。

**推论：** 推荐在平台 adapter 打开后显式 dup 一个 Rust 所有的 fd，登记 USB connection generation；Rust 将其包为 RAII 资源，取消并 drain native I/O 后执行 libusb_close，再 close 自有 fd，最后释放平台 connection／interface。具体 releaseInterface 与 libusb claim 顺序必须实测；dup 共享底层设备状态，不提供独立的 USB 接口租约，也不允许一个组件继续使用已被另一个组件 reset 的设备。拔线触发的是设备失效，dup 无法挽救连接。

**POC R3：** 权限拒绝／撤销、重插、USB-C host 角色、供电／充电并行、多个设备经 hub、同设备 MTP/ADB 接口、Service 重启、取消阻塞读写。核对 fd 数和线程数，验证重复 close 与 fd 数值复用不会误伤新连接。

**结论：** Rust 可承担 ADB 协议、transport、调度和文件数据流；Android 的权限、Service、USB attachment、URI、通知、硬件密钥及渲染生命周期仍需公开平台 API。可以用 Rust JNI 调这些 API，或保留少量 Kotlin 宿主；两种实现都不等于「没有平台适配」。NDK 公共 API 清单不提供对全部 Android framework 功能的替代。[NDK stable APIs](https://developer.android.com/ndk/guides/stable_apis)。

### Android 16／17 本地网络不是仅加 INTERNET

**事实。** Android 16 的本地网络保护是兼容性测试阶段；Android 17 对 target 37+ 应用实施 `ACCESS_LOCAL_NETWORK` 运行时权限，target ≤36 仍按官方规则使用 INTERNET 隐式访问。限制涵盖本地 TCP／UDP／mDNS 等，native Rust socket 不能绕过。Android 17 提供由系统呈现的 NSD 服务选择器作为较窄授权路径。[Local network permission](https://developer.android.com/privacy-and-security/local-network-permission)。

**推论：** 多设备自动发现、手输本地 IP、长期同时连接多个设备与 NSD picker 的单设备选择流程不完全等价。主控要有统一权限状态机，让发现、配对、连接、重连在权限撤销时同步失效；拒绝后不能把 socket 错误误报成「设备离线」。手动连接跨网地址不代表其底层路由一定不是本地网络。

**POC R4：** target 37 真机对 native UDP/mDNS、系统 NsdManager、手输 IPv4／IPv6、VPN／多网卡、拒绝和系统设置撤销分别测。对系统 picker 是否能覆盖 ADB pairing/connect 两种 service 的交互单独验证，不能仅凭 NSD 支持就承诺无广域授权的完整体验。

### Keystore 需提供签名能力，不能要求导出私钥

**事实。** Android Keystore 私钥材料可保持不可导出；可以限制用途与是否要求用户认证。AOSP legacy ADB AUTH 对 token 使用 RSA/SHA-1 形式签名，TLS 路径另有 X.509 生成与 SHA-256 签名，不能把 legacy `.pub` 编码与 X.509 certificate 当同一个对象。[Android Keystore](https://developer.android.com/privacy-and-security/keystore)、[AOSP AUTH 实现](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/auth.cpp)、[AOSP X.509 生成](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/crypto/x509_generator.cpp)。

**推论／POC：** 基本算法可匹配不等于现有 Rust TLS／ADB crate 可直接消费 Android 非导出密钥。Rust 应依赖可异步调用的平台 signer，区分「已散列 token／待散列消息」、padding、digest 与证书公钥的一致性，避免对 challenge 再做一遍哈希。需在 API24+ 软件／TEE／StrongBox 路径实测，尤其锁屏可签名与要求生物识别的互斥产品承诺。完整认证格式与 crate 适配交由 ADB 专项研究，本节不声称已完成对接。

## Riverpod 3、Hooks 与 Rust 状态分工

**事实。** Riverpod codegen 默认自动销毁；无监听者一帧后触发 dispose。keepAlive 只能改变无监听时的销毁策略，依赖变化导致 provider 重算仍会销毁旧状态。Riverpod 3 离屏 widget 的监听默认暂停，失败 provider 默认自动重试；dispose 后不能继续用已失效的 Ref／Notifier。[Automatic disposal](https://riverpod.dev/docs/concepts2/auto_dispose)、[Riverpod 3 migration](https://riverpod.dev/docs/3.0_migration)。

**事实。** flutter_hooks 的 `useEffect` 可在 keys 变化或 widget dispose 时执行清理函数；它适合取消 UI 订阅和清理 controller，不构成后台服务生命周期。[useEffect API](https://pub.dev/documentation/flutter_hooks/latest/flutter_hooks/useEffect.html)。

**推论：** Notifier 处理同步 UI 状态，AsyncNotifier 处理带异步加载的投影／交互；不要在 `build()` 里隐式创建具有副作用的持久设备连接。provider 自动重试不能再次上传文件、重新发按键或重复创建会话。命令用 operation ID 做去重，Rust 决定重试；Riverpod 负责呈现结果。`onDispose` 只释放它拥有的订阅等局部资源，用户断开与停止后台由明确命令触发。

**POC R5：** 离屏暂停时大量 Rust 事件如何处理；客户端重新订阅时取得快照与增量是否有竞态；一次失败是否触发双重重连。纯 Dart／Rust 测试可覆盖状态序列，实际 engine 销毁与 Android Service 必须走集成验证。

## Monorepo、生成代码与跨平台预留

**事实。** Dart pub workspaces 从 Dart 3.6 起提供统一依赖解析，根有共享 pubspec.lock 与 package_config；同一 workspace 不能各包使用冲突的依赖版本。Melos 7 基于 pub workspaces，配置进入根 pubspec.yaml 的 melos 字段，不应照搬旧 melos.yaml 教程。Cargo workspace 共享 Cargo.lock 与 target，并可共享 dependencies／lints；它与 Dart workspace 是两套独立解析系统。[Dart workspaces](https://dart.dev/tools/pub/workspaces)、[Melos 迁移](https://melos.invertase.dev/guides/migrations)、[Cargo workspaces](https://doc.rust-lang.org/cargo/reference/workspaces.html)。

**事实。** FRB 官方升级流程会随 codegen generate 更新 Dart／Rust 运行时依赖，源码也检查 codegen 与 Dart runtime 版本一致性。[FRB regular upgrades](https://cjycode.com/flutter_rust_bridge/guides/miscellaneous/upgrade/regular)、[版本检查源码](https://github.com/fzyzcjy/flutter_rust_bridge/blob/master/frb_dart/lib/src/main_components/entrypoint.dart)。

**推论：** CI 固定 Flutter SDK revision（随附 Dart）、Rust toolchain、FRB codegen 与两侧 runtime、pubspec.lock、Cargo.lock、JDK、Gradle wrapper、AGP/Kotlin、compileSdk／targetSdk／NDK。生成步骤使用已锁版本，重生成后检查工作区无 diff；不能在每次 CI 临时安装「latest」。NDK `ndkVersion` 支持 side-by-side 固定。[Android 固定 NDK](https://developer.android.com/studio/projects/install-ndk)。

**事实。** Flutter 3.47 官方发布文档列出的验证矩阵为 Java17（最低）、KGP2.4.0、AGP9.1.0、Gradle9.3.1（该 AGP 的最低），默认 compileSdk36、targetSdk36、minSdk24。这是该版本的基线，不代表 FRB、fvp 和自建 JAR 已在该组合通过；target37 权限验证也不能仅用默认 target36 构建替代。实施时依据锁定 release 的官方构建文件再次核对，NDK 版本还要与全部原生依赖一起验证。[Flutter 3.47 官方发布文档源码](https://github.com/flutter/website/blob/main/sites/www/content/blog/whats-new-in-flutter-3-47/index.md)。

**跨平台限制。** 纯协议 crate 与会话逻辑可共享；USB 枚举／权限、后台资格、通知、文件选择、密钥、视频 surface、输入法必须提供能力化 adapter。每个平台返回能力而非假装方法处处可用。Windows／Linux／macOS 的 USB 驱动、权限和播放器分发各有独立验证；iOS 不能仅凭 FRB 支持就继承 Android 后台与 USB 功能。iOS 构建／签名需要 Apple 工具链宿主。[Flutter 平台集成](https://docs.flutter.dev/platform-integration)、[Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup)。

## 液态玻璃、视频合成、输入与无障碍

### 渲染 API 的存在不能证明多路视频性能

**事实。** BackdropFilter blur 成本高，不 clip 会作用于更大区域；不重叠滤镜可通过 BackdropGroup／BackdropKey 共用输入，重叠区域不能随意复用同一 key。Impeller 在 Android API29+ 默认启用，低版本／不支持 Vulkan 时回退旧 OpenGL renderer；最低 API24 并不保证所有设备都用同一路径。[BackdropFilter API](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)、[Impeller availability](https://docs.flutter.dev/perf/impeller)。

**事实。** Android PlatformView 的 texture layer、hybrid composition、实验性 HCPP 有不同 transform、无障碍、缓冲与线程代价；HCPP 要 API34+、Vulkan、Impeller。fvp 的 Dart Player 暴露 textureId 与 nativeHandle，但不因此保证端到端零拷贝、所有视频格式硬解或多路任意并发。[Flutter PlatformViews](https://docs.flutter.dev/platform-integration/android/platform-views)、[fvp Player 源码](https://github.com/wang-bin/fvp/blob/master/lib/src/player.dart)。

**推论：** 压缩流与解码帧留在 native pipeline，FRB 传命令／事件／统计；不要每帧把 RGBA 经 Rust→Dart→UI 上传。Flutter Texture 与 AndroidView 是不同集成选择，不能拿 PlatformView 的某个模式说明直接证明 fvp Texture 的表现。视频下方的原生 surface 是否可被玻璃正确采样、色彩转换和 fence／copy 次数，均需检查具体插件和渲染后端。减少 CPU 拷贝也不代表没有 GPU pass、YUV→RGB、buffer queue 或合成延迟。

**POC R6：** 同一主控测 1／2／4 路、不同编码／分辨率／帧率；全屏与网格，玻璃覆盖面积／blur 分别变化，前后台切换和持续热负载。记录端到端输入到显示 P50／P95、实际解码队列深度、丢帧、UI raster 时间、内存、温度、功耗，验证播放器销毁与 texture 重建。官方要求性能分析使用真实设备 profile 模式；模拟器与 debug 不能证明最终性能。[Flutter profiling](https://docs.flutter.dev/perf/ui-performance)。

远端视频 texture 不会自动生成可供主控读屏器理解的远端控件语义树；主控工具栏可无障碍操作与远端画面可访问性是不同能力。[Flutter accessibility](https://docs.flutter.dev/ui/accessibility)。

### 中文输入与远端输入法需要单独验证

**事实。** scrcpy SDK 键盘注入只支持 ASCII 与部分字符；UHID 支持所有字符与 IME，但旧 Android 可能因权限不支持；AOA 只走 USB。Flutter TextInput 维护包含文本、selection、composing 的异步编辑状态，不能把所有 onChanged 内容当已提交字符。[scrcpy keyboard](https://github.com/Genymobile/scrcpy/blob/master/doc/keyboard.md)、[Flutter TextInput](https://api.flutter.dev/flutter/services/TextInput-class.html)。

**推论：** 产品需分别设计：远端输入法＋虚拟硬件键盘、本机中文输入后提交文本／剪贴板、键位直通。前者中文候选在远端，后者须处理本机 composing、退格、选区与提交确认；剪贴板粘贴不是万能字符输入，在密码／禁止粘贴字段可能不同。不能因 desktop scrcpy 的 UHID 能力就证明手机软键盘能自动产生全部硬件键事件。

**POC R7：** 中文拼音、候选替换、emoji、组合字符、长按重复、粘贴、密码框、游戏按键、远端旋转／分辨率改变；测试至少一种本机中文 IME 与目标系统 IME 的组合。

**推论：** 坐标必须记录远端 display ID、真实画面尺寸、旋转、裁切、letterbox，以及实际存在的 viewport 变换；用其逆变换映射 pointer。每个 pointer ID 必须保持 down→move→up／cancel，切设备、旋转和权限丢失时补 cancel，防止「手指粘住」；不能让 GestureDetector 临时抢走一个已发给远端的多指序列。这些是实现责任，不应作为算法选择交给用户。具体交互入口见[产品规则](../../designs/prod/interaction-rules.md)。

**事实／推论。** Android 边缘 Back 与 Home 系统手势拥有系统处理规则，允许有限的排除区域，不宜承诺全屏拦截。Flutter 本机导航使用 PopScope 接入 predictive back；远端 Back 是另一条输入命令，应有可见入口与清楚映射。[Android gesture navigation](https://developer.android.com/develop/ui/views/touch-and-input/gestures/gesturenav)、[Flutter predictive back](https://docs.flutter.dev/platform-integration/android/predictive-back)。

## 文件、通知与未来 Apple 平台

### 本机文件入口不能退化为普通路径字符串

**事实。** SAF 返回用户选定的 URI／目录树授权；Android11+ 对根目录、Download 整目录、Android/data／obb 等存在选择限制。可持久化 URI grant 仍可能因文档移动／删除失效；provider 的能力 flags 决定支持写入／删除等操作，`DocumentFile.canWrite()` 甚至不能独自证明可编辑。官方入门页描述 `ACTION_CREATE_DOCUMENT` 同名会加编号，但固定Android源码也存在用户选择已有文件后直接返回原URI的路径；返回URI不能证明排他新建，也不能据此安全截断。后续[提供方专项](provider-output-streams.md)记录了该源码反例及当前安全保存边界，优先于将入门说明外推成保证。[SAF 文件访问](https://developer.android.com/training/data-storage/shared/documents-files)。

**事实。** MediaStore 对媒体管理提供独立接口与权限规则，Android10+ 的 `IS_PENDING` 可使新媒体在写入期间不向其他应用发布；它不提供对任意 SAF provider／远端文件系统的统一事务。[MediaStore guide](https://developer.android.com/training/data-storage/shared/media)。

**推论：** 抽象文件 endpoint 为「定位符＋权限＋操作能力」：本机路径、SAF URI、MediaStore URI、远端 shell 路径不能互相冒充。预检可读、可创建、可覆盖、可 rename、可 seek、剩余空间与授权；远端 shell 能读到的位置也不自动可写，更不包含其他 App 私有数据的通行权。

**跨设备复制建议：** Rust 任务以 operation ID 管理，明确源版本／目标冲突策略；先写 staging，再校验尺寸／可选哈希，再按目标能力提交。只有同一文件系统且操作受支持时才可能使用原子 rename；SAF provider 不保证这种提交，跨设备也不可能靠 rename 原子完成。UI 的「成功」应在提交后，不能在字节传完时抢先完成。取消需停两端 I/O、清理临时项，清理失败进入可见待处理记录。目录部分成功按项报告，不虚构整目录原子性。

**推论：** 软链接须区分复制链接／跟随链接／拒绝；跟随时还要处理循环和逃出用户授权目录。远端路径、归档文件名与 Unicode 名不能直接拼 shell 字符串；冲突策略应同时考虑文件夹合并、大小写、保留扩展名与重新连接后目标已改变。跨设备 move 只能是复制验证成功后删除源，且删除前再次核对源身份／修改情况。

**POC R8：** 本地 SAF／MediaStore／远端任意两端组合；大文件与不可 seek stream、断网、空间满、取消、provider 崩溃、撤销 URI grant、重名、符号链接、校验失败、目录部分成功。是否可断点续传必须按 source/target capability 返回，不能把「记录了偏移」当可靠恢复。

### 通知同步与本地主控通知是两个授权方向

**事实。** Android13+ 的 POST_NOTIFICATIONS 管主控发布非豁免通知；不授予读取其他 App 通知的能力。启动 FGS 不以该权限获准为前提，但仍须创建 FGS 通知。NotificationListenerService 是另一套明确开启的通知访问机制，且有 profile／低内存设备等约束；被控端不安装 APK 时，通知取得与 action 能力必须由 shell／临时 JAR 方案另行证明。[通知权限](https://developer.android.com/develop/ui/compose/notifications/notification-permission)、[NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService)。

**推论：** 远端通知事件、主控本地发布、回复／关闭远端通知三个能力要分别协商。通知正文、OTP、来源设备名、锁屏公开版本、保留时长和是否存盘由产品明确；默认采用最少展示，在系统 visibility／channel 设置之外仍保留应用级策略。连接断开后旧 action 要拒绝或重新验证，不能向已切换的设备发回复。双向同步需要原始来源和去重 ID，避免镜像通知被再次同步。[锁屏 visibility 与 publicVersion](https://developer.android.com/develop/ui/compose/notifications/create-notification)。

### iOS／iPadOS：实际编译与运行能力分别验收

**事实。**Apple 本地网络权限、具体 Bonjour service 声明、自行 multicast entitlement 和后台任务各有条件；普通 TCP／Rust 实现不能绕过系统许可。USB 候选后端是否支持也不等于整个核心是否可编译。[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)、[后台策略](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)。

**现行交付约束。**保留 BackgroundExecutionCapability、UsbHostCapability、LocalNetworkAuthorization、FileEndpoint、KeySigner、VideoSurface 等适配，同时按[四端编译契约](cross-platform-build-contract.md)实际构建核心、FRB链接和Flutter整包；平台构建、运行权限和后台能力仍是不同验证层级。
