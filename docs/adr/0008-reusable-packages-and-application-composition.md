---
status: accepted
---

# 通用能力拆包，产品业务归应用

`packages/` 仅保留 design_system、adb、scrcpy、media_codec；Rust 在同名 `rust/<package>/`。设备、身份选择、连接策略、文件任务、偏好和界面由 `app/` 维护。早期按产品功能拆包增加依赖与发布边界，却不能独立复用，因此收回应用，仍按状态所有者组织模块。

通用接口遵循 ADB／scrcpy 概念，不接收产品设备 ID、页面租约、后台策略或聚合 JSON 命令。应用负责窗口准入、打开记录与质量交接，按精确捕获句柄附着控制及媒体，不重复创建捕获。

无协议、互操作或性能理由的逻辑优先 Dart。FRB 和生成细节由能力包维护，应用只用公开 Dart API；组合宿主共享普通 Rust 库及单一 FRB 入口，不跨动态库传内部对象。组装见[架构](../implementation/architecture.md)。
