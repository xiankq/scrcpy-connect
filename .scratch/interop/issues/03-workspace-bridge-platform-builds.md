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

当前完整状态以[当前完成度](../current-status.md)为准；以下按批次保留证据与边界。

2026-10-17重新核查：monorepo、FRB、生成路由/状态、Android整包和部分跨target check已完成。

手机持续窗口、事件缺口快照和播放器所有权已有新证据；Apple/Windows宿主最终链接/整包、平台资格配置、FRB/companion/MDK一致性门禁与完整活动恢复仍缺。

任务保持开放；`ready-for-agent`表示有明确工作可继续，不表示从未实施。逐需求与32流程见[完整重新核查](../completion-reassessment.md)，当前后端证据见[验收记录](../../../docs/implementation/validation.md)。

## 本轮工程核查：A46／A48

本地Android三ABI整包通过不等于持续门禁：`.github/workflows/check.yml:38`没有传`--android`，所以`tool/check.sh`条件内的APK构建和native ownership main没有CI覆盖（A46）。下一步明确Android CI入口，实际job验证构建／测试失败会阻断。Apple／Windows宿主整包和最终链接仍另行验收。

A48还发现`PlatformDocuments.kt:94`仍用产品AlertDialog决定同名保留／跳过／取消，共享协调器调用`documents.platform.conflict`；应将策略／产品UI归共享Dart，原生保留系统授权／provider／FD适配，并回归离页／取消／迟到结果。当前状态见[当前完成度](../current-status.md)。

后续A46配置已显式调用`./tool/check.sh --android`，并加入此前未执行的audio JVM runner、实际APK三ABI Flutter／Rust ELF与manifest核验、成功产物留存。三ABI构建106.8秒、4组native main检查通过；首个包检查误把apkanalyzer数值枚举当成错误，依据固定API36 SDK和官方常量修正后，原Android脚本分支重新构建11.1秒并全部通过。损坏arm64 Rust ELF头的独立负例被精确拒绝。远端CI未运行、分支保护未配置；Apple／Windows整包和原生产物闭包不据此关闭，详见[验收](../../../docs/implementation/validation.md)。


## 本次逐指令复核补回的关闭条件

- [ ] A48扩展：共享层接管多USB设备选择及系统目录冲突的产品状态／UI，原生只做枚举、授权与句柄；不把目标临时JAR或测试fixture APK混同用户前提。
- [ ] A56：实际直接依赖的固定API／系统条件和四端编译闭包逐项对应，FRB hooks／code_assets及媒体原生产物不以Dart锁文件代替。
- [ ] 当前实施指导同步离页保留／协作暂停、显式关闭才stop与共享呈现所有权；Android已构建，其他宿主未验，不能沿用ADR的旧状态。

源码、研究及本轮证据边界见[重新核查第22节](../completion-reassessment.md#22-用户再次要求逐指令逐文档逐设计核查)；当前状态以[权威入口](../current-status.md)为准。新增检查项尚未通过，不因写入任务自动关闭。

2026-10-18用户默认APK反馈：已复现并修复A60未签名release成功包及单ABI不完整插件架构。新增签名初始化／最终APK独立校验、Gradle任务缓存；默认三ABI真实release签名与首次安装／启动／同签名更新通过，同源重复10.760秒。[完整范围](../../../docs/implementation/android-packaging.md)。四端最终链接和干净远端job仍独立开放，不以本地Android结果代替。
