# 互联研究与设计补齐任务

本轮会话需求审计生成。任务不是按“首版只做”裁剪的清单，也不把历史被移除能力重新加入。所有任务处于信息足够、可由代理开展研究的状态；尚无应用构建或真机完成结果。`Depends on` 约束对应实验和最终验收，先读资料、盘点环境、明确接口可并行。P0表示影响后续路线的关键前提，P1表示同样保留但可随前提并行推进。

| 任务 | 类型 | 依赖 | 优先级 |
| --- | --- | --- | --- |
| [01 完整 Rust ADB 契约与新版无线行为对照](01-adb-contract-and-wireless.md) | research | 无 | P0 |
| [02 ADB 依赖纯度、密码学成熟度与复用路线](02-pure-rust-crypto-dependencies.md) | research | 无 | P0 |
| [03 Monorepo、状态所有权与四端实际构建方案](03-workspace-bridge-platform-builds.md) | research | 02 | P0 |
| [04 主控、被控与功能分级兼容矩阵](04-compatibility-capabilities.md) | research | 01、06 | P0 |
| [05 普通用户首次连接、扫码配对与日常重连](05-ordinary-user-onboarding.md) | research | 04、15 | P0 |
| [06 scrcpy JAR 与扩展服务的启动、协议和清理](06-server-orchestration.md) | research | 01 | P0 |
| [07 fvp 实时流、时间戳与可替换渲染链路](07-fvp-media-pipeline.md) | research | 03、06 | P0 |
| [08 手机控手机的输入、全屏与窗口生命周期](08-mobile-input-and-windows.md) | research | 06、07 | P1 |
| [09 文件管理、部分成功、取消与恢复资格](09-file-endpoints-and-recovery.md) | research | 01、14 | P1 |
| [10 相册索引、视频预览与手动取用](10-gallery-video-and-content.md) | research | 07、09 | P1 |
| [11 免 APK 通知动作、认证与原应用接续](11-notifications-continuation.md) | research | 06、15 | P0 |
| [12 通话控制、双向语音与多设备仲裁](12-calls-and-audio-arbitration.md) | research | 06、14 | P0 |
| [13 剪贴板对象、设备音源与系统分享](13-device-targets-and-sharing.md) | research | 08、09、12 | P1 |
| [14 后台资格、活动恢复与未知操作结果](14-background-and-recovery.md) | research | 03、05、15 | P0 |
| [15 主控密钥、授权撤销与多路径设备身份](15-identity-trust-and-transports.md) | research | 02 | P0 |
| [16 液态玻璃跨端方案、可访问性与低延迟预算](16-glass-and-performance-budget.md) | research | 07、20 | P0 |
| [17 补齐厂商手机互联的实际操作证据](17-manufacturer-mobile-flows.md) | research | 无 | P1 |
| [18 补齐产品流程与 Pencil 交互状态覆盖](18-complete-design-state-coverage.md) | task | 04、05、08、09、10、11、12、13、14、16、17 | P1 |
| [19 依赖许可、版本维护与交付证据治理](19-dependency-license-and-updates.md) | research | 02、03、06、07、16 | P1 |
| [20 Android 模拟器、真机与性能验收基准](20-android-validation-bench.md) | research | 03 | P0 |

优先核实完整ADB/无线、依赖纯度、四端构建、能力门槛、JAR和身份；随后以模拟器/真机证据推进媒体、输入、通知、通话、文件与后台。设计补齐可先落实已确定规则，未证功能保持条件状态，不用“等全部技术做完”搁置设计。

- [全量需求对照](../requirements-audit.md)
- [功能分级基线](../compatibility-matrix.md)
- [产品流程覆盖](../../../designs/prod/coverage.md)
- [关键事实补查](../../../docs/research/requirements-gap-verification.md)

任务18是设计补齐，其余19项是研究/验证任务。创建任务不表示已执行其中的构建、POC、实测或补画。
