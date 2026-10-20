# 需求缺口的关键事实复核

复核日期：2026-10-16。范围：最新 scrcpy、官方 ADB 无线优化、普通用户首次授权下限、Apple 运行边界。只读取规格与已有研究、查询官方网页和上游源码；未构建应用、未连接真机、未验证 ROM 行为。本文补充证据与研究任务，不改变已确认的功能、最低版本目标或 ADR。

## 与现有研究的关系

| 已有材料 | 已覆盖，不重复立项的事实 | 本次补充的缺口 |
| --- | --- | --- |
| [ADB 主机与连接](adb-host-and-connectivity.md) | TLS/SPAKE2、配对与连接端口分离、Wi-Fi 2.0、身份、mDNS、可达跨网、互操作 POC | 无线优化须按设备版本与主机行为分开验收；37.0.1 与通用网页存在后端说明差异；首次手动步骤需要成为产品验收 |
| [scrcpy 媒体与服务端](scrcpy-media-and-server.md) | v5.0.1、Android 10 虚拟显示、11 音频、13 duplication、单应用任务与多实例、协议版本 | 明确复核基础 Android 5+ 是否真的被最新上游放弃；区分启动应用与独立应用窗口，避免误删历史承诺 |
| [四端编译约束](cross-platform-build-contract.md) | 三层构建证据、iOS 排除 nusb、正式 feature 闭包、编译与运行分开 | Apple 本地网络首次授权、系统 Bonjour 与自行 UDP mDNS 的 entitlement 差异，应形成运行专项验收 |

## 1. scrcpy：未发现 Android 5+ 基础目标与当前上游矛盾

**已证：**调查时官方 `releases/latest` 指向 **v5.0.1**，2026-10-08 发布，release 指向源码 `a60891a…`。这与现有研究锁定版本一致。[官方 release](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1)

**已证：**v5.0.1 README 仍声明 API 21 / Android 5.0 最低要求；同 tag 的 `server/build.gradle` 仍为 `minSdkVersion 21`，不是将主控 Flutter SDK 的下限当成被控下限。[固定 README](https://github.com/Genymobile/scrcpy/blob/v5.0.1/README.md#prerequisites)、[固定构建配置](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/build.gradle)

因此，本次没有证据认定“被控 Android 5+ 基础投控”与最新 scrcpy 冲突。需要补的是本产品真实兼容验收，不能从功能门槛倒推放弃 Android 5–9，也不能从 `minSdkVersion` 直接宣布所有旧机已经通过。

| 被控能力 | v5.0.1 可核实门槛 | 对现有需求的含义 |
| --- | --- | --- |
| 主屏基础镜像与输入 | 官方最低 API 21；`supportsInputEvents` 允许主屏 display 0 | 保留 Android 5+ 基础目标；ROM 输入授权与编码器仍需实测。[README](https://github.com/Genymobile/scrcpy/blob/v5.0.1/README.md#prerequisites)、[Device.java](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/device/Device.java) |
| 启动某应用 | `Device.startApp` 取已有 launch intent；API 26+ 才附 `setLaunchDisplayId`，较旧系统仍有不附该选项的启动分支 | “进入原应用”与“独立应用窗口”分别验收，不能把二者都写成 Android 10+。[Device.java](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/device/Device.java) |
| 新虚拟显示与非主屏输入 | `Server.scrcpy` 在 API <29 拒绝 `new_display`；非主屏输入亦要求 API 29+ | Android 5–9 可保留主屏接续路径；独立窗口呈现精确不可用原因。[Server.java](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/Server.java)、[Device.java](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/device/Device.java) |
| 音频捕获 | Android 11+；11 启动时需解锁；12+ 无该额外步骤；10 以下自动禁用 | 视频与声音分别记录状态；Android 11 锁屏有画面但无声音是单独场景。[音频说明](https://github.com/Genymobile/scrcpy/blob/v5.0.1/doc/audio.md) |
| 被控本机同时播放的 duplication | Android 13+，应用可拒绝捕获 | 不将可投屏等同于可保留全部声音；设备音源与窗口音轨仍分开。[音频说明](https://github.com/Genymobile/scrcpy/blob/v5.0.1/doc/audio.md#duplication) |

**待实验：**固定官方 JAR、摘要与 Rust 协议实现，对 API 21/22、23、24/25、26–28、29、30、33、较新系统分别记录启动、首帧、触控、多点、导航、旋转、重连与退出清理。模拟器可查 API/异常分支，最低版本基础兼容与厂商输入条件须有真机证据。主控最低版本不受被控 API21 自动证明，按宿主依赖闭包确定。

## 2. 官方无线优化：改进重连，首次信任仍存在

**已证：**官方发布说明在调查时最高列出 **Platform Tools 37.0.1（2026-07）**。37.0.0 将默认 mDNS 后端改为 `libadbmdns`，增加 `.local` 主机名元数据；37.0.1 移除 `openscreen`，`ADB_MDNS_OPENSCREEN` 不再有效。[Platform Tools 发布说明](https://developer.android.com/tools/releases/platform-tools)

**已证：**官方 ADB 页面把 **Android 17 + adb 37.0.0** 的改进称为 **ADB Wi-Fi 2.0**，核心可观察行为是回到已信任无线调试网络时自动连接；它是设备与主机共同支持的路径，不能写成“换最新主机库后所有旧 Android 自动获得”。页面用 `mdns_service_version >=2.0` 诊断设备支持。[官方无线指南](https://developer.android.com/tools/adb#wireless)

**文档差异：**同一 ADB 通用页面末尾仍描述 v37 含两个后端、排障段仍建议修改 `ADB_MDNS_OPENSCREEN`。这与明确针对 **37.0.1** 的发布说明不同。应按锁定发行包说明与实际二进制行为验收，不能把两段合并成同一版本事实。[通用 ADB 后端说明](https://developer.android.com/tools/adb#mdns-backends)、[37.0.1 说明](https://developer.android.com/tools/releases/platform-tools)

**版本账本：**现有研究选定 AOSP `9084198a2d4b0f6a0f174260fb42da33485b684d`；它是固定源码基线，不是经本次证明的 37.0.1 二进制构建提交。后续同时保留下载包版本、摘要、`adb version`/`server-status`、源码提交和设备 build/API；没有构建来源映射时分别报告。[既有版本快照](adb-host-and-connectivity.md#1-版本与来源快照)

**已证：**AOSP 固定 Wi-Fi 架构文档区分 `_adb-tls-pairing._tcp` 与 `_adb-tls-connect._tcp`，连接 listener 随机选端口；旧 `_adb._tcp` / `tcpip 5555` 是另一条未加密 transport。示例中 pairing 与 connect 使用不同端口。配对完成后 `adb_wifi_pair_device` 记录 GUID，并尝试按服务名连接；这意味着配对成功和连接成功仍是两个结果。[固定架构文档](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/adb_wifi.md)、[固定配对客户端](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/adb_wifi.cpp)

**工程推论：**嵌入式 Rust 主机没有运行官方 adb server，因此新版桌面 server 自带的发现、重试与元数据处理不会自动进入产品。需要实现并验收等价行为。mDNS 是发现条件，授权是信任条件，网络路由/端口开放是可达条件；三者不能合为一个“已配对”布尔值。新 IP、新端口、切网后的旧流均不能靠沿用缓存恢复。[官方发现排障](https://developer.android.com/tools/adb#wireless)、[既有连接与状态研究](adb-host-and-connectivity.md)

**待实验：**对 Android 11–16 旧无线调试与 Android 17 Wi-Fi 2.0 分组，测试可信 Wi-Fi→断开→原网络、可信→未信任网络、DHCP 换 IP、关闭/重开无线调试、mDNS 丢失但 TCP 可达、路由可达但设备 listener 未开启、VPN 不承载组播、撤销授权。验收必须区分“自动发现”“已信任”“可连接”“旧控制会话恢复”，并记录无需用户操作的比例及实际中断时间。可达跨网保持 ADR0003 的条件，不追加自动穿透承诺。

## 3. 首次尽量无感：能封装命令，不能封装掉系统同意

以下是官方普通设备工作流下限，不是对全部 ROM 点击数量的保证。主控仅显示分步引导并执行已授权协议；不要求用户理解或输入 adb 命令。

| 路径 | 仍需人的动作 | 产品可自动完成的部分 |
| --- | --- | --- |
| 首次 USB | 被控启用开发者选项与 USB 调试，接线，解锁并确认被控 RSA 授权；Android 主控另需已有 USB 访问权限或用户同意系统 USB 弹窗 | USB 枚举、发起身份认证、获准后上传临时 JAR 与开启控制会话。[开发者选项](https://developer.android.com/studio/debug/dev-options#enable)、[RSA 授权](https://developer.android.com/tools/adb#Enabling)、[USB host 权限](https://developer.android.com/develop/connectivity/usb/host#permission-d) |
| Android 11+ 首次无线 | 被控启用开发者选项和无线调试、同意当前网络；选择配对码并提供码，或选择二维码配对并扫描主控二维码 | 自动发现配对服务、接收码并配对、再发现连接服务与连接；二维码免手抄码，但仍需在被控系统界面扫码。[无线指南](https://developer.android.com/tools/adb#wireless)、[AOSP 配对/QR 流程](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/adb_wifi.md) |
| Android 10 及以下首次无线 | 官方路径先完成 USB 授权，再由已授权主机切换 TCP listener；需要实际 USB 路径 | 主控代发 `tcpip` 与连接请求；无需用户输入命令。没有官方依据可承诺冷启动、从未授权的旧设备纯无线一键连接。[旧系统无线流程](https://developer.android.com/tools/adb#wireless) |

**已证与推论：**`Settings.Global` 的值不能由普通应用任意写入；调试的官方工作流要求在系统 UI 启用。USB ADB 文档明确 RSA 确认的目的就是防止未解锁、未确认的命令执行。本约束下没有已证官方路径从未授权连接静默开启被控调试或略过信任。无线配对不额外出现 USB 的 RSA 同意框，是以配对码/扫码建立信任，不是免授权。[Settings.Global](https://developer.android.com/reference/android/provider/Settings.Global)、[USB 授权机制](https://developer.android.com/tools/adb#Enabling)、[AOSP Wi-Fi 信任](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/adb_wifi.md)

**需求结论：**“首次尽量无感”应验收为无需命令、定位设置清楚、正确区分两台设备的系统操作、可恢复，并在已有信任与许可条件下减少后续打扰。它不应改写成零系统步骤。无被控 APK/no root 与主控不开调试继续保留；主控 USB 权限是普通应用授权，不等于主控开启调试。厂商额外输入安全开关可见 [scrcpy 固定 README 的 Xiaomi 说明](https://github.com/Genymobile/scrcpy/blob/v5.0.1/README.md#prerequisites)，其他厂商需按实际机型记录，不推定全部需要或全部不需要。

## 4. Apple：构建义务继续，运行需单列本地网络与后台证据

**已证：**Apple TN3179 区分本地网络访问与 Bonjour/multicast：iOS/iPadOS 14+ 的本地网络访问受用户授权控制，macOS 从 15 起同样有此权限；应用需提供 `NSLocalNetworkUsageDescription`。浏览已声明的具体 Bonjour 服务需 `NSBonjourServices`；自行收发 multicast/broadcast 或浏览任意服务类型，iOS 另需 multicast entitlement。不能笼统认定“所有 Bonjour 都需 entitlement”，也不能认定“Rust 直接 UDP mDNS 不受平台许可影响”。[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

**工程推论：**优先研究 iOS 平台发现适配，列出 `_adb._tcp`、`_adb-tls-pairing._tcp`、`_adb-tls-connect._tcp` 这三个具体服务；共用 Rust ADB 核心接收发现结果。若继续使用自行 UDP mDNS，再核对 entitlement 与签名条件。手动填写 LAN IP 仍是本地网络访问，不应作为绕过拒绝权限的功能。TN3179 还指出授权待定时的首次操作可能立即失败，故恢复重试需实测，不能一失败就宣告设备离线。[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

**已证与限制：**Apple 提供按任务类型选择后台运行策略；系统调度后台任务不构成任意 TCP/ADB 连接永久运行的许可。后台下载的系统机制也不能未经验证就等价于私有 ADB sync。现有规格用“系统允许条件下”表述后台保持是合适的，需为持续音频、文件传输、普通待机分别研究。[Apple 后台策略](https://developer.apple.com/documentation/BackgroundTasks/choosing-background-strategies-for-your-app)、[系统后台下载](https://developer.apple.com/documentation/Foundation/downloading-files-in-the-background)

本次未重新穷尽 Apple 新 USB API，故不新增“iPhone 永远不能 USB ADB”的断言；现有候选 nusb 无 iOS backend 的源码事实只证明当前依赖方案需隔离。iOS 当前交付仍按[编译约束](cross-platform-build-contract.md)实际构建；TCP/TLS、权限、发现、媒体及后台运行保持单独证据。
