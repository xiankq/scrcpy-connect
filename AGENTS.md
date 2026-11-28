# 仓库规则

## 代码放在哪里

- `app/`：页面、业务状态、流程控制和视觉。
- `packages/`：通用原生能力包（`adb`、`scrcpy`、`media_codec`），对外只提供 Dart 接口。
- `rust/<包名>/`：`packages/<包名>` 的 Rust 实现。
- `servers/`：在被控手机上临时运行的程序和构建它们的脚本。

`app/` 只通过能力包公开的 Dart 接口调用原生能力，不直接导入 FRB 生成物或 Rust 代码。改完运行 `dart --disable-dart-dev scripts/check_architecture.dart` 检查这些依赖规则。

## 改之前先读

| 要改的东西 | 先读 |
| --- | --- |
| 术语、设备身份、连接和资源由谁负责 | [词表](GLOSSARY.md)、[领域文档约定](.agents/skills/setup-matt-pocock-skills/domain.md) |
| 产品行为、功能范围 | [产品规格](designs/prod/README.md)、[规格写法](designs/prod/AGENTS.md) |
| 页面、路由、状态、服务 | [应用代码规则](app/lib/AGENTS.md) |
| 视觉、主题、token、共享控件 | [设计规则](designs/AGENTS.md)、[视觉规范](designs/design.md) |
| 原生能力 | [adb](packages/adb/README.md)、[scrcpy](packages/scrcpy/README.md)、[media_codec](packages/media_codec/README.md)、[Rust ADB](rust/adb/README.md) |
| 被控程序的协议、构建和资源 | [被控程序规则](servers/AGENTS.md) |
| 生成、构建、打包、清理缓存 | [脚本说明](scripts/README.md) |
| 测试：写什么、不写什么、怎么跑 | [测试说明](test/README.md) |
| 发布 | [发布说明](docs/releasing.md) |

改产品行为或视觉时，在同一次改动里同步更新受影响的规格、设计稿组件和代码。测试范围按实际改变的行为选，见[测试说明](test/README.md)。

## 错误处理

- 在能处理错误的那一层捕获已知错误，并给出其中一种结果：自动恢复、明确的失败结果、诊断日志。处理不了就把原错误和堆栈原样抛给上层。
- 必须完成的操作失败时返回失败。失败、空结果、默认值、用户取消是四种不同结果，不要用一种代替另一种。例如：用户关掉文件选择框返回"取消"，不返回空列表。
- 释放资源写在 `finally` 里。操作本身的结果和释放的结果分别保留，释放失败不能覆盖操作的错误。
- 外部输入（用户输入、设备返回、文件内容）只在进入系统的那一层校验一次，内部代码按类型直接使用。
- 要为罕见情况加分支时，先向用户说明：什么场景、什么条件下发生、不处理会怎样。用户确认后再写。
- 只有代码真的重复出现、且职责相同时才抽成共用函数。

## 写文档

- 文档只写当前有效的规则、必要用法和看代码看不出来的决定。规则变了就改原文、删掉旧内容，不追加"更新说明"。
- 代码或配置里能直接查到的清单（命令参数、文件列表）不要抄进文档。
- 过程记录交给 Git 历史；任务结果写在回复里，不另建文档。
- 规格写法见[规格写法](designs/prod/AGENTS.md)，设计稿规则见[设计规则](designs/AGENTS.md)。

## Agent skills

- 工单和规格写成 `.scratch/<功能名>/` 下的 Markdown。处理工单前读[本地工单约定](.agents/skills/setup-matt-pocock-skills/issue-tracker-local.md)。
- 分诊使用五个默认角色。分诊前读[标签映射](.agents/skills/setup-matt-pocock-skills/triage-labels.md)。
- 探索代码前读[领域文档约定](.agents/skills/setup-matt-pocock-skills/domain.md)和[词表](GLOSSARY.md)。本项目只有一个领域上下文；`docs/adr/` 下有 ADR 时读与改动相关的那几篇。
