# 原生媒体重构验收

本记录对应 `60d6c07028774f861a001d54f31765a995f3ba24` 之后的工作区候选版本，日期为 2026-10-23。架构责任见[当前实现职责](architecture.md)，测量定义和预算见[视频性能测量](video-performance.md)。下表只记录已执行的证据，未完成项不计作通过。

**版本边界：** 下文保留源码审计前的第一阶段结果及当时产物摘要。该阶段 Android 普通 Release 后被证实存在 R8 裁掉 JNI 回调导致打开投屏 SIGABRT，详见[崩溃证据](../research/android-release-media-crash.md)。后续已实施 keep rules、JNI 查找失败保护及各平台整改，并以新普通 Release 在 Android16 x64 AVD 验证开屏、关闭再开屏及真实画面，不能继续将旧摘要当作最新交付。最新逐项实施、复验与剩余边界见[审计整改验收](scrcpy-audit-fixes.md)。

## 固定输入

- 本机 Ubuntu 24.04 x86_64；Flutter 3.47.7、Dart 3.13.5、Rust 1.99.1、JDK 21。
- FFmpeg revision `2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e`，源归档 SHA-256 `1e789726340a8ee2646f86a3f7a29bef704dd642a0f6711ec198b8de15d0d699`。关闭 avformat、network、programs 和无关组件；AV1 软件回退为静态 dav1d 1.5.4。完整配置随各宿主构建回执交付。
- 桌面官方 platform-tools 37.0.1 的平台归档和选取文件均受锁文件校验，使用私有 adb-server，不接管用户的 5037 实例。

## Android 实际运行

主控与目标分别为 API 36 x86_64 AVD `interop-controller` 和 `interop-target`。通过现有 SDK ADB 转发访问目标 TCP adbd。视频为 H.264，最大边 720、60fps、4Mbps；目标实际输出 324×720。构建模式为 Debug，预先完成连接，计时不包含 Flutter 进程启动。

| 运行 | 首像素三轮（ms） | 24 次输入 P50 / P95（ms） | 额外证据 |
| --- | --- | --- | --- |
| 第一轮 | 596 / 559 / 526 | 133 / 180 | 真实解码计数；Flutter 只核验图像尺寸 |
| 第二轮 | 621 / 581 / 540 | 146 / 177 | 真实解码计数及 Flutter 合成 RGBA 计数逐轮一致 |

两轮均未放宽 1000ms 首像素、200ms P50、300ms P95 预算，均完成暂停恢复、精确会话释放及夹具清理。第二轮只有实际非空解码器状态才发布运行选择事件，名称为 `h264_mediacodec/mediacodec`。AVD 使用 goldfish 解码组件；这些数据不能证明实体 GPU、OEM 兼容性、P99、长稳或功耗。

独立视频生命周期用例在纹理挂载前取得真实 288×640 像素，Settings 截图包含 7139 种颜色，暂停恢复与 `nativeDeleteConfirmed` 通过。声音生命周期确认 PCM 原生接收 24576 字节，暂停时钟保持、恢复、音量/静音和释放通过；平台接收字节不等同扬声器可闻输出。

原始证据为本次系统临时目录中的 `media-codec-android-performance-{1,2}.log`、`media-codec-perf-android-{1,2}/result.json` 与音视频生命周期日志；临时文件不是仓库规范或长期交付物。

## 桌面与 Apple

| 宿主 | 已执行 | 当前限制 |
| --- | --- | --- |
| Windows x64，Intel UHD 750 / GTX 1650 | 实际 H.264 D3D11VA；严格 Profile 三轮性能、真实 Flutter 像素计数、三次暂停恢复及释放；WASAPI PCM；离线纹理回归 | 远程会话锁屏，未取得应用的操作系统屏幕截图；跨 GPU 回退没有强制实机验证 |
| Linux 本机，Intel Rocket Lake | 普通入口 Release 启动、关窗退出；实际 H.264 VAAPI、Flutter 合成 RGBA、三次暂停恢复、释放 | GPU 驱动为系统依赖，本机测试显式指定 iHD；Flutter 启动报告 DRI3 错误，不能据此认定整个合成器硬加速 |
| macOS arm64，macOS 27.0.1 / Xcode 27.1 | Flutter Debug 整包与普通入口通用 Release；实际 VideoToolbox 远控生命周期、三次暂停恢复、非黑快照与释放；AudioQueue PCM | 严格首像素预算未通过的样本保留；详见 Apple 独立记录 |
| iOS 27.1 arm64 模拟器 | Flutter 整包构建、签名和运行；实际 H.264 远控生命周期、三次暂停恢复、像素与释放；三轮严格性能 | 模拟器首帧回退软件，首像素预算未通过；不代表 iPhone 硬解或实体设备验收 |

Windows 的 D3D11 硬件上下文需要 FFmpeg 现代 `*_d3d11va2` 配置；受控 FFmpeg 的共享对象还要求同时启用旧 variant。VP8 无该上游硬解实现，保留软件回退。AV1 硬件尝试显式选择原生 `av1`，软件回退显式选择 `libdav1d`，避免默认注册顺序跳过硬解。

Windows 生命周期运行的核心启动为 826ms，随后首帧解码 81ms，原生释放通过；原先将整个 MaterialApp 的 134 种颜色当作纹理证据，可能混入 Debug banner，已撤回该呈现结论。严格计数器核对随后捕捉到真实 D3D binding failure。根因是插件独立 D3D device 的纹理指针不能直接交给 ANGLE；改为 DXGI shared handle，保留纹理拥有者引用。相同离线 Profile 回归修复前只有一种颜色，修复后三次创建、实际 AV1 解码、仅 Texture 子树回读和销毁均有 23694 种颜色，没有新增 CPU 像素下载。

修复后的 Windows 严格 Profile 三轮首像素为 754/865/818ms，24 次输入 P50/P95 为 83/97ms；三轮实际 Flutter 计数匹配、暂停恢复、精确释放、夹具卸载和独占 ADB server 清理均通过。首像素 1000ms、P50 200ms、P95 300ms 预算保持不变。Android、Linux 和 Apple 测试使用 Debug，Windows 使用 Profile，这些数值不能作为同条件跨平台排名。详见 [Windows 验收](windows-native-media-validation.md)和 [Apple 验收](apple-native-media-validation.md)。

Linux 收紧为仅 Texture 子树的生命周期复测为核心启动 485ms、首帧 47ms、2204 种合成颜色，三次暂停恢复和原生释放通过。严格 Debug 三轮首像素为 528/520/497ms，24 次输入 P50/P95 为 49/59ms；每轮真实 Flutter 计数、精确释放和夹具卸载通过。真实解码状态均为 `h264/vaapi`、硬件帧 true。三轮核心启动为 482/500/478ms，输出取得首像素为 46/20/19ms，压缩部署完成时间为 170/193/168ms。没有放宽预算。

Linux ALSA PCM 生命周期实际接收 12288 字节，暂停六次时钟采样从 6336974ms 收敛到 6336995ms 并保持，恢复推进 1280ms，音量 0.25、静音及原生释放通过。这里同样显式允许后台播放。

Windows 与 macOS 音频测试显式启用后台播放；默认策略在锁屏或未激活窗口时会暂停输出，初次超时样本保留。两者确认原生接收 12288 字节，暂停时钟收敛、恢复推进、音量/静音设置及销毁通过。混音租约不冒称系统独占焦点，接收字节不证明可闻输出。

## 实际应用组装

独立底层测试之外，`app/integration_test/media_runtime_lifecycle_test.dart` 使用实际 `DeviceRuntime.initialize`，包含 ADB 后端、Dart 偏好、准入、原生包源识别、输出创建、音频策略及状态快照合成。每轮验证真实 Texture 子树像素、暂停恢复、PCM 原生接收及播放时钟、完整快照、停止与 shutdown；没有绕过组装层直接创建播放器。

| 宿主 | 完整结果 | 运行边界 |
| --- | --- | --- |
| Linux | 通过，VAAPI 视频及 ALSA PCM | 默认禁止后台播放，实际前台 |
| Windows | 通过，D3D11VA 视频 1612 色、WASAPI PCM 12288 字节 | 锁屏，显式允许后台；默认禁止后台的超时保留，不声称前台音频验收 |
| macOS | 通过，VideoToolbox 视频 1717 色、AudioQueue PCM 8192 字节 | frontmost 为 loginwindow，实际 visible=false，显式允许后台；默认策略采样为 backgroundPaused/focusPaused、0 字节，符合暂停规则 |
| iOS 模拟器 | 通过，软件 H.264 视频 1570 色、AudioQueue PCM 4096 字节 | resumed、visible=true；产品默认后台意图为 true，平台 backgroundReady=false，前台仍可播放 |

这轮补齐了原始包源 ID 进入输出创建、桌面音频分发、前台可见性及 iOS 未声明后台能力时的前台策略。它不是性能测试；并发构建期间的启动时间不替换独立严格性能结果。

Linux 实际 `media_runtime_rotation_test.dart` 在主屏会话、Settings 前台下完成两次旋转：576×1280 → 1280×576 → 576×1280，采集和解码尺寸一致；同一 textureId、rendererGeneration=1、captureGeneration=1，三次仅 Texture 子树分别 1448/599/1430 色。恰有两次尺寸变化元数据，普通帧不向 Dart 发逐帧事件，暂停恢复、停止和释放通过。测试临时将目标设为 rotation locked 0，结束恢复原 user_rotation=1 与 FREE，并核验成功。

此前两轮 FREE 模式失败保留：没有观察到真实屏幕方向改变，不能据此判断解码尺寸更新失败。固定 scrcpy 的 [rotateDevice 实现](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/device/Device.java#L179) 在原本 FREE 时 freeze 后立即 thaw；模拟器可继续采用竖屏传感器方向。锁定是测试前置条件，未修改产品旋转规则或放宽几何断言。Rust 同时回归旧 texture/renderer/capture 回执和质量重建屏障，拒绝迟到尺寸更新且保留暂停状态。

完整 ADB 服务通过实际 API 36 AVD 与官方 37.0.1 私有 server 的 typed adapter 验证，含 duplex shell、exec、SYNC 元数据/所有广告压缩、JDWP、reverse、取消读取、失败保护与清理；范围及显式跳过的设备控制见 [flutter_adb 验收](../../packages/flutter_adb/test/README.md)。产品偏好迁移与持久化由 Dart `device_preferences` 测试覆盖，Rust 保留执行镜像与设备身份导入验证。

## 包体积比较基准

旧 fvp 通用 Release APK 已保留于 `build/verified/baseline/fvp-universal-release.apk`，59,971,009 字节，SHA-256 `55d29211eec0f903294045cf09add3b3e95350bcb370c4d75b05c94dc9826196`。它包含三 ABI 的完整 FFmpeg、MDK 与 fvp。新普通入口三 ABI 通用 Release `build/verified/android-universal-release.apk` 为 53,714,629 字节，SHA-256 `eafaed0ffe680bc3c4ce1bba51bf6b52e46a01b81a5cdb46be523fe59feb6d3f`，减少 6,256,380 字节，约 10.43%。没有用 Debug 或单 ABI 包替换比较基准。完整 ADB API 扩展使桥接库增长，因此总包降幅小于媒体库独立降幅。

新包已通过三 ABI ELF、共享 server 资源摘要、ZIP 完整性、16 KiB 页对齐、manifest 和签名检查；在主控 API 36 x86_64 AVD 实际更新安装并冷启动普通 MainActivity，确认设备页正常呈现，进程日志没有 Flutter 错误或原生链接异常。Release 使用仓库本地侧载签名，不声称商店发布。新包只有 `libmedia_codec_plugin.so`，不再附带 fvp、MDK 或通用 `libffmpeg.so`。

最终 Windows、macOS、iOS 归档摘要分别见各宿主验收记录；完整交付摘要同时记录在 `build/verified/SHA256SUMS`。macOS 为通用 Release、本机临时签名；iOS 为 arm64/x86_64 模拟器 Debug、实际运行 arm64，不能安装实体 iPhone。

Linux 普通入口最终归档 `build/verified/linux-release.tar.gz` 为 31,744,513 字节，SHA-256 `a2a07bf1a8173c7661f96101b7425edbdf43a8ceb5db4abfe06e777c58414676`。完整 build_host 通过；清空 LD_LIBRARY_PATH 后实际启动 1280×720 普通设备页，使用窗口关闭事件退出为 0，对应私有 ADB server 同步退出，未关闭用户 5037。驱动和 DRI3 限制同前述记录。

## 自动化检查

最终主应用 422 项、运行时 43 项（另 2 个显式设备用例跳过）、媒体控制与真实 Rust FFI 8 项、投屏包 98 项、构建与端到端工具 70 项均通过；投屏包完整复跑包含最后的渲染代际计数隔离。Rust workspace 完整执行并修正迁移前的责任归属断言后，368 项通过、73 项设备/网络/权限用例显式跳过；失败目标修正后独立重跑通过。独立媒体 Rust 核心 2 项通过、1 个要求显式 H.264 路径的用例跳过；另有本记录中的真实媒体运行证据。生成一致性、分析和 Rust clippy 检查通过。

被移除的 Rust 偏好持久化测试在 Dart `device_preferences` 已有迁移、损坏保护、原子提交、并发冲突、重启和导入覆盖。Rust 测试只保留执行镜像、设备身份、事件水位及原生资源规则，没有通过恢复旧业务职责来迁就旧断言。

收尾时关闭本次启动的两个 AVD 进程、测试代理及独占 ADB server，移除具体调试转发和隔离测试身份目录；目标恢复 USB adbd 与原自动旋转设置。保留用户 AVD 定义、默认 5037 server、依赖源码/许可证、复用编译缓存及五份交付归档。清理过期驱动日志约 274MB；本机最终可用空间约 45GiB。
