# 互联活动核心

`Runtime::initialize(private_directory)` 返回共享运行时；`invoke(command, params)`
是设备、会话、文件任务、通知、剪贴板和声音的异步命令边界，`subscribe()`
提供有界实时事件。界面不直接管理 ADB socket 或目标临时进程。

运行时使用相邻的 `interop-adb` 直接连接 adbd，不调用系统 adb 或 scrcpy 主机。
固定的 scrcpy JAR、免安装 Binder companion 和四 ABI 原生文件服务位于
[`servers`](../../servers/)，其来源、构建与摘要分别记录在对应目录。
系统版本、ADB feature 与实际权限分别判断，低版本元数据和进程回收的
契约及证据见[被控兼容边界](../../docs/implementation/android-target-compatibility.md)。

调用方须提供平台私有目录。设备偏好、传输进度与主机身份分开存储；Unix
目录权限为 0700，私钥为 0600。导出设备元数据不包含身份。应用不得把该目录
作为系统文件导出来源。事件中的媒体 token、通知正文和剪贴板不得写入日志。

媒体通过一次性随机 token 保护的回环 socket 交给本机平台解码器。启动返回
传输入口不等于已渲染或已播放；平台必须报告真实首帧／首次播放结果。文件
先暂存并验证，再提交；结果未知时不自动重放提交，目录任务不保证整体事务。

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

真实设备测试默认忽略，必须显式提供隔离目标；运行方法、实际通过范围和
未验证项见[验收记录](../../docs/implementation/validation.md)。单元测试通过
不表示 Android/OEM 或四端应用整包均已验收。当前密码提供器为 experimental；
具体通话控制、通话音频等能力与验证边界见[产品验收](../../docs/implementation/product-refinement.md)及[流程覆盖](../../designs/prod/coverage.md)。
