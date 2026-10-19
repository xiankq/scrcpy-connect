---
status: accepted
---

# 被控设备免安装，通过 ADB 临时运行服务端

被控 Android 设备无需 root，也不安装配套 APK。连接以该设备开启 USB 或无线调试并完成授权为前提；主控通过 ADB 部署并临时运行 scrcpy 与必要的协同 JAR、助手。

免安装不等于被控设备不执行代码，也不等于主控获得系统应用权限。通知、通话等扩展能力按被控系统实际提供的能力判断；接口存在不构成跨 ROM 可用承诺。短信等应用内容通过通知接续原应用，不建设独立短信数据服务。

临时产物的固定版本、构建输入和清理责任见 [servers](../../servers/)及[架构](../implementation/architecture.md)。该执行模型与[主控免调试](0006-controller-without-debugging.md)同时成立。
