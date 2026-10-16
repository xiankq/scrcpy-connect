# 03 · Monorepo、状态所有权与四端实际构建方案

Status: ready-for-agent
Type: research
Priority: P0
Depends on: 02
Requirements: R06–R07、R13–R15

## 问题

如何以一套 Flutter/Rust monorepo 固定依赖与绑定，并使四端核心、FRB链接和应用整包分别可构建？

## 研究输入与边界

一手依据与已有调查位于 `docs/research/`：cross-platform-build-contract.md；flutter-rust-platform-runtime.md。入口见[需求审计](../requirements-audit.md)和[任务索引](README.md)。不把文档调查、编译与真机通过混为同一状态；现行规格与用户后续纠正优先于历史研究候选。

## 工作与交付物

- 给出工作区目录、Cargo/Dart依赖方向、Flutter Hooks/Riverpod局部状态与Rust持续任务所有权、绑定生成和版本锁定规则。
- 结合依赖闭包提出正式CPU/最低OS/SDK/feature profiles，区分Android模拟器、iOS真机和模拟器；不得把示例CPU误记为只支持范围。
- 核对Cargokit/Native Assets、FRB runtime/codegen、异步取消和事件快照/游标重订阅，避免UI dispose关闭设备会话。
- 制定Linux/Windows/macOS宿主CI与产物验收，隔离JNI/USB/密钥/媒体/玻璃插件；iOS无USB后端仍可编译TCP核心。

交付到对应研究报告及能力／流程矩阵；涉及代码或画布验证时保留版本、可复现步骤与证据。依赖项约束对应实验与最终结论，资料研究可先开始。临时截图与日志样本按隐私处理后放临时目录，不把设计预览纳入 Git。

## 完成条件

- [ ] 每平台都有核心、FRB最终链接、Flutter整包的真实构建步骤和产物要求；cargo check/绑定生成不能替代。
- [ ] 构建方案覆盖媒体、玻璃、图标和平台插件完整闭包；普通主控用户无需开启调试。
- [ ] 实际执行前先有可复现最小工程和目标矩阵；没有宿主/SDK时记录缺口，不能永久跳过仍报通过。

## 当前状态

未执行本任务的工程验证；已有事实研究见输入。
