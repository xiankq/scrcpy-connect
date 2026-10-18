# scrcpy server 来源

- 上游：[Genymobile/scrcpy v5.0.1](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1)。
- 文件：`scrcpy-server-v5.0.1`，官方发布的临时 Android app_process JAR，不是 APK。
- SHA-256：`764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`。
- 原始地址：https://github.com/Genymobile/scrcpy/releases/download/v5.0.1/scrcpy-server-v5.0.1
- 许可证：随附 `LICENSE-scrcpy`（Apache-2.0）。该文件未修改。

核心在推送前校验内置字节摘要，每个会话使用独立临时文件和 socket 标识，停止后清理。主机连接、授权、流协议、输入、媒体编排由本仓库实现，不运行上游 adb/scrcpy 主机可执行程序。

视频、音频和查询统一复用此官方 JAR，不维护 scrcpy server 源码补丁或构建链。会话暂停只暂停主控本地显示，被控设备继续采集和编码；恢复通过官方 RESET_VIDEO 指令获取新的编码会话。
