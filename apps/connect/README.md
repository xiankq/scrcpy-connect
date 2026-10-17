# 邻接 Android 主控

设备列表是首屏，选择设备后进入工作台；远控使用全屏纹理与可拖动/吸附退出控件。生产数据来自 Rust 核心，不注入示例设备。被控端通过系统 ADB 调试授权，不安装 APK；主控使用网络或 Android USB 授权，不要求开启调试。

## 构建

仓库为 Dart/Cargo monorepo。在根目录执行 `flutter pub get`，配置 Android SDK/NDK 后从本目录 `flutter run -d <device>`。Flutter 原生 assets hook 自动构建 Rust FRB 库，无需外部 adb 可执行文件参与应用运行。Rust 与 Flutter/Dart 版本见根工具链和锁文件。

`flutter test` 运行组件、状态、手势、导航和分享/音源策略测试。真实设备连接、共享fvp/MDK视频与音频测试及已知边界见 [验收记录](../../docs/implementation/validation.md)。旧自写AudioTrack循环已删除，其历史结果不替代当前链路。官方 adb 仅用于测试部署与对照。

视觉值来自 [designs/design.md](../../designs/design.md)，共享组件位于 packages/design_system。设备与活动生命周期由 crates/interop_core 管理，经 packages/interop_bridge 与原生媒体/USB/后台适配连接。目标与未完成验收项见 [.scratch/interop/goal.md](../../.scratch/interop/goal.md)，安装包可启动不代表全部产品目标完成。
