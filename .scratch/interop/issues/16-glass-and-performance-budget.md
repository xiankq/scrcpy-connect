# 16 · 液态玻璃跨端方案、可访问性与低延迟预算

Status: ready-for-agent
Type: research
Priority: P0
Depends on: 07, 20
Requirements: R07、R22、R39、R41–R44

## 问题

哪些玻璃实现能保留四端构建路径，并在实时视频上满足低延迟与清晰可读？

## 研究输入与边界

一手依据与已有调查位于 `docs/research/`：apple-liquid-glass-redesign.md；design-system-and-toolchain.md；flutter-rust-platform-runtime.md。入口见[需求审计](../requirements-audit.md)和[任务索引](README.md)。不把文档调查、编译与真机通过混为同一状态；现行规格与用户后续纠正优先于历史研究候选。

## 工作与交付物

- 继续比较liquid_glass_easy、widgets、fresnel等固定版本，不因单库Windows限制直接要求用户降级；逐端区分文档支持、编译和运行证据。
- Android按最新设计的设备面板、彩色功能图标、导航与工具浮层密度验证Texture采样、模糊/折射、多视频和滚动，量化GPU/内存/热量/功耗；比较关闭效果、基础材质和目标效果。
- 基于任务20基准提出输入到显示P95/P99、首帧、音画同步、重连、内存/并发、长稳与热降频阈值；未经测量不凭空承诺固定数字。
- 默认浅色、黑色主题色，可选深色/跟随系统；降低透明度/减少动态/大字/TalkBack/对比度与同层导航选中态保持操作一致。

交付到对应研究报告及能力／流程矩阵；涉及代码或画布验证时保留版本、可复现步骤与证据。依赖项约束对应实验与最终结论，资料研究可先开始。临时截图与日志样本按隐私处理后放临时目录，不把设计预览纳入 Git。

## 完成条件

- [ ] 形成有数据的候选结论及可测通过/失败门槛，动态视频采样不黑屏且回退可解释。
- [ ] 真实Android场景验证与四端构建分别留下产物；静态稿不当动态折射通过。
- [ ] 视觉值仅在design.md与Pencil tokens维护；Google官方lint的错误修复、剩余警告有分类说明。

## 当前状态

2026-10-17重新核查：官方Apple研究、规范、静态稿、基础模糊材质和部分对比测试已完成。

后续已固定liquid_glass_easy5.0.0，在共享Glass实现真实背景shader折射，不使用View/逐帧截图，不新增原生业务。Flutter3.47默认桌面Impeller的旧平台推断已纠正；按后端能力而非Windows平台硬降级。solid/降低透明度/highContrast完全跳过滤镜；圆与长导航左右中三点的黑白背景、双外观4.5对比及共享组件测试通过。Android真实产品流程与图像对照见[验收记录](../../../docs/implementation/validation.md#共享光学材质与通知页视觉复验)。

三段渐变及17stop平滑对照实机产生斜线，均未作为视觉通过；两色椭圆保护层已消除该可见缺陷。动态视频与拖动/收起/展开场景无黑块，仍不代表任意GPU或量化性能已验收。可打断液态形变、系统可访问性完整矩阵、独立光学像素对照、多视频GPU/热量预算及四宿主整包继续开放。

任务保持开放；`ready-for-agent`表示有明确工作可继续，不表示从未实施。逐需求与32流程见[完整重新核查](../completion-reassessment.md)，当前后端证据见[验收记录](../../../docs/implementation/validation.md)。
