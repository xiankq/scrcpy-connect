# 02 · ADB 依赖纯度、密码学成熟度与复用路线

Status: ready-for-agent
Type: research
Priority: P0
Depends on: 无
Requirements: R08–R09、R40

## 问题

在四端可构建与安全成熟度约束下，怎样尽量使 ADB 依赖链保持纯 Rust？

## 研究输入与边界

一手依据与已有调查位于 `docs/research/`：pure-rust-adb-dependencies.md；cross-platform-build-contract.md。入口见[需求审计](../requirements-audit.md)和[任务索引](README.md)。不把文档调查、编译与真机通过混为同一状态；现行规格与用户后续纠正优先于历史研究候选。

## 工作与交付物

- 固定libadb/DroidMux及替代组合，逐目标审计normal/build依赖、feature叠加、源码/预编译C与ASM、许可证和更新责任。
- 核查TLS provider生产状态、RSA advisory实际私钥调用路径、AOSP SPAKE2变体、AUTH DigestInfo与TLS-PSS；不以连通性替代密码学发布条件。
- 验证nusb、发现、Brotli/LZ4/Zstd双向流式压缩，坏帧、取消、内存上界及ruzstd错误传播。
- 比较软件Rust与系统signer路线；必要系统API与捆绑原生实现分别列账，未获接受的原生密码后端不得作为默认结论。

交付到对应研究报告及能力／流程矩阵；涉及代码或画布验证时保留版本、可复现步骤与证据。依赖项约束对应实验与最终结论，资料研究可先开始。临时截图与日志样本按隐私处理后放临时目录，不把设计预览纳入 Git。

## 完成条件

- [ ] 给出可重建的目标feature闭包、实际编译/链接证据及未通过原因；不把lockfile出现依赖等同实际启用。
- [ ] 配对/TLS/旧AUTH与官方实现互操作，安全警告和维护方案有明确处置。
- [ ] 若纯Rust路线受阻，先交具体证据和最小例外范围；未获授权不替用户批准例外。

## 当前状态

2026-10-17重新核查：已有依赖/feature调查并实际使用纯Rust协议/密码路线。

RustCrypto生产警告、RSA时序风险、安全评估与四端正式依赖闭包仍未解决。

任务保持开放；`ready-for-agent`表示有明确工作可继续，不表示从未实施。逐需求与32流程见[完整重新核查](../completion-reassessment.md)，当前后端证据见[验收记录](../../../docs/implementation/validation.md)。
