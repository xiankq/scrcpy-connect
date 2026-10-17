# 20 · Android 模拟器、真机与性能验收基准

Status: ready-for-agent
Type: research
Priority: P0
Depends on: 03
Requirements: R03、R17–R18、R20–R22、R39

## 问题

怎样把可调用的Android模拟器与必需真机验证组成一套可复现验收？

## 研究输入与边界

一手依据与已有调查位于 `docs/research/`：flutter-rust-platform-runtime.md；cross-platform-build-contract.md。入口见[需求审计](../requirements-audit.md)和[任务索引](README.md)。不把文档调查、编译与真机通过混为同一状态；现行规格与用户后续纠正优先于历史研究候选。

## 工作与交付物

- 盘点现有Flutter/Dart/Rust/JDK/SDK/NDK、模拟器/设备与宿主条件，只记录必要信息，不安装或虚构不存在的工具链。
- 定义API21最低被控与各能力边界、现代Android主控、AOSP与主要OEM的版本/机型矩阵，主控测试部署调试不变成产品用户要求。
- 模拟器测UI、状态、协议故障和可模拟权限；真机测USB host/双机连接、实际硬解/触控/中文IME、Doze/OEM回收、真实通话HAL与耗电。
- 建立USB/局域网/可达跨网、单会话/多窗口/后台大文件/玻璃覆盖的基准场景、采样方法、持续时长和结果留存格式。

交付到对应研究报告及能力／流程矩阵；涉及代码或画布验证时保留版本、可复现步骤与证据。依赖项约束对应实验与最终结论，资料研究可先开始。临时截图与日志样本按隐私处理后放临时目录，不把设计预览纳入 Git。

## 完成条件

- [ ] 每个验收声明都能定位环境、输入、版本、步骤和原始结果；未测、模拟器通过、真机通过分开。
- [ ] 将测量结果交任务16建立数值门槛，不凭一次演示宣称完整兼容或低延迟通过。
- [ ] 工程有Dart/Flutter改动后按环境工具要求执行reload/restart与适当运行检查；本轮无代码不伪造运行结果。

## 当前状态

2026-10-17再次核查：三独立AVD、共享媒体/文本对象隔离/外部分享导入、手机三窗口保留切换精确关闭、同UUID事件缺口恢复及独立进程检查已有证据。A37/A38/A40负例与真实typed路由回归已纳入；新增双AVD原通知UI回复、独立受管receiver原文/count1及精确清理两轮通过，测试APK临时安装且不进入产品；不把fixture测试冒充安全adbd/真实用户链路。

完整真实UI闭环、故障/旧API/安全授权/物理USB/HAL/热功耗未完成；缺完成回执的验收假绿本轮修复。

任务保持开放；`ready-for-agent`表示有明确工作可继续，不表示从未实施。逐需求与32流程见[完整重新核查](../completion-reassessment.md)，当前后端证据见[验收记录](../../../docs/implementation/validation.md)。
