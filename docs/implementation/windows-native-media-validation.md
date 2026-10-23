# Windows 原生媒体验证记录

2026-10-23 对本轮尚未提交的媒体迁移工作区执行。前文记录早期迁移验收；审计整改后的复验单独记于文末，不能把早期性能值当作新版本重测。本文记录指定宿主、入口与样本，不承担平台支持规格；当前架构见 [ADR 0007](../adr/0007-capability-packages-and-native-media.md)，构建输入与产物规则见[工具链契约](repository-tooling.md)。

## 环境与证据范围

| 项目 | 实际环境 |
| --- | --- |
| 主控宿主 | Windows 11 x64，10.0.26300；Intel Core i7-11700，8 核 16 线程 |
| GPU 与驱动 | Intel UHD Graphics 750 / 32.0.101.7088；NVIDIA GTX 1650 / 32.0.16.1088；另有 Oray、GameViewer 虚拟显示适配器 |
| 工具链 | Flutter 3.47.7、Dart 3.13.5、Rust 1.99.1；Visual Studio 2022 Community、MSVC 14.44.35207、Windows SDK 10.0.26100.0；实际安装 ATL 组件后整包编译通过 |
| 被控目标 | 单一获授权 API 36 x86_64 AVD，通过受控 TCP 代理访问；没有测试物理 Android 或其他设备 |
| 桌面状态 | Windows 会话锁屏。WTS 状态核验确认锁定；系统屏幕抓取只取得锁屏背景，不作为产品画面证据 |
| 媒体输入 | 原始压缩包通过 SinkV1 进入 Rust FFmpeg 核心，无 HTTP、MKV 或 AVFormat |

工具和源码部署在任务新建的隔离目录，不覆盖既有项目。测试使用独立身份、ADB server 和夹具；不接管用户默认 ADB server。固定 FFmpeg、dav1d、nv-codec-headers 的来源和摘要见 `packages/media_codec/third_party/`，依赖源码、许可证与仍在复用的编译缓存保留。

下述离线纹理、严格性能和早期 PCM 测试直接创建原生输出或调用 core 接口；另有独立的真实 `DeviceRuntime` 组装验证，分别记录。各项证据均不证明物理屏幕发光、实体 Android、长期温升、并发多视频或其他 GPU 驱动兼容。

## 纹理绑定失败、修复与回归

初次 Windows Profile 严格性能测试完成首轮原生可读像素更新，但 Flutter 报 `Binding D3D surface failed`，最终纹理 counter 为 null。该轮启动 856 ms，八次输入到原生可读像素为 51–86 ms；仍判定整轮失败，未因解码或时间达标而算作呈现通过。

离线最小复现不连接 ADB：固定 FATE AV1 原包进入同一 Rust 核心，再由真实 Windows 插件交给仅包含 `Texture` 的 `RepaintBoundary`。修复前图像只有一种颜色，并报相同绑定错误。

原因是插件把独立 D3D 设备创建的 `ID3D11Texture2D*` 作为直接纹理交给 Flutter。ANGLE 的直接纹理入口要求完全相同的 D3D device；Flutter 的另一入口可从 DXGI shared handle 打开同适配器资源。现改为导出 `IDXGIResource::GetSharedHandle`，交给 `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`，并保留资源拥有者引用直到 Flutter 打开资源。[ANGLE 校验实现](https://chromium.googlesource.com/angle/angle/+/refs/heads/main/src/libANGLE/renderer/d3d/d3d11/Renderer11.cpp)、[Flutter 纹理导入实现](https://api.flutter.dev/windows-embedder/external__texture__d3d_8cc_source.html)。

软件上传设备使用 Flutter 实际渲染适配器。同适配器硬解输出保持 GPU 转换和共享；若解码与 Flutter 属于不同 GPU，使用已有 CPU 回读并上传到 Flutter 适配器。这条跨适配器回退是实现边界，本次没有强制切换到另一 GPU 验证。

最终离线回归连续创建、解码和释放三次，每次解码全部 24 帧，真实 Flutter 纹理读取均为 23,694 色，测试通过。该宿主 AV1 硬解不可用，实际回退 libdav1d，再通过 GPU 上传呈现。mock sink 源码以 MSVC `/W4 /WX` 编译通过；Dart 测试及 driver 静态分析通过。复现入口与固定夹具摘要见[原生测试说明](../../packages/media_codec/native/tests/README.md)。

先前生命周期测试把整个 `MaterialApp` 作为截图对象，得到 134 色。文字抗锯齿或 debug banner 可能独立满足颜色断言，因此撤回其作为“视频纹理已呈现”的独立证据。现有生命周期入口已缩至纹理子树，本记录的 Windows 呈现结论以离线隔离纹理回归和下述严格 counter 匹配为依据。

## 真实 H264 严格性能复测

使用 `app/integration_test/video_performance_test.dart` 和 `tool/driver/video_performance.dart`，Windows **Profile** 模式，三轮、每轮八次输入；保留启动 1000 ms、P50 200 ms、P95 300 ms 的默认预算，没有放宽。

| 指标 | 实测 |
| --- | --- |
| 各轮 `session.start` 至首个验证可读像素 | 754 / 865 / 818 ms |
| 24 次输入请求至原生可读像素 P50 / P95 | 83 / 97 ms |
| 实际解码诊断 | 三轮均 `h264/d3d11va`、hardware frames、`runtimeSelectionVerified=true` |
| Flutter 呈现 | 每轮末读取真实纹理 RGBA，均匹配最新夹具 counter |
| 生命周期 | 三轮暂停/恢复、停止和 `nativeDeleteConfirmed=true` 均通过 |
| 清理 | 独立 fixture 卸载且确认不存在，Settings 恢复；自有 ADB server 退出，无本任务目录的 adb.exe 残留 |

启动计时从设备已连接后的 `session.start` 开始，包含该会话的服务端准备和首帧验证，不包含 Flutter 进程启动、首次 ADB 授权或测试夹具安装。每次输入计时终点是原生 snapshot 识别新 counter，包含请求、编解码、传输、轮询和像素读取开销；只在每轮末另外检查 Flutter 合成 counter。它不是每次输入的显示合成或屏幕面板延迟。

其他宿主若使用 Debug 模式，不能把本表直接作为跨平台速度排名。短期 AVD 样本也不能外推为所有网络、OEM 或长期负载的性能承诺。

## DeviceRuntime 产品组装

最终源码的 `app/integration_test/media_runtime_lifecycle_test.dart` 在 Windows Profile 模式实际初始化 `DeviceRuntime`，执行设备连接、会话启动、原生输出挂接、暂停/恢复及清理。第一轮得到实际 `h264/d3d11va` 硬件帧、576 × 1280 解码尺寸，仅包含 `Texture` 的 Flutter 读回为 1656 色，证明产品 sourceId 识别和输出组装路径已工作。

该轮明确禁止后台播放，宿主仍处于锁屏；`audio.start` 约 18 秒后超时，因此整轮判为失败，不能据此宣称音频产品组装通过。失败后的设备连接、原生输出和自有 ADB server 均已清理，未遗留本任务的 adb.exe。

随后以独立的 `CONNECT_E2E_BACKGROUND_PLAYBACK=true` 配置重编译相同入口，完整组装在 7 秒内通过：实际 `h264/d3d11va`、576 × 1280 硬件帧，纹理子树读回 1612 色；WASAPI 实际接收 12,288 字节后 `nativeReady=true`，播放时钟前进。完整 `state.snapshot` 包含同一会话纹理、已挂接音频源和 Dart transfer 集合；暂停/恢复、停止、设备断开、runtime shutdown 均通过，`session.output.ready` 恰好一次，自有 ADB server 无残留。

该轮诊断如实记录 `visible=false`、`backgroundAllowed=true`，Flutter lifecycle 为 null；它证明锁屏且允许后台播放的产品路径，不证明前台音频或扬声器可闻。最终入口包含完整 ADB API 和 renderer generation/frameCount 隔离修复；不以此前 raw-core 测试替代此次组装证据。

## PCM 与包体证据

Windows Debug PCM 生命周期在明确允许后台播放的策略下通过：WASAPI 实际接收 12,288 字节后报告 `nativeReady=true`；暂停每 200 ms 采样六次，时钟允许最后一个有界缓冲结束后保持稳定；恢复播放时钟增加，音量、静音配置及原生释放确认均通过。先前锁屏且未允许后台播放时的 18 秒 timeout 属于真实播放资格限制，不记为 WASAPI 成功，也没有伪造前台可见状态。

WASAPI 仅在 `ReleaseBuffer` 成功后累计实际提交字节，失败返回已提交部分或错误。设备接收和时钟变化不证明扬声器可闻；本轮没有声学采样。

最终普通 `main` Release 已在包含完整 ADB API、DXGI、GOP/诊断、产品组装及最后 Rust 1.99 静态检查修正的源码下重建。`tool/build_host.dart windows` 实际通过宿主/Flutter/Rust/插件架构、裁剪回执、依赖许可证和官方 ADB 检查；最后增量构建用时 32.6 秒。官方 ADB 是独立 i386 进程，exe 与两份 DLL 同架构；Flutter、Rust 和媒体插件为 x64。归档由正常应用入口生成，未以测试 Profile 可执行文件替代。

| 早期迁移产物（文末另记整改版） | 实测 |
| --- | --- |
| 路径 | `build/verified/windows-release.zip` |
| ZIP 大小 | 33,178,120 字节 |
| SHA-256 | `dc40e8c30064583761276f02ca6571041325a9b4a508d40ef80b6c47647554ae` |
| 归档校验 | 78 项，全部 CRC 通过；下载前后 SHA-256 一致 |
| 媒体插件 | `media_codec_plugin.dll`：7,540,736 字节 |
| 业务 Rust 动态库 | `interop_bridge.dll`：14,846,976 字节 |
| Flutter 引擎 | `flutter_windows.dll`：21,274,112 字节 |
| 依赖声明 | 包含 FFmpeg/dav1d 许可证、固定来源元数据、裁剪配置与构建回执，以及官方 ADB NOTICE |

早于 DXGI、最终 GOP/诊断和后续 ADB/业务组装修复的 32,915,121 字节候选包已失效并删除，不作为交付。已保留最终归档、受控对应源码与复用中的 SDK/编译缓存，清理失效候选、临时源码传输归档、mock DLL/夹具、测试身份目录及全部本任务计划任务。

原始失败与通过日志、计数回执保存在系统临时目录用于本轮诊断，长期结论由本文承载，不依赖临时文件持续存在。最终包与对应源码、许可证保留；本次临时 mock DLL、测试安装、计划任务和失效中间产物已清理。

## 源码审计整改后的复验

本轮在同一宿主新建 `C:\Users\xiankq\source\scrcpy-connect-desktop-fixes-20261023`，未覆盖前一轮源码目录。固定 FFmpeg 实际重建为 profile 3，补丁 SHA-256 为 `1437ad9aacede31e6b501f6e789564786f76ce0bdecdd86d61166b1613767bc0`。插件 MSVC `/W4 /WX` 检查及完整 Flutter/MSVC 普通 main Release 均通过；逐项整改关系见[桌面整改验收](scrcpy-audit-desktop-fixes.md)。

新增原生 WASAPI 测试实际运行生产 sink，确认 event 写入、IAudioClock 前进、pause Stop/Reset、resume、generation 和同线程关闭；静音 PCM 不作为可闻证据。`MEDIA_CODEC_BUILD_TESTS=ON` 下 Windows CTest 两项全通过：WASAPI 0.43 秒，公共 core lifecycle 0.41 秒。

真实 Flutter AV1 回放在已登录用户 Session 1 连续创建/释放三次，每次解码 24 帧，隔离纹理读回均为 **23,229 色**；后端 libdav1d、平台路径 `cpu/dxgi`。直接从 SSH Session 0 启动时，原生虽有 24 帧且无错误，纹理尚未被 raster 消费，`toImage` 报 `operation failed`；使用本次自建的 InteractiveToken 计划任务后通过。临时任务已删除，验证打印已从远端测试副本恢复。AV1 硬件拒绝后正常软件回退，不能仅凭其硬件错误日志认定整条解码失败。

首个整改候选普通 main Release 包为 33,245,631 字节，SHA-256 `35c6dfb04c0e4a5be6e5cb5aa0cdb8962bddd9948b74b4cd898d50ef4d220c55`，81 项 CRC 全通过，未包含测试 exe/replay。该候选首次新目录含依赖重建用时 512.4 秒；媒体插件 7,561,216 字节，业务 Rust 14,949,888 字节，Flutter 引擎 21,274,112 字节。后续业务最终修改仍需重新同步构建，不能把该候选认作全部最终修复的交付。

整包日志为上述远端目录的 `desktop-build.log`，原生回归为 `desktop-tests.log`，真实交互会话回放为 `desktop-replay-interactive.log`。本机证据在系统临时目录 `/tmp/media-codec-desktop-windows-evidence/`。这些验证不证明面板发光、实体热插拔、强制跨 GPU、GPU trace 或长时间漂移。

随后同步全部最终业务/Rust/生成契约及媒体核心，在 Session 1 重跑真实 `media_runtime_lifecycle_test.dart`，6 秒通过。被控为获授权 API 36 x86_64 AVD；经本次自有 SSH 反向隧道连接，不安装 counter 夹具、不注入按键或旋转。实际 `h264/d3d11va` 在 NVIDIA GTX 1650 上产生硬件帧，`hardwareVerification=hardware`；隔离 Texture 子树读回 1966 色。视频暂停/恢复、音频启动、state.snapshot、停止、断连和 runtime.shutdown 全部断言通过，`session.output.ready` 恰好一次。

音频在明确 `backgroundAllowed=true` 的锁屏资格下接收 8192 字节，`nativeReady=true` 且真实播放时钟前进；没有伪造前台状态，没有可闻或声学证明。此轮是组装正确性验证，没有重跑早期三轮严格输入延迟测试。退出后检查到该测试的独立 ADB server 仍在 `tcp:57853`，已仅关闭这个自有 server；默认 5037 未操作。临时 InteractiveToken 任务和反向隧道已删除/关闭；原始证据为 `desktop-runtime.log` 和本机 `runtime-result.json`。


同轮补充读取实际平台准备状态，确认硬件纹理路径为 `d3d11va/dxgi`、`presentationError` 为空、准备计数 2、sequence 5。此证据加上隔离 Texture 子树的真实像素，排除了该次 H264 组装偷偷走 CPU fallback；不等同于物理显示完成。

独立 ADB 残留随后纳入整改：native owner 只在关闭成功后释放，错误保留并向上传播；FlutterAdb 先请求自己 server 的 kill-server，再有界等待/进程兜底；DeviceRuntime 失败 shutdown 可以重试，并发和成功调用仍去重。再次真实 Windows 完整 A/V 组装通过（7 秒），诊断记录自有 PID 37052、port 53977 正常关闭；退出后该进程不存在，53977 拒绝连接，无手动清理。默认 5037 与其他目录的 server 未操作。原始记录为 `desktop-runtime-adb-fixed.log`。该修复没有把旧裸 FlutterAdb 也能正常关闭的事实掩盖为普遍 Process.kill 故障。

新增 `native_adb_shutdown_test.dart` 与全部 `flutter_adb/test` 在 Windows 实际运行，20 项通过、1 项需要设备授权夹具而跳过；包含失败 owner 重试、并发关闭去重、成功幂等，以及真实独立 server 的端口关闭/无关 listener 保留。记录为 `desktop-adb-tests.log`。Linux 同样 20 项通过、1 项跳过。

最后普通 Release 还同步了公共核心的分配失败修复：拒绝 latest frame 分配失败，null packet 安全关闭，worker 初始化失败标记 stopping 并唤醒 Surface/PCM barrier。真实 FFmpeg `av_max_alloc` 故障注入由公共核心 Linux 隔离子进程回归验证；Windows 此处只复验最终代码的正常构建和 native lifecycle，不宣称在 Windows 执行了 OOM 注入。


## 上轮交付（随后发现普通启动缺口）

最后同步生产诊断、完整关闭重试及公共核心分配失败修复后，普通 `main` Release 再次构建通过（12.7 秒），原生 CTest 2/2 再次通过（WASAPI 0.71 秒、core 0.42 秒）。最终归档已经替换此前候选，包含正常应用入口，不含测试 exe/replay。

| 上一轮整改产物（已被后续启动修复替代） | 实测 |
| --- | --- |
| ZIP | `build/verified/windows-release.zip` |
| 大小 | 33,244,358 字节 |
| SHA-256 | `f6d7717cf51ef54ea2521eb3412dcf4fe543f1d797af2343ff346d16fa1cf5af` |
| 校验 | 81 项 CRC 全通过，远端与下载副本 SHA 一致 |
| 媒体插件 | `media_codec_plugin.dll`：7,561,728 字节 |
| 业务 Rust | `interop_bridge.dll`：14,949,888 字节 |
| Flutter 引擎 | `flutter_windows.dll`：21,274,112 字节 |

远端可直接检查以下位置：

- 工程：`C:\Users\xiankq\source\scrcpy-connect-desktop-fixes-20261023`
- 普通 EXE：工程下 `app\build\windows\x64\runner\Release\scrcpy_connect.exe`
- ZIP：工程下 `build\verified\windows-release.zip`
- 整包、原生回归、ADB关闭回归：工程下 `desktop-build.log`、`desktop-tests.log`、`desktop-adb-tests.log`
- Flutter 像素与完整A/V组装：工程下 `desktop-replay-interactive.log`、`desktop-runtime.log`

最终检查没有本次隔离目录的 adb.exe 或本次计划任务；反向 SSH 隧道已关闭。其他目录的应用 ADB 和默认 5037 保持原状。已保留工程与受控依赖输入、日志和仍在复用的编译缓存；本次传输归档、临时身份/夹具及失效候选不作为交付。显式跨 device GPU 消费 fence、强制双 GPU、CUDA Linux 真机、实体声卡切换和长期音频漂移仍是前述平台契约或硬件验收边界。


## 普通启动 ERROR_INVALID_FUNCTION 修复

随后真实普通应用启动暴露精确错误“函数不正确。 (os error 1)”。此前 Windows `media_runtime_lifecycle_test.dart` 直接初始化 DeviceRuntime，没有执行普通入口的 outgoingMediaDirectory → media.cache.configure，因此其 A/V 成功不能替代普通 main 启动成功。上一轮归档不再作为本次启动修复的交付。

新增 `crates/interop_core/tests/runtime_startup.rs` 在真实 Windows 无 ADB/GUI 依赖地执行 Runtime 初始化、登记 canonical outgoing、重新打开持久缓存所有权和读取状态。可在 Windows MSVC 工具终端运行：

```sh
cargo test --release -p interop-core --test runtime_startup -- --nocapture
```

修改前真实 Runtime 初始化成功，紧接媒体缓存登记在 0.12 秒内返回 `CoreError { code: "io_error", message: "函数不正确。 (os error 1)" }`，退出码 101。独立最小 OS probe 进一步确认 `symlink_metadata` 查询 canonical Windows 路径的第一个 `Prefix(VerbatimDisk)` 分量 `\\?\C:` 会精确返回错误 1；追加 RootDir 后的 `\\?\C:\`、所有后续完整目录，以及文件 write/sync 均成功。因此不是私有 ADB、GUI 继承句柄或偏好文件读写失败。

`media_cache::plain_path` 现仅跳过 Prefix 单独作为元数据对象的查询；仍查询完整根目录及其后每个组件，保留相对路径拒绝、符号链接拒绝和全部真实文件系统错误。没有增加吞错误或无法启动时的替代后端。新增回归还检查 Windows 无需管理员权限的目录 junction（Unix 为 symlink）仍被拒绝。

新的 `app/integration_test/application_bootstrap_test.dart` 调用真正 `application.main()`，覆盖应用日志、材质初始化、默认 bootstrap、真实打包 ADB 和 Rust、缓存登记以及首页组件。仅替换公开目录提供器以隔离 support/temp；没有替换 initializeTransport 或缓存登记。配套 driver 为 `tool/driver/application_bootstrap.dart`，使用独立结果目录，不冒充产品或媒体验收回执：

```sh
cd app
flutter drive --profile -d windows --target=integration_test/application_bootstrap_test.dart --driver=../tool/driver/application_bootstrap.dart
```

该 Windows Session 1 回归 17 秒通过：ConnectApp 存在，StartupErrorPage 不存在，media.cache.status 可读；真实 Flutter 首页 PNG 为 1264 × 681，已目视确认是设备首页。它是 Profile 下执行普通 main 逻辑的证据；普通交付 Release.exe 的独立窗口启动结果另记于下文。原始证据为隔离工程下 `desktop-startup-before.log`、`desktop-startup-fixed.log`、`desktop-startup-path-probe.log`、`desktop-bootstrap.log`，本机临时目录 `/tmp/media-codec-desktop-windows-evidence/` 中保存对应日志、`bootstrap-main.png` 和 `bootstrap-result.json`。


最终冻结源码在 Windows MSVC Release 下两项 `runtime_startup` 回归均通过（0.20 秒）：正常 canonical 缓存登记/重新打开，以及 junction 拒绝。Linux 同两项通过，原有媒体缓存回归 5 项通过、1 项设备夹具忽略。App 测试与 driver 静态检查通过。

普通 `lib/main.dart` Release 随后实际重建 126.0 秒，宿主构建与依赖校验通过。归档解压到新的 `build\verified\windows-startup-fixed-20261023`，在已登录 Session 1 直接启动其中普通 `scrcpy_connect.exe`；生产日志出现 `bootstrap.ready`，没有旧缓存登记错误。实际窗口标题“邻接”，1280 × 720，`PrintWindow` 成功；目视确认已进入应用的添加设备界面，正常 `CloseMainWindow` 后退出码 0，独立 ADB 也退出。该截图包含临时配对二维码，窗口关闭后已删除本机和远端副本，不作为可公开的截图交付；安全 UI 图保留前述真实 main 集成测试的设备首页。窗口结果为 `desktop-normal-startup-result.json`。

独立窗口验收中，第一次截图误用了没有被构建工具更新的旧解压目录，随后纠正到本次 ZIP 的新目录；未覆盖或关闭该旧目录中用户自己运行的应用。短时间等待未观察到可见窗口，延长等待后上述普通 EXE 验证完成；不将截图超时解释成 bootstrap 失败。后一次重复运行收到控制台中断 `0xC000013A`，不计为通过，已按父进程身份只清理该次产生的独立 ADB。验收不证明冷启动时间上限。

| 启动修复后的交付 | 实测 |
| --- | --- |
| ZIP | `build/verified/windows-release.zip` |
| 大小 | 33,248,331 字节 |
| SHA-256 | `accc16ed20b906cbd38b5507604777ad21fdc2528623671983ac02f7e9d2b31e` |
| 校验 | 81 项 CRC 全通过，远端与下载副本 SHA 一致；无测试/replay 入口 |
| 媒体插件 | `media_codec_plugin.dll`：7,561,728 字节 |
| 普通 EXE | 新解压目录下 `scrcpy_connect.exe`：91,648 字节 |

远端本轮可运行副本为 `C:\Users\xiankq\source\scrcpy-connect-desktop-fixes-20261023\build\verified\windows-startup-fixed-20261023\scrcpy_connect.exe`。构建工具只更新 ZIP，不维护名为 `windows-release` 的旧解压目录，应使用该新目录或重新解压本次归档。两项临时 GUI 计划任务和本次独立 ADB 已清理，保留源码、构建日志、受控依赖输入、最终 ZIP 和可复用缓存；不操作用户其他应用或默认 ADB。
