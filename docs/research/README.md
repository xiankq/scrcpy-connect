# 互联产品技术调研

研究基线日期：2026-10-16（Asia/Shanghai）。研究阶段使用 research、grilling 和 domain-modeling 补足产品与技术决策；后续实施已于2026-10-17推进，当前证据与缺口见[验收记录](../implementation/validation.md)和[持续目标](../../.scratch/interop/goal.md)。下文保留研究阶段的证据边界，不能用历史“未验证”覆盖后续实际结果。

研究成果已汇总到[规格](../../.scratch/interop/spec.md)。[产品设计](../../designs/prod/README.md)进一步描述用户体验，并与[页面与转换](../../designs/prod/user-flows.md)对应。设计已按最新范围重绘，以黑色为主题色、浅色为默认外观。预览按需导出到系统临时目录，仓库保留设计源文件、规范与所需素材；目前已建立Flutter/Rust工程并获得真实Android构建和部分双机E2E证据。

## 如何阅读

| 文档 | 重点 |
| --- | --- |
| [ADB 主机、连接与身份](adb-host-and-connectivity.md) | AOSP 版本快照、无线配对/TLS、主控密钥、USB、多路复用、现有 Rust 库、完整度验收 |
| [纯 Rust ADB 依赖链](pure-rust-adb-dependencies.md) | 两个候选的实际 feature、TLS provider 成熟度、nusb、双向压缩、系统 API 边界与验证矩阵 |
| [四端编译交付约束](cross-platform-build-contract.md) | 核心、FRB 链接与 Flutter 整包三层验收，平台依赖隔离、宿主 SDK 与 CI |
| [厂商互联完整流程](manufacturer-workflows.md) | 小米 Windows／苹果端功能、版本记录，以及文件编辑回写、相册备份和本机内容接续 |
| [免 APK 通知、短信与通话](android-shell-interop-capabilities.md) | shell 真实身份、通知 Binder token、原通知动作、SMS AppOps 与通话音频的 HAL 条件 |
| [CallStyle动作目标隔离](callstyle-action-targeting.md) | 原通知PI与具体通话绑定的区别，Android11/16 Dialer反例及不能仅凭typed extras解锁按钮的依据 |
| [AVD HEVC实际尺寸约束](hevc-emulator-constraints.md) | 软件编码器配置失败后的尺寸降级、独立码流／FFmpeg对照与1280／1080单变量验证 |
| [scrcpy、媒体与服务端](scrcpy-media-and-server.md) | 固定 scrcpy 协议、JAR 生命周期、独立应用窗口、fvp/MDK 输入、PTS、音频、录制与并发 |
| [首帧与客户端状态等待](scrcpy-first-frame-and-latency.md) | 官方静止补帧、播放器阻塞对照、五codec/后台/旋转与真实退出回归 |
| [共享媒体封装与播放器](cross-platform-media-pipeline.md) | 纯Rust Matroska、PTS、鉴权HTTP、fvp公开接口与各平台验收边界 |
| [Flutter/Rust 平台运行时](flutter-rust-platform-runtime.md) | Android 后台与权限、FRB/Riverpod 生命周期、USB 句柄、workspace、文件与输入 |
| [设计系统与工具链](design-system-and-toolchain.md) | Google DESIGN.md、液态玻璃候选比较、Lucide、厂商交互参照、Pencil 无头路径 |
| [Apple Liquid Glass 重设计依据](apple-liquid-glass-redesign.md) | HIG、WWDC25/26 的材质、导航、媒体与无障碍原则，以及中性色的设计应用 |
| [手机输入与剪贴板](mobile-input-and-clipboard.md) | 普通主控 App 与远端 shell 权限区别、中文 IME、图片/文件 URI、厂商体验证据 |
| [需求缺口关键事实复核](requirements-gap-verification.md) | scrcpy基础下限、ADB无线版本差异、首次授权下限与Apple本地网络/后台边界 |

每份报告区分直接证据、工程推论与未执行的 POC。引用上游作者的兼容说明不等于本项目已完成设备验收；实际构建、被控设备互通与性能分别以验收记录为准。

最新产品范围已收敛：录屏和自动备份移除；短信经通知接续手机原应用，通话、相册与文件管理保留专用页。其他取舍见[功能范围](../../designs/prod/scope.md)。研究报告中曾调查或建议的能力不等于当前产品承诺；专项证据见[小米与华为的页面路由](manufacturer-scope-xiaomi.md)。

## 本轮纠正与新增事实

- 无被控 APK 不等于不能扩展功能：可经 ADB 临时运行 shell JAR；但源码存在接口不等于所有 ROM 都授予相同行为。
- 当前已存在带 Rust 配对实现的 ADB 库，不能沿用“只能从零重写”的假设。复用路线仍需本项目的完整度与互操作验收。
- AOSP main 并不自动代表最新 ADB 行为；ADB 报告固定 Android 17 分支提交，且没有将其冒称为 Platform Tools 37.0.1 的精确构建源码。
- 配对、设备发现、连接在线、控制会话和可信物理设备身份是不同状态；设备地址和 GUID 不足以直接承担所有身份语义。
- scrcpy 多 SCID 只解决 socket 命名隔离；设备剪贴板、声音、设置、task 和编码器仍可能共享或争用。
- fvp/MDK 有字节流输入路径，appendBuffer 本身没有逐帧 PTS 参数；能播裸流不等于音画同步、旋转和录制均已正确。
- Android 后台连接不能简单交给离屏 provider；平台执行资格、Rust 会话、Dart 订阅和视频 surface 有不同生命周期。
- liquid_glass_renderer 的 Windows 限制不能推广到所有液态玻璃库；已补查 liquid_glass_easy、liquid_glass_widgets 和 fresnel。
- 用户否决“查看模式”；交互继续以厂商互联产品为参照。文件冲突默认询问并可应用到当前任务已经确认。

以上结论的逐项源码和官方文档见各专项报告。

## 记录与下一轮

- 产品术语：[GLOSSARY.md](../../GLOSSARY.md)。
- 已确认且具有长期影响的取舍：[ADRs](../adr/)。研究建议不记为 accepted ADR。
- 已确认目标、问题依赖与答案：[访谈设计树](../../.scratch/interop/interview.md)。

Q22–Q27 已回答。用户希望 ADB 依赖链尽量纯 Rust；确认后台按活动类型保持、设备级声音、真实应用任务、身份不自动迁移。Q27当时接受的可选通知历史随后被最新范围取舍移除，只保留实时通知。具体纯 Rust 口径及 TLS/USB/压缩后端继续核查，不把一轮回答当成整个设计树已经闭合。

已建立[60项需求追溯](../../.scratch/interop/requirements-audit.md)，补[分级兼容基线](../../.scratch/interop/compatibility-matrix.md)、[32项产品流程覆盖](../../designs/prod/coverage.md)及[20项后续任务](../../.scratch/interop/issues/README.md)。任务含19项研究/验证和1项设计补齐；已有研究不等于任务中的工程验证完成。2026-10-17已按源码/设计对象/实际测试路径做[完整重新核查](../../.scratch/interop/completion-reassessment.md)，发现产品主线缺实现与断链；该核查优先于研究阶段的状态描述。

Q28 用户要求依据 scrcpy 能力设计，已核实销毁虚拟显示内容和迁回主屏两条路径，不把此答复记为接受“默认迁回”。Q29–Q31 确认按中断原因恢复、实时通知动作同步远端、资源不足时保护已有重要活动。另有两项补充调查：纯 Rust ADB 依赖链、Android 手机输入与剪贴板；前者不自动撤销用户已接受的 fvp/MDK 媒体依赖选择，其范围专指 ADB。

Q35 后用户将常规功能取舍交给代理，并在 Q37 要求核实最新 scrcpy 单应用能力。已再次确认最新稳定版 5.0.1 的应用列表、指定应用启动和虚拟显示，将其作为应用互联主线；后续范围与默认由代理依据证据记录在[产品规格](../../.scratch/interop/spec.md)，不再批量询问功能是否需要，也不冒充用户逐项确认。

手机输入与剪贴板的文档调查已完成：Android10+ 普通主控 App 的后台读剪贴板能力不能照搬远端 shell；软 IME 编辑操作也不能自动当成实体按键。LADB 的本机无线 ADB 路线已调查，但 Q33 用户明确要求主控始终不开调试，因此不提供该入口，保留其研究记录以避免反复提出。Q34 确认自动同步跟随当前设备且可固定；实际执行仍遵守主控普通应用权限。

纯 Rust 依赖报告已完成静态调查：USB、发现与压缩存在候选路线；现有 ADB 库的 ring 依赖需要实际改造，不能仅关闭调用方默认 feature。RustCrypto TLS provider 有明确的上游生产警告，尚未闭合密码学成熟度与互操作验收。当前没有证据宣布全链路生产就绪，也没有证据认定 C 后端不可避免。Q32 用户未选定严格纯度口径，但要求确保 Android、iOS、Windows、macOS 全平台编译；后续必须用对应构建结果验收，而不是只看包的平台标签。
