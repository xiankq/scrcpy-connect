# 互联活动核心

`Runtime::initialize(private_directory)` 返回共享运行时；`invoke(command, params)`
是设备、会话、通知、剪贴板和声音的异步执行边界，`subscribe()`
提供有界实时事件。界面不直接管理 ADB socket 或目标临时进程。

移动主控使用相邻的 `interop-adb` 直接连接 adbd；桌面主控由 `flutter_adb`
准备随包原版 ADB，并经其私有 server 的 smart socket 执行服务。不会查找系统
PATH 中的 adb，也不调用 scrcpy 主机。
固定的 scrcpy JAR、免安装 Binder companion 和四 ABI 原生文件服务位于
[`servers`](../../servers/)，其来源、构建与摘要分别记录在对应目录。
系统版本、ADB feature 与实际权限分别判断，低版本元数据和进程回收的
契约及证据见[被控兼容边界](../../docs/implementation/android-target-compatibility.md)。

应用通过 `initialize_with_settings` 注入 Dart 提供的执行镜像；独立
`initialize` 只提供执行参数，设置默认为空。Runtime 拥有单次连接、健康探测、
资源清理与可信发现缓存；配对后发现、USB 记录选择、转 IP 重试、自动重连
和能力说明由 Dart 调用方组织。`adb.*` 命令返回原始执行或探测事实，显式操作
租约受取消、身份变化及到期回收约束，不自行重试。媒体启动要求调用方传入
具体画质参数，预设展开和偏好合并在 Dart 完成。
`interop-adb` 只负责底层协议，不依赖这些业务命令、偏好或事件。

调用方须提供平台私有目录。Dart 拥有产品偏好和文件任务日志，Rust 拥有设备
身份与执行租约；Unix
目录权限为 0700，私钥为 0600。导出设备元数据不包含身份。应用不得把该目录
作为系统文件导出来源。事件中的媒体 token、通知正文和剪贴板不得写入日志。

媒体通过进程内 SinkV1 C ABI 将完整 scrcpy 视频包与 PCM 送往本机解码器；
无 HTTP、MKV 或 Dart 字节中转。配置和数据带输出代际，detach 同步等待回调排空。
传输入口不等于已渲染或已播放；平台必须报告真实首帧／首次播放结果。

`file_execution` 仅提供有界 stat/list、受取消的原生文件复制和原子提交事实；
目录遍历、筛选排序、搜索、相册快照、任务冲突/恢复及日志归
[`device_files`](../../packages/device_files/)。文件先暂存并验证，再由 Dart
持久化 finalizing 后提交；未知结果不自动重放，目录任务不保证整体事务。

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

真实设备测试默认忽略，必须显式提供隔离目标；运行方法、实际通过范围和
未验证项见[验收记录](../../docs/implementation/validation.md)。单元测试通过
不表示 Android/OEM 或四端应用整包均已验收。当前密码提供器为 experimental；
具体通话控制、通话音频等能力与验证边界见[设备流程证据](../../docs/implementation/validation.md#设备与系统证据)及[流程覆盖](../../designs/prod/coverage.md)。
