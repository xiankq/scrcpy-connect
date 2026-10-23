# Windows 原生媒体验收记录

2026-10-23 工作区证据。当前实现见[架构](architecture.md)，逐项D01–D24见[桌面整改](scrcpy-audit-desktop-fixes.md)；依赖身份与最终包摘要只维护于[总表](scrcpy-audit-fixes.md)。旧候选、逐轮构建流水和已替换摘要由git追溯。

## 环境与运行要求

真实Windows x64、Intel UHD750/NVIDIA GTX1650，MSVC `/W4 /WX`、Flutter3.47.7/Rust1.99.1，固定FFmpeg profile3；目标API36 x64 AVD。构建为普通 `lib/main.dart` Release，官方ADB为独立i386进程，Flutter/Rust/插件为x64。私有ADB及测试身份与默认5037隔离。

Flutter成像必须在已登录用户交互会话运行；SSH Session0可解码却未被raster消费，`toImage`失败，不能据此判定解码失败。锁屏音频样本显式允许后台播放，默认禁止后台时0字节/超时属于资格限制。

## 解码、呈现与音频

独立D3D设备的texture指针不能直接交ANGLE；现导出DXGI shared handle并保留拥有者引用。软件上传选择Flutter适配器，同卡硬解GPU转换共享，跨卡可CPU读回上传；本轮未强制双GPU。Flutter consumer完成fence尚无公开契约，见桌面D18。

| 已执行入口 | 实际结果 | 范围 |
| --- | --- | --- |
| `native/tests` Flutter离线AV1回放 | 交互会话三次创建/解码24帧/释放，隔离Texture均23229色，libdav1d、cpu/dxgi | AV1硬件拒绝后的正常软件回退；不是AV1硬解证据 |
| `windows/tests` CTest | 生产WASAPI event写入、IAudioClock、pause/reset/resume/generation、同线程close及core lifecycle通过 | 静音PCM无声学输出证据 |
| `media_runtime_lifecycle_test.dart` | 实际h264/d3d11va、hardwareVerification=hardware、576×1280；Texture1966色、d3d11va/dxgi、无presentationError；PCM8192字节及播放时钟，快照/暂停恢复/停止/shutdown | 后台播放显式允许，不是延迟测试 |
| 私有ADB关闭回归 | 失败owner可重试、并发去重、成功幂等；真实独立server退出/端口关闭，无关listener保留 | 完整A/V重跑退出后自有PID/端口消失，无手工kill；默认5037未操作 |

只对Texture子树取像素；此前整个MaterialApp颜色计数已撤回为视频证据。平台准备回执没有提供Flutter scanout完成，实体热插拔、强制跨GPU、长期漂移未验。

## 严格性能样本

审计整改前Profile三轮、每轮八次输入；H.264实际D3D11VA，预算首像素1000ms、输入P50 200ms/P95 300ms未放宽。

| 指标 | 实测 |
| --- | --- |
| session.start至首个原生可读像素 | 754/865/818ms |
| 24次输入至原生可读像素 | P50 83ms，P95 97ms |
| 额外断言 | 每轮Flutter Texture counter匹配、暂停恢复、精确释放、夹具卸载和私有ADB退出 |

预先已连接，不含Flutter进程启动、首次授权或夹具安装。输入终点包含snapshot轮询/识别，仅轮末另验Flutter合成，未测每次输入的面板延迟。最终整改后未重测该分布，不能与Debug宿主作速度排名。测量入口见[视频性能](video-performance.md)。

## 普通启动 ERROR_INVALID_FUNCTION 修复

真正main的outgoingMediaDirectory→media.cache.configure曾在canonical Windows路径返回错误1。根因是逐组件查询把 `Prefix(VerbatimDisk)`（如 `\\?\C:`）当作完整目录；追加RootDir后才可查询。现仅跳过Prefix自身，仍检查根及后续组件、拒绝相对路径/junction并保留真实I/O错误。旧DeviceRuntime组装绕过普通bootstrap，未覆盖此缺口。

`crates/interop_core/tests/runtime_startup.rs` 在真实Windows无ADB/GUI下复现修前错误，修后canonical登记/重开和junction拒绝均通过。Windows MSVC工具终端入口：

```sh
cargo test --release -p interop-core --test runtime_startup -- --nocapture
```

`app/integration_test/application_bootstrap_test.dart` 调用真正application.main，仅隔离support/temp目录，不替换ADB/Core或缓存登记。Profile运行确认ConnectApp存在、无StartupErrorPage、缓存状态可读和真实设备首页。入口：

```sh
cd app
flutter drive --profile -d windows --target=integration_test/application_bootstrap_test.dart --driver=../tool/driver/application_bootstrap.dart
```

最终普通Release由本轮ZIP新解压后在交互会话直接启动，实际窗口进入添加设备界面，生产日志 `bootstrap.ready`，正常关窗exit0且私有ADB退出。含二维码截图已删除，集成测试无凭据首页图保留。一次被控制台中断的重复不计通过；未取得冷启动时间上限。

## 交付与复现

普通包通过 `tool/build_host.dart windows` 的架构、裁剪回执、许可证及官方ADB检查；最终ZIP CRC全部通过，无测试/replay入口。大小/SHA归[交付表](scrcpy-audit-fixes.md#最终普通入口交付)，不再保留被替换包摘要。应重新解压当前ZIP；构建工具不维护旧解压目录。

原生夹具见 `packages/media_codec/windows/tests/`，离线纹理与固定输入见[原生测试说明](../../packages/media_codec/native/tests/README.md)，组装/性能/普通启动见上文入口。远端源码与构建日志保留；本轮计划任务、反向隧道、测试身份和自有ADB已清理，未操作其他应用或默认server。
