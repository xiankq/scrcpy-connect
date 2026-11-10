# 项目约束

业务与应用视觉归app，通用能力归packages，对应Rust实现归rust同名目录，被控产物归servers。app只使用能力包公开Dart接口。

## 按任务读取

| 修改范围 | 入口 |
| --- | --- |
| 术语、身份或连接边界 | [词表](GLOSSARY.md)、[ADR](docs/adr/) |
| 产品行为 | [产品规格](designs/prod/README.md) |
| 界面与设计稿 | [视觉约束](designs/AGENTS.md)、[视觉规范](designs/design.md) |
| Flutter页面与路由 | [应用约束](app/lib/AGENTS.md) |
| 主题、token与共享控件 | [应用约束](app/lib/AGENTS.md)、[视觉规范](designs/design.md) |
| 原生与被控执行端 | [原生边界](docs/agents/native.md)、[servers](servers/AGENTS.md) |
| 资源、生成、构建或测试 | [架构](docs/implementation/architecture.md)、[工具链](docs/implementation/repository-tooling.md) |

产品或视觉变更同步受影响的规格、组件及实现。测试默认复用，新增遵守[测试准入](docs/implementation/repository-tooling.md#测试取舍)。

## 文档

只保留当前规则、必要用法及非显然决定；可直接查代码/配置的清单不再抄写。更新原文，删除失效内容，历史过程交给Git。任务结果默认在回复中说明，不自动新增研究、验收或总结MD。

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
