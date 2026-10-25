---
status: accepted
---

# 被控设备免安装，通过 ADB 临时运行服务端

被控 Android 不需 root 或配套 APK，通过已授权 USB／无线调试部署临时 scrcpy、协同 JAR 及助手，避免维护被控安装包。免安装仍执行代码，不取得系统应用权限；扩展功能按真实系统能力判断，短信等接续原应用。固定输入与清理归属见 [servers](../../servers/)及[架构](../implementation/architecture.md)。
