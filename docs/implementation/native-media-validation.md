# 原生媒体重构验收

2026-10-23 工作区验收索引。当前实现责任见[架构](architecture.md)，固定依赖、整改与最终交付见[审计总表](scrcpy-audit-fixes.md)；本页保留跨平台运行证据和仍有参考价值的测量。旧候选包和测试数量随历史版本留在git。

## 环境与测量

主机Ubuntu24.04 x86_64，Flutter3.47.7/Dart3.13.5/Rust1.99.1/JDK21；被控为API36 x86_64 AVD。桌面使用锁定platform-tools37.0.1及私有server。性能夹具为H.264、最大边720、60fps、4Mbps，实际324×720；预先连接，计时从session.start至原生可读像素，每轮末核对真实Flutter Texture计数。定义与预算见[视频测量](video-performance.md)。

| 主控/模式 | 首像素三轮ms | 24次输入P50/P95 ms | 结论 |
| --- | --- | --- | --- |
| Android API36 x64 AVD / Debug | 621/581/540 | 146/177 | goldfish MediaCodec，Flutter计数匹配，暂停恢复及释放通过 |
| Linux Intel RKL / Debug | 528/520/497 | 49/59 | h264/vaapi硬件帧，Flutter计数匹配，暂停恢复及释放通过 |
| Windows GTX1650 / Profile | 754/865/818 | 83/97 | h264/d3d11va，Flutter计数匹配，暂停恢复及释放通过 |

以上是审计前严格样本，最终整改后未重测该分布；Debug与Profile不能跨平台排名。AVD不提供实体芯片/OEM、P99、温控或长稳证据。Apple的启动预算失败样本见[Apple验收](apple-native-media-validation.md)。

## 真实产品组装

`app/integration_test/media_runtime_lifecycle_test.dart` 从DeviceRuntime.initialize执行连接、偏好/准入、包源识别、视频与声音输出、快照、暂停恢复、停止和shutdown。最终整改后的各平台均确认仅Texture子树像素、PCM接受及播放时钟推进，详细环境归各专项；输入576×1280、默认balanced，不作为性能样本。

| 主控 | 已验证后端与范围 | 特有限制 |
| --- | --- | --- |
| Android16 x64 AVD | 普通三ABIRelease实际开屏、重开和后台返回；ART callback/consumer关闭回归 | R8/JNI修复及arm64指针夹具见总表；实体arm64设备未复验 |
| Linux Intel | VAAPI→DMA-BUF→EGL真实十二帧；Texture/ALSA、暂停恢复/清理；普通Release首页启动、窗口关闭和自有ADB退出 | 需可用iHD/libdrm。DRI3警告不支持推断整个合成器硬件状态；CUDA/多GPU未验 |
| Windows x64 | D3D11VA/DXGI Texture、WASAPI、完整清理；普通main窗口 | 必须交互会话成像；显式允许后台音频。见[Windows](windows-native-media-validation.md) |
| macOS arm64 | VideoToolbox硬件、Texture/AudioQueue、完整清理 | 显式允许后台音频，见[Apple](apple-native-media-validation.md) |
| iOS arm64模拟器 | 软件H.264、Texture/AudioQueue、前台完整组装 | iphoneos仅无签名SDK编译，未做实体iPhone验收 |

平台PCM接收和时钟推进没有声学输出证据。解码、平台准备、Flutter合成分别取证；最终呈现没有公开跨平台scanout回执。

## 旋转与归属

Linux `media_runtime_rotation_test.dart` 真实完成576×1280→1280×576→576×1280，同一texture/renderer/capture代际，两个尺寸元数据、普通帧无逐帧Dart事件，暂停恢复和释放通过。目标必须先锁定rotation0，结束恢复原user_rotation及FREE；scrcpy在FREE时freeze后thaw，AVD传感器可维持竖屏，因此未观察到方向改变的运行不能作为尺寸链路失败。迟到texture/renderer/capture回执及画质重建屏障由Rust/Dart回归覆盖。

完整ADB typed adapter范围见[adb验收](../../packages/adb/test/README.md)。偏好持久化/迁移由应用 Dart 偏好模块覆盖，Rust只保留执行镜像、身份、事件与原生资源规则。

## 复现入口

- 视频：`app/integration_test/video_performance_test.dart`、`tool/driver/video_performance.dart`；方法和隔离前置见[重复测量](video-performance.md#重复测量入口)。
- 组装/旋转：`app/integration_test/media_runtime_lifecycle_test.dart`、`media_runtime_rotation_test.dart`及对应driver。
- 原生：`packages/media_codec/native/tests/README.md`；Linux/Windows/darwin tests分别覆盖真实平台import/PCM。源ABI、FFI、分配故障与所有权结果见[整改总表](scrcpy-audit-fixes.md)。
- 普通包：`tool/build_host.dart`与[Android打包](android-packaging.md)。最终SHA及签名/架构范围只维护于[交付表](scrcpy-audit-fixes.md#最终普通入口交付)。

本轮自有模拟器、测试安装、代理、转发和独占ADB已清理，目标恢复USB adbd及旋转；受控输入、许可证、最终交付与复用缓存保留。
