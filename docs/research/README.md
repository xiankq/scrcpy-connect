# 技术研究索引

本目录保留按文内日期、版本与来源完成的研究。上游事实、工程推论和当时建议分别阅读；研究建议不直接构成现行产品规则，旧实验也不自动代表当前源码。

当前对象与边界见[词表](../../GLOSSARY.md)和 [ADR](../adr/)，用户可见规则见[产品规格](../../designs/prod/README.md)，视觉值与材料用途见[视觉规范](../../designs/design.md)，实现职责见[架构](../implementation/architecture.md)。指定版本的运行结果见[产品验收](../implementation/product-refinement.md)与[专项记录](../implementation/validation.md)。

## 专项入口

| 文档 | 重点 |
| --- | --- |
| [ADB 主机、连接与身份](adb-host-and-connectivity.md) | AOSP 版本快照、无线配对/TLS、主控密钥、USB、多路复用、现有 Rust 库、完整度验收 |
| [实际mDNS锁版契约](locked-mdns-contract.md) | 实际0.17.2与研究0.21.5的区别、HINFO解析器缺陷、0.21.2修复线及实际验收边界 |
| [纯 Rust ADB 依赖链](pure-rust-adb-dependencies.md) | 两个候选的实际 feature、TLS provider 成熟度、nusb、双向压缩、系统 API 边界与验证矩阵 |
| [四端编译交付约束](cross-platform-build-contract.md) | 核心、FRB 链接与 Flutter 整包三层验收，平台依赖隔离、宿主 SDK 与 CI |
| [厂商互联完整流程](manufacturer-workflows.md) | 小米 Windows／苹果端功能、版本记录，以及文件编辑回写、相册备份和本机内容接续 |
| [Apple自身连续互通操作](apple-continuity-workflows.md) | Mac镜像、通知与原应用、Handoff／AirDrop／剪贴板、独立通话，以及FaceTime手机／iPad获允远控的不同条件 |
| [免 APK 通知、短信与通话](android-shell-interop-capabilities.md) | shell 真实身份、通知 Binder token、原通知动作、SMS AppOps 与通话音频的 HAL 条件 |
| [CallStyle动作目标隔离](callstyle-action-targeting.md) | 原通知PI与具体通话绑定的区别，Android11/16 Dialer反例及不能仅凭typed extras解锁按钮的依据 |
| [AVD HEVC实际尺寸约束](hevc-emulator-constraints.md) | 软件编码器配置失败后的尺寸降级、独立码流／FFmpeg对照与1280／1080单变量验证 |
| [scrcpy、媒体与服务端](scrcpy-media-and-server.md) | 固定 scrcpy 协议、JAR 生命周期、独立应用窗口、fvp/MDK 输入、PTS、音频、录制与并发 |
| [首帧与客户端状态等待](scrcpy-first-frame-and-latency.md) | 官方静止补帧、播放器阻塞对照、五codec/后台/旋转与真实退出回归 |
| [当前首帧与产物核查](scrcpy-first-frame-performance.md) | 官方版本／暂停JAR身份、重建条件、源时钟与后续隔离候选边界 |
| [SurfaceTexture实际队列](surface-texture-queue-semantics.md) | Android16异步替换、原生回调合并、EGLConsumer取帧、静态repeat10次与运行时待证项 |
| [共享媒体封装与播放器](cross-platform-media-pipeline.md) | 纯Rust Matroska、PTS、鉴权HTTP、fvp公开接口与各平台验收边界 |
| [协作暂停捕获](cooperative-capture-pause.md) | 固定scrcpy源码的捕获扩展、停止编码与保留task、ACK/代际边界、可复现构建与真实多窗口 |
| [Flutter/Rust 平台运行时](flutter-rust-platform-runtime.md) | Android 后台与权限、FRB/Riverpod 生命周期、USB 句柄、workspace、文件与输入 |
| [Flutter工程工具链](flutter-engineering-toolchain.md) | typed路由、生成Riverpod、build_runner、官方lint和生成一致性 |
| [系统保存与提供方流契约](provider-output-streams.md) | SAF已有URI反例、rw／w／pipe／proxy FD、错误通道及系统保存完成证据；专项研究不等于提供方矩阵已实测 |
| [系统分享信任与所有权](android-share-trust.md) | 外部URI/grant、导入/取消、持久源、Activity/engine边界与实际分享驱动 |
| [目标端缩略图](media-thumbnail-pipeline.md) | JPEG/视频帧、EXIF/旋转、有界作业、缓存/取消和真实端验证 |
| [主控系统通知投递](controller-notification-delivery.md) | 跨端插件固定版本、权限/通道、普通来电提醒、系统历史隐私与Windows包身份限制 |
| [设计系统与工具链](design-system-and-toolchain.md) | Google DESIGN.md、液态玻璃候选比较、Lucide、厂商交互参照、Pencil 无头路径 |
| [Apple Liquid Glass 重设计依据](apple-liquid-glass-redesign.md) | HIG、WWDC25/26 的材质、导航、媒体与无障碍原则，以及中性色的设计应用 |
| [手机输入与剪贴板](mobile-input-and-clipboard.md) | 普通主控 App 与远端 shell 权限区别、中文 IME、图片/文件 URI、厂商体验证据 |
| [需求缺口关键事实复核](requirements-gap-verification.md) | scrcpy基础下限、ADB无线版本差异、首次授权下限与Apple本地网络/后台边界 |

## 使用边界

上游文档的兼容说明与本项目的实际编译、被控设备互通、物理权限及性能是不同证据。报告列出的候选版本只适用于其研究时点；依赖升级后按锁定版本重新核对，不组合不同版本的能力描述。

早期调查包括通知历史、固定剪贴板对象、手动音源策略和其他范围候选。现行取舍以[功能范围](../../designs/prod/scope.md)及[交互规则](../../designs/prod/interaction-rules.md)为准；这些候选不构成重新加入产品入口的依据。

页面、组件与测试计数统一读取[视觉审计](../implementation/ios-visual-audit.md)及对应验收记录。本索引不维护另一份完成度、访谈编号或任务列表。

- [ADB 低版本兼容与开源参照](adb-android-compatibility.md)：固定 AOSP、scrcpy、Tango 等源码；实际实施与版本验收另见[被控兼容边界](../implementation/android-target-compatibility.md)。
