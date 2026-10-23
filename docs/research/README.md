# 技术研究

研究保留一手来源、结论和未解决的技术取舍。当前规则与结果分别见[ADR](../adr/)、[架构](../implementation/architecture.md)和[验收入口](../implementation/validation.md)；被替换的播放器、捕获实验及重复排查报告由 Git 历史追溯。

| 主题 | 资料 |
| --- | --- |
| ADB协议、配对与授权身份 | [连接与身份](adb-host-and-connectivity.md)、[旧版兼容](adb-android-compatibility.md) |
| ADB依赖与吞吐 | [纯Rust依赖](pure-rust-adb-dependencies.md)、[参考实现性能](adb-reference-performance.md) |
| 跨平台 | [构建边界](cross-platform-build-contract.md)、[Flutter/Rust运行时](flutter-rust-platform-runtime.md) |
| scrcpy服务与协议 | [服务端与媒体](scrcpy-media-and-server.md)、[原生媒体机制差异](scrcpy-source-audit.md) |
| 延迟与编码 | [队列放大和参考实现](remote-control-latency-optimization.md)、[35–70ms来源](scrcpy-mobile-latency-primary-sources.md)、[HEVC模拟器](hevc-emulator-constraints.md)、[SurfaceTexture](surface-texture-queue-semantics.md) |
| Android发布构建 | [JNI/R8根因](android-release-media-crash.md) |
| 内容交付 | [URI信任与任务复用](android-share-trust.md)、[provider输出流](provider-output-streams.md)、[目标端缩略图](media-thumbnail-pipeline.md) |
| 输入与通信 | [中文输入和剪贴板](mobile-input-and-clipboard.md)、[shell权限](android-shell-interop-capabilities.md)、[具体通话动作](callstyle-action-targeting.md)、[主控系统通知](controller-notification-delivery.md) |
| 产品参考 | [厂商操作路由](manufacturer-workflows.md)、[Apple连续互通](apple-continuity-workflows.md) |
| 视觉与工具 | [设计系统来源](design-system-and-toolchain.md)、[Liquid Glass官方资料](liquid-glass-design-review.md) |
