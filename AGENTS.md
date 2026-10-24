# 项目约束

Flutter 主控应用与业务代码位于 `app/`；`packages` 仅承载通用设计系统、ADB、scrcpy 与媒体解码能力，Rust 实现统一位于同名的 `rust/<package>/`。FRB 及生成代码由能力包维护，应用只使用公开 Dart 接口。被控临时执行产物位于 `servers`。目录职责见 [README](README.md#工作区)。

## 按任务读取

| 修改范围 | 先读 |
| --- | --- |
| 领域术语、设备身份、连接或平台边界 | [领域文档规则](docs/agents/domain.md)、[词表](GLOSSARY.md)和对应 [ADR](docs/adr/) |
| 产品范围、页面入口、默认行为、失败与恢复 | [产品维护约束](designs/prod/AGENTS.md)、[产品规格入口](designs/prod/README.md) |
| 界面、布局、颜色、材质或 Pencil 组件 | [视觉工作约束](designs/AGENTS.md)、[视觉规范](designs/design.md) |
| Flutter 页面、导航、当前设备归属 | [主控应用约束](app/lib/AGENTS.md) |
| 共享主题、材质、控件或 token 接口 | [设计系统约束](packages/design_system/AGENTS.md) |
| ADB 协议、被控版本、文件服务或 Rust 活动生命周期 | [Rust 核心约束](docs/agents/native.md) |
| 被控 JAR、原生助手、上游产物或嵌入摘要 | [服务端产物约束](servers/AGENTS.md) |
| 资源所有权、路由、生成物或原生依赖 | [架构](docs/implementation/architecture.md)、[工具链契约](docs/implementation/repository-tooling.md) |

涉及产品行为或视觉的变更，先定位责任规格、Pencil 代表状态和实现入口；共享组件变更还需定位母组件及受影响实例。按实际影响同步这些对象，避免只调整其中一层便将整项需求标记为完成。

## 文档边界

产品规则、视觉 token、架构决定各有唯一责任文档。研究报告说明固定来源下的事实与推论；实施和验收记录说明特定版本的结果，不承担当前规范。更新规则时修改原有正文，其他文档改为引用，避免用追加“最新要求”保留互相矛盾的正文。

规范只记录本项目容易混淆的对象、归属、默认值和例外；技术选型的理由归 ADR 或研究文档。页面数量、测试数量、临时日志与截图路径归验收记录。

主控宿主、被控 Android、协议能力及单项功能是不同的兼容维度。声明支持或完成验收时，注明对象、环境与实际验证层级；静态稿、组件截图、GPU 成像、主机协议夹具和设备运行分别提供证据。

## 构建与调试资源

截图和调试导出使用系统临时目录；设计源稿实际引用的素材保留在仓库。构建与调试结束清理过期中间产物、重复安装包和本次创建的测试资源；保留指定交付产物及仍在复用的编译缓存，范围见[构建与产物边界](docs/implementation/repository-tooling.md)。

受控依赖源码、许可证及其要求的对应源码归档属于项目输入。清理依据产物用途、资源身份与在用状态，不能仅按目录名或体积判定为垃圾。

## Agent skills  (以下不可修改)

### Issue tracker

Issues and specs use local Markdown under `.scratch/<feature>/`.
Before working with tickets, read `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage roles.
Before triaging tickets, read `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `GLOSSARY.md` and `docs/adr/`.
Before exploring the codebase, read `docs/agents/domain.md`.
