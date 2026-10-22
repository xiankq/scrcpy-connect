# 技术研究索引

本目录记录固定来源下的事实、推论与实验结果。当前规则由[词表](../../GLOSSARY.md)、[ADR](../adr/)、[产品规格](../../designs/prod/README.md)、[视觉规范](../../designs/design.md)和[架构](../implementation/architecture.md)维护；研究中的候选与历史测试不承担当前支持或完成度承诺。

## ADB、身份与平台

| 研究 | 独有内容 |
| --- | --- |
| [ADB 主机、连接与身份](adb-host-and-connectivity.md) | AOSP无线配对/TLS、密钥、USB、多路复用与burst机制 |
| [ADB 性能与参考实现](adb-reference-performance.md) | AOSP/Tango/libadb对照、SYNC合并及受控测量边界 |
| [ADB 低版本兼容](adb-android-compatibility.md) | 固定版本认证、shell、SYNC、压缩与超时差异 |
| [纯 Rust ADB 依赖](pure-rust-adb-dependencies.md) | 候选feature、TLS成熟度、nusb与系统API边界 |
| [mDNS版本与解析器修复](locked-mdns-contract.md) | 旧0.17.2语义、HINFO缺陷及0.21系列修复；当前已升级0.21.6 |
| [四端构建约束](cross-platform-build-contract.md) | iOS USB依赖隔离、FRB链接与构建宿主条件 |
| [Flutter/Rust运行时](flutter-rust-platform-runtime.md) | FGS、FRB/Riverpod、USB句柄、权限与恢复边界 |
| [Flutter工程工具链](flutter-engineering-toolchain.md) | typed路由、Riverpod生成、build_runner与一致性 |
| [关键事实复核](requirements-gap-verification.md) | scrcpy下限、无线ADB版本与Apple网络/后台条件 |

## 媒体机制与实验

| 研究 | 独有内容 |
| --- | --- |
| [scrcpy媒体与服务端](scrcpy-media-and-server.md) | 固定协议、通道顺序、JAR生命周期、应用窗口与音频边界 |
| [共享媒体封装与播放器](cross-platform-media-pipeline.md) | Matroska映射、精确PTS、MDK C表ABI与输入候选 |
| [scrcpy 到 fvp 的数据与复制路径](scrcpy-fvp-copy-path.md) | 按 Java/Rust/Dart/原生追踪、两段本机TCP、封装复制、USB差异与像素回读 |
| [核心体积、延迟与跨平台重构评估](scrcpy-core-architecture-options.md) | 原版scrcpy与自写ADB差异、当前APK/ELF审计、原生packet解码、系统后端与全面重写取舍 |
| [fvp 与 media_kit 替换评估](fvp-media-kit-comparison.md) | 开源核心、直播缓冲、截图与销毁语义、原生分发及现有迁移接缝 |
| [移动端延迟一手来源](scrcpy-mobile-latency-primary-sources.md) | 官方35~70ms的桌面实验条件、第三方scrcpy-mobile固定源码与测量边界 |
| [远控延迟对照与改造顺序](remote-control-latency-optimization.md) | scrcpy/scrcpy-mobile/EasyControlNext对照、输入ACK积压、视频反压与弱网实验 |
| [客户端低延迟路径](scrcpy-client-latency-path.md) | 官方packet直送、FFmpeg parser/线程与容器反证 |
| [首帧与状态等待](scrcpy-first-frame-and-latency.md) | waitFor0负例、decoder选择、START_APP等待环与回调竞态 |
| [首帧、源时间与解码路径](scrcpy-first-frame-performance.md) | AOSP时间轴、软件codec参数、snapshot故障与实际异步路径 |
| [SurfaceTexture队列语义](surface-texture-queue-semantics.md) | 异步替换、回调合并、EGLConsumer与重复纹理 |
| [输入槽与有界捕获实验](capture-input-queue.md) | slot观测、双项/单项候选失败、完整帧选择偏差 |
| [协作暂停实验](cooperative-capture-pause.md) | 已弃用type128扩展、资源归属及负向多窗口结果 |
| [MDK内存输入实验](mdk-memory-input-experiment.md) | HTTP/append对照、AMediaCodec/FFmpeg反证与有限流限制 |
| [MDK修复版本核查](mdk-sdk-snapshot-followup.md) | snapshot公开问题、不同崩溃栈及async默认值 |
| [HEVC模拟器约束](hevc-emulator-constraints.md) | 实际尺寸降级、码流/FFmpeg和分辨率单变量验证 |
| [Android媒体包体积](android-media-package-size.md) | 三ABI基线、ELF/JAR重复、libass依赖及裁剪候选上界 |

## 内容与通信

| 研究 | 独有内容 |
| --- | --- |
| [shell通知、短信与通话](android-shell-interop-capabilities.md) | Binder token、原通知动作、SMS AppOps与HAL条件 |
| [CallStyle动作目标](callstyle-action-targeting.md) | 原通知PI与具体通话的绑定、Dialer反例 |
| [主控系统通知投递](controller-notification-delivery.md) | 插件/平台权限、通道、锁屏历史和Windows包身份 |
| [系统保存与提供方流](provider-output-streams.md) | SAF旧URI反例、pipe/proxy FD、错误与完成证据 |
| [系统分享信任](android-share-trust.md) | URI/grant、持久来源、取消与task复用夹具陷阱 |
| [目标端缩略图](media-thumbnail-pipeline.md) | shell进程EXIF/FD限制、旋转、隔离解码与源戳 |
| [手机输入与剪贴板](mobile-input-and-clipboard.md) | 普通App与shell权限、中文IME、跨设备URI和焦点 |

## 厂商与视觉来源

| 研究 | 独有内容 |
| --- | --- |
| [厂商互联操作路由](manufacturer-workflows.md) | 小米平台矩阵、OPPO/vivo内容交接、编辑与断连 |
| [Apple连续互通](apple-continuity-workflows.md) | 镜像、通知、Handoff/AirDrop、通话与FaceTime远控条件 |
| [设计系统与工具链](design-system-and-toolchain.md) | DESIGN.md、液态玻璃库比较、图标与Pencil工具边界 |
| [Liquid Glass官方设计复核](liquid-glass-design-review.md) | HIG/WWDC25与26差异、材质、滚动边缘、排版和静态证据边界 |
