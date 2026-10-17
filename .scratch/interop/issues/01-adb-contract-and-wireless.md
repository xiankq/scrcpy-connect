# 01 · 完整 Rust ADB 契约与新版无线行为对照

Status: ready-for-agent
Type: research
Priority: P0
Depends on: 无
Requirements: R08–R11

## 问题

怎样以固定 AOSP/发行包为基线交付完整主机库，并在自有 Rust 主机中实现新版无线发现与重连行为？

## 研究输入与边界

一手依据与已有调查位于 `docs/research/`：adb-host-and-connectivity.md；requirements-gap-verification.md。入口见[需求审计](../requirements-audit.md)和[任务索引](README.md)。不把文档调查、编译与真机通过混为同一状态；现行规格与用户后续纠正优先于历史研究候选。

## 工作与交付物

- 逐项对照版本协商、AUTH/STLS/TLS/SPAKE2、发现、USB/TCP、流复用/背压、shell/exec/cmd/abb、sync、forward/reverse、包管理及条件服务，建立 API 与验证账本。
- 明确5037适配、incremental/fastdeploy等的归属及理由；不将完整库缩成产品若干命令，也不把重写adbd列入目标。
- 同时固定Platform Tools发行包版本/摘要、AOSP源码提交和设备build；不假定二进制等于某main提交。核对37.0.1发布说明与通用页面的mDNS后端差异。
- 区分Android11–16无线、17 Wi-Fi2、旧TCP、pair/connect端口、服务元数据、IPv6 scope、多网卡/VPN；验证配对成功但连接失败与网络回来后重连。

交付到对应研究报告及能力／流程矩阵；涉及代码或画布验证时保留版本、可复现步骤与证据。依赖项约束对应实验与最终结论，资料研究可先开始。临时截图与日志样本按隐私处理后放临时目录，不把设计预览纳入 Git。

## 完成条件

- [ ] 每个承诺服务都有Rust API/平台条件/官方参考用例及失败语义；未完成和设备不支持分开。
- [ ] 无线参考行为与自有实现差异逐项记录，mDNS丢失仍可手动连接；不依赖外部adb运行。
- [ ] 对照官方ADB的协议、取消/尾部数据/坏帧/背压和跨网可达条件可重复验证；当前未实验的项不勾通过。

## 当前状态

当前完整状态以[当前完成度](../current-status.md)为准；以下按批次保留证据与边界。

2026-10-17重新核查：独立ADB库及配对/TLS、压缩、reverse、JDWP已有实现与真实互操作。

公开服务完整契约、版本/Wi-Fi2行为、安全授权负例及恢复矩阵仍未闭合。A37已补Required策略及发现/typed路由/表单/devices.add全链类型；修改已有TLS/GUID记录不能降级，公开Client/Core负例及入口widget通过。安全授权与完整无线兼容矩阵仍开放。

任务保持开放；`ready-for-agent`表示有明确工作可继续，不表示从未实施。逐需求与32流程见[完整重新核查](../completion-reassessment.md)，当前后端证据见[验收记录](../../../docs/implementation/validation.md)。

## 首次配对后续（2026-10-17）

隔离secure=1 API36 AVD已跑真实app.main/FRB/Rust身份：未配对拒绝→错码拒绝→系统新码PAKE→独立端口Required TLS→系统接口精确撤权→旧身份拒绝及停止重连→精确清理，64秒通过。Core CertificateUnknown误归offline已公开红绿回归并修复。直接Settings Forget因AtomicFile持久化竞争仍失败，未算入上述通过；host夹具固定API36且不成为用户调试/root前提。

任务保持开放：QR/mDNS/过期/切网/切后台/USB/旧系统、量产/OEM/重装/四端身份保护及成熟密码链尚未闭合；普通用户表单仍暴露英文证书原错。完整范围、失败与重跑入口见[首次配对](../../../docs/implementation/first-pairing.md)和[当前差距](../completion-reassessment.md#122-当前差距按完整产品而非单次实验判断)。

## 本轮契约核查：A47

`crates/adb/README.md:148`当前把typed forward、包管理、delayed ACK、incremental install、5037兼容server列为API外；这没有关闭本任务对forward／包管理／条件服务和5037归属的要求。下一步按固定AOSP逐服务给出已有原语／公开API／失败语义／参考用例／未实现与正式边界理由，不把README排除当成用户已经接受的缩scope。首次安全AVD码配对／系统接口撤权已有局部证据，成熟密码链、量产OEM和完整无线矩阵仍开放。当前结论统一见[当前完成度](../current-status.md)，发现证据见[第20节](../completion-reassessment.md#20-本轮当前账本与新增断链2026-10-17)。


## 本次逐指令复核补回的关闭条件

- [ ] A52：产品发现／自动重连遍历同可信服务的候选端点，真实验证首项不可达、次项可达、端口变化及切网；库API存在不算产品已接通。
- [ ] A56：核查实际锁定mdns-sd0.17.2与研究0.21.5的行为差异，不自动升级；兑现可运行协议fuzz入口、取消／坏帧／流控和参考互操作关闭条件。

源码、研究及本轮证据边界见[重新核查第22节](../completion-reassessment.md#22-用户再次要求逐指令逐文档逐设计核查)；当前状态以[权威入口](../current-status.md)为准。新增检查项尚未通过，不因写入任务自动关闭。
