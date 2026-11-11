# 项目边界

业务、状态编排与视觉归 `app/`；通用能力归 `packages/`，对应 Rust 实现归 `rust/` 同名目录；被控产物归 `servers/`。应用只通过能力包公开 Dart 接口调用原生能力。

## 按修改范围读取

| 修改范围 | 入口 |
| --- | --- |
| 术语、身份、连接及资源归属 | [词表](GLOSSARY.md)、[领域文档约定](.agents/skills/setup-matt-pocock-skills/domain.md) |
| 产品行为与能力范围 | [产品规格](designs/prod/README.md) |
| 页面、路由、状态与服务 | [应用约束](app/lib/AGENTS.md) |
| 视觉、主题、token、共享控件 | [设计约束](designs/AGENTS.md)、[视觉规范](designs/design.md) |
| 原生能力 | 对应能力包的 README；[adb](packages/adb/README.md)、[scrcpy](packages/scrcpy/README.md)、[media_codec](packages/media_codec/README.md) |
| 被控协议、构建与资源 | [执行端约束](servers/AGENTS.md) |
| 生成、构建与测试 | [脚本入口](scripts/README.md)、[测试取舍与运行](test/README.md) |

修改产品或视觉时，同步受影响的规格、组件与实现；验证范围按实际改变的行为与边界选择。架构约束由 `scripts/check_architecture.dart` 校验。

文档只保留当前规则、必要用法与非显然决定。更新原文并删除失效内容，代码和配置可直接查到的清单留在其来源；过程交给 Git，任务结果默认在回复中说明。

## Agent skills

- 工单与规格使用 `.scratch/<feature>/` 下的 Markdown；处理工单前读[本地工单约定](.agents/skills/setup-matt-pocock-skills/issue-tracker-local.md)。
- 分诊使用五个默认角色；分诊前读[标签映射](.agents/skills/setup-matt-pocock-skills/triage-labels.md)。
- 探索代码前读[领域文档约定](.agents/skills/setup-matt-pocock-skills/domain.md)与[词表](GLOSSARY.md)；本项目采用单上下文，按约定读取已有 ADR。
