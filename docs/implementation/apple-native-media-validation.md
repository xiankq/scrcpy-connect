# Apple 原生媒体验收记录

2026-10-23 工作区证据。逐项A1–A18归[整改表](scrcpy-audit-mobile-apple-fixes.md)，当前职责归[架构](architecture.md)，最终依赖与包摘要归[总表](scrcpy-audit-fixes.md)。

## 环境与产物边界

M1 Pro/macOS27.0.1、Xcode27.1、Flutter3.47.7、Dart3.13.5、Rust1.99.1；被控API36 x64 AVD，经隔离私有ADB连接。实际运行Mac arm64和iOS arm64模拟器，未验证实体iPhone。profile3固定依赖实际构建macOS arm64、Simulator arm64/x86_64、iphoneos arm64。

普通main的macOS Release、Simulator Debug整包、iphoneos Release无签名SDK编译通过。Mac/Simulator通过bundle内容、Rust/Flutter架构、裁剪回执与深层签名检查；Mac为本机临时签名，无Developer ID/公证。iOS不打包桌面ADB；Simulator归档不能安装实体iPhone。最终Mac为arm64，不与早期通用包直接比较体积。

## 最终运行证据

| 入口 | 已执行结果 | 限制 |
| --- | --- | --- |
| `darwin/tests/pixel_output_test.mm` | 601/709 limited、601 full软件像素、池复用、709 NV12 CoreImage/Metal；真实AudioQueue clock/reset/完全underrun迟到PCM、pause/flush/resume/close | 测试读回用于断言，播放无同步CPU读回；未覆盖HDR/广色域 |
| `media_runtime_lifecycle_test.dart` / Mac | 实际h264/videotoolbox，硬件状态确认，576×1280，Texture2080色；PCM7940字节、时钟/暂停恢复/停止/shutdown | 锁屏自动化环境，显式允许后台播放；未取得可闻输出证据 |
| 同一生产组装 / iOS模拟器 | 实际软件h264，576×1280，Texture2362色；PCM7940字节、时钟/暂停恢复/停止/shutdown | 前台运行，未声明系统后台能力；不提供实体硬解证据 |
| 生成Dart FFI | 真实Rust状态、暂停恢复/音量、销毁后防护和renderer代际回归 | 不依赖Darwin全局符号导出 |

Mac未允许后台时实际visible=false、backgroundPaused=true、0字节，符合策略；不把该资格暂停当设备故障。最后AudioQueue完全underrun时钟细化由真实Mac夹具及普通入口构建覆盖，未重复整轮Mac生产组装。实体路由/蓝牙/中断、长漂移、HDR、scanout和声学输出尚未验。

## 性能结果

以下为审计整改前的Debug严格三轮，各轮八次输入；预算首像素1000ms、P50 200ms、P95 300ms未放宽。session.start前已连接；输入终点为原生读回识别，轮末另核对Flutter Texture计数。方法见[视频测量](video-performance.md)。

| 样本 | 首像素三轮ms | 输入P50/P95 ms | 结论 |
| --- | --- | --- | --- |
| macOS，压缩部署后 | 2150/1816/1769 | 142/222 | 真实VideoToolbox帧、输入预算通过，启动三轮超预算 |
| iOS模拟器，压缩部署后 | 1410/1257/1418 | 121/141 | 实际软件解码、输入预算通过，启动三轮超预算 |

两组均Flutter计数匹配、精确释放及夹具清理通过。iOS单轮定位1412ms分为core1333ms和输出79ms；测试代理开启NODELAY的单轮对照首像素由2008降至1341ms，提示部署网络成本，但两轮仍超预算，单轮不能替代分布或作为产品优化收益。最终profile3整改后未重测P50/P95/P99，保留上述失败结论。

## 复现与交付

实际像素/音频入口为 `packages/media_codec/darwin/tests/pixel_output_test.mm`；组装为 `app/integration_test/media_runtime_lifecycle_test.dart` 与对应driver；性能为 `video_performance_test.dart` 与 `tool/driver/video_performance.dart`。构建使用 `tool/build_host.dart`，依赖与签名契约见[工具链](repository-tooling.md)。

包SHA只维护于[最终交付表](scrcpy-audit-fixes.md#最终普通入口交付)。本轮自建模拟器和隧道已删除，用户原Booted模拟器保留；源码、受控依赖、许可证和复用缓存保留。原始运行日志属于系统临时证据，不作为长期资源。
