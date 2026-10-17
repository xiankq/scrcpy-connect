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

当前完整状态以[当前完成度](../current-status.md)为准；以下按批次保留证据与边界。

2026-10-17重新核查：已有锁文件、生成Dart检查、严格分析、官方设计lint和部分来源摘要。

固定scrcpy捕获扩展已有源码/产物与JVM默认门禁；FRB重生成、companion源到JAR及其JVM统一门禁、MDK逐平台原生下载/摘要/许可闭包（A41）、未跟踪真实测试与安全发布依据仍未闭合。pub锁只固定Dart包，不能冒充MDK原生产物锁定。

任务保持开放；`ready-for-agent`表示有明确工作可继续，不表示从未实施。逐需求与32流程见[完整重新核查](../completion-reassessment.md)，当前后端证据见[验收记录](../../../docs/implementation/validation.md)。

## 本轮持续门禁与职责审计：A46／A48

A46确认CI仅运行不带`--android`的`tool/check.sh`，三ABI APK和native ownership main只有条件／本地证据，没有CI门禁；补明确job及实际失败阻断后再记通过，四宿主与MDK原生摘要／许可闭包继续开放。A48确认provider冲突产品说明及选择仍在`PlatformDocuments.kt`，共享协调器主动调用平台conflict；第16批“原生仅OS适配”是过宽结论，须回迁共享产品层并复验。当前入口：[当前完成度](../current-status.md)。


## 本次逐指令复核补回的关闭条件

- [ ] A56：形成当前直接依赖→锁版→一手API／源码→使用契约→四端条件→实际验收映射，覆盖file_picker13.1.0、share_plus13.3.1、open_filex5.0.0、qr_flutter4.1.0、path_provider2.1.6、FRB hooks2.13.0／code_assets2.1.0等，不仅列候选库名称。
- [ ] mdns-sd研究0.21.5与实际0.17.2差异有明确处置；协议fuzz有可运行入口及回归种子。此要求不授权无依据升级依赖。
- [ ] 修正会诱导回归的当前指导：ADR构建状态、页面计数、离页与显式关闭、播放器所有权及SAF返回已有URI反例；研究索引必须能找到提供方专项。

源码、研究及本轮证据边界见[重新核查第22节](../completion-reassessment.md#22-用户再次要求逐指令逐文档逐设计核查)；当前状态以[权威入口](../current-status.md)为准。新增检查项尚未通过，不因写入任务自动关闭。

## A56实际锁版处置与A58

实际0.17.2已确认存在上游修复的HINFO长度越界panic，发现接收路径先于信任过滤。此次同步生产／测试依赖至精确0.21.2修复线，版本／feature／源码证据见[实际mDNS契约](../../../docs/research/locked-mdns-contract.md)。窄编译和上游离线原回归通过，真实七项DNS-SD及当前综合门禁另记，不把未运行ignored用例计通过。

- [ ] A58：修复发布锁定、坏包解析回归、真实发现／端点撤销与TLS互操作、四端依赖和编译证据分别通过；Core发现daemon终止后的清理／重建另行实施验证。

A56其余逐库契约／完整ADB fuzz、生产密码与四宿主整包继续开放。

A58解析器修复已提交`e776065`，新锁版真实DNS-SD／TLS七项77.36秒、iOS／macOS／Windows核心check、完整`tool/check.sh --android`全部通过；三ABI APK与实际manifest／ELF均核验。默认Rust186／58 ignored与显式七项分别记，不重复计数。上面的整项仍开放，因为daemon异常关闭后的重建／清理尚未实现，其余库契约／完整ADB／生产密码和宿主整包也未闭合。
