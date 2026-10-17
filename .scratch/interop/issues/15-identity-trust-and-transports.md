# 15 · 主控密钥、授权撤销与多路径设备身份

Status: ready-for-agent
Type: research
Priority: P0
Depends on: 02
Requirements: R04–R05、R10、R40

## 问题

如何本机保管主控身份，避免恢复旧设备名、IP变化或多路径造成误授权与误合并？

## 研究输入与边界

一手依据与已有调查位于 `docs/research/`：adb-host-and-connectivity.md；pure-rust-adb-dependencies.md。入口见[需求审计](../requirements-audit.md)和[任务索引](README.md)。不把文档调查、编译与真机通过混为同一状态；现行规格与用户后续纠正优先于历史研究候选。

## 工作与交付物

- 比较软件受保护密钥与平台signer完成AUTH/配对/TLS同一身份的可行性，系统备份排除、锁屏使用、丢失、重装和重新授权。
- 不自动迁移私钥；元数据可独立恢复并显示待重新授权。显式导入未定为产品能力，不自动新增入口。
- USB serial、GUID、IP、型号、transport_id和主控key不能单项证明同一物理设备；设计证据关联、冲突不合并和手动重新识别。
- 区分本机忘记、远端撤销、授权过期、端口变化与不可达；不自动循环弹授权，不为身份关联偷偷在被控持久化标识。

交付到对应研究报告及能力／流程矩阵；涉及代码或画布验证时保留版本、可复现步骤与证据。依赖项约束对应实验与最终结论，资料研究可先开始。临时截图与日志样本按隐私处理后放临时目录，不把设计预览纳入 Git。

## 完成条件

- [ ] 同型号两机、USB+无线、DHCP/IP复用、mDNS重命名、被控重置和旧缓存均有可复现关联结果。
- [ ] 备份/换机恢复测试证明身份不自动迁移，秘密不进入日志或诊断包。
- [ ] 所有新增持久身份/密码例外有证据和明确范围，未授权不静默引入。

## 当前状态

2026-10-17重新核查：本机身份和元数据恢复分离已测；USB/连接取消租约已实现。

安全adbd授权/撤权、多路径身份、四端私钥保护/备份排除和物理USB仍待闭环。A37已将legacy TCP/USB和现代TLS分开，Required及发现/表单/保存/恢复路径保留TLS，明文CNXN/AUTH零凭据拒绝有公开负例；正向互通和这些负例仍不等于生产信任矩阵完成。

任务保持开放；`ready-for-agent`表示有明确工作可继续，不表示从未实施。逐需求与32流程见[完整重新核查](../completion-reassessment.md)，当前后端证据见[验收记录](../../../docs/implementation/validation.md)。

## 首次配对后续（2026-10-17）

隔离secure=1 API36 AVD已跑真实app.main/FRB/Rust身份：未配对拒绝→错码拒绝→系统新码PAKE→独立端口Required TLS→系统接口精确撤权→旧身份拒绝及停止重连→精确清理，64秒通过。Core CertificateUnknown误归offline已公开红绿回归并修复。直接Settings Forget因AtomicFile持久化竞争仍失败，未算入上述通过；host夹具固定API36且不成为用户调试/root前提。

任务保持开放：QR/mDNS/过期/切网/切后台/USB/旧系统、量产/OEM/重装/四端身份保护及成熟密码链尚未闭合；普通用户表单仍暴露英文证书原错。完整范围、失败与重跑入口见[首次配对](../../../docs/implementation/first-pairing.md)和[当前差距](../completion-reassessment.md#122-当前差距按完整产品而非单次实验判断)。
