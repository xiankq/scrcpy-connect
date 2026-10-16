# 19 · 依赖许可、版本维护与交付证据治理

Status: ready-for-agent
Type: research
Priority: P1
Depends on: 02, 03, 06, 07, 16
Requirements: R07–R16、R43–R44、R50

## 问题

怎样让可复用库、JAR、媒体二进制、图标和设计工具的版本与许可长期可核查？

## 研究输入与边界

一手依据与已有调查位于 `docs/research/`：pure-rust-adb-dependencies.md；scrcpy-media-and-server.md；design-system-and-toolchain.md。入口见[需求审计](../requirements-audit.md)和[任务索引](README.md)。不把文档调查、编译与真机通过混为同一状态；现行规格与用户后续纠正优先于历史研究候选。

## 工作与交付物

- 固定Rust/Flutter/FRB/codegen、ADB参考、server JAR、fvp/MDK、玻璃、图标/字体等版本与摘要，区分发布包/源码HEAD/实验版本。
- 核查fork、原生产物、MDK/FFmpeg变体、Lucide包装及Iconify后备的实际许可/声明与分发边界；ADB纯度不外推为Flutter runner无C++。
- 定义升级时协议/权限/最低版本/feature闭包/四端构建/Android回归的影响检查，避免‘latest’长期失真。
- 将官方DESIGN.md lint、链接/任务引用、设计token来源和产物临时目录规则纳入后续仓库检查方案；手工检查已做不虚构现成CI。

交付到对应研究报告及能力／流程矩阵；涉及代码或画布验证时保留版本、可复现步骤与证据。依赖项约束对应实验与最终结论，资料研究可先开始。临时截图与日志样本按隐私处理后放临时目录，不把设计预览纳入 Git。

## 完成条件

- [ ] 版本/许可/依赖闭包与产物对应，可复现和更新；不能只凭顶层包平台标签或许可证推断全部。
- [ ] 本轮已归档的研究分支不重新进入执行任务，已答问题不再变成问卷。
- [ ] 形成实际工程阶段可执行的检查清单与责任范围；未实现自动化明确标待实施。

## 当前状态

2026-10-17重新核查：已有锁文件、生成Dart检查、严格分析、官方设计lint和部分来源摘要。

FRB重生成、companion源到JAR、JVM统一门禁、未跟踪真实测试和安全发布依据仍未闭合。

任务保持开放；`ready-for-agent`表示有明确工作可继续，不表示从未实施。逐需求与32流程见[完整重新核查](../completion-reassessment.md)，当前后端证据见[验收记录](../../../docs/implementation/validation.md)。
