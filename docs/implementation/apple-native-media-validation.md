# Apple 原生媒体验收记录

本文前半保留源码审计前的第一阶段候选及产物结果，文末记录profile3整改后的独立复验。逐项实现和边界见[移动与 Apple 整改验收](scrcpy-audit-mobile-apple-fixes.md)，旧产物摘要与性能分布不代表最新构建。

本记录对应 `60d6c07028774f861a001d54f31765a995f3ba24` 之后的工作区候选版本，日期为 2026-10-23。只记录本轮实际构建和运行结果；架构见[当前实现职责](architecture.md)，预算和测量定义见[视频性能测量](video-performance.md)，其他宿主见[原生媒体验收](native-media-validation.md)。

## 环境与产物边界

隔离目录中的真实 Mac 为 Apple M1 Pro、macOS 27.0.1、Xcode 27.1（27A9275），Flutter 3.47.7、Dart 3.13.5、Rust 1.99.1。iOS 对象为该机器上 iOS 27.1 的 arm64 iPhone Duo 模拟器；没有验证实体 iPhone。被控端为 API 36 x86_64 Android AVD，经局域网 TCP adbd 访问。测试使用隔离 adb-server 和已有测试授权身份的副本，未替换用户身份或接管 5037。

FFmpeg 固定 revision、dav1d 和官方 platform-tools 37.0.1 与总验收记录一致。CocoaPods 自动按 SDK、架构构建裁剪依赖和 Rust 静态库；通用 macOS 包含 arm64、x86_64，iOS 模拟器构建包含 arm64、x86_64。实际运行只验证 arm64。iOS 设备目标配置不等同设备构建或设备验收。

macOS 最终资源阶段装入受锁文件校验的官方 ADB、依赖许可证与构建回执，并对嵌套可执行文件签名。iOS 不打包桌面 ADB。项目未声明许可时 Podspec 使用 Unspecified，不虚构 MIT 或专有授权。

## 解码、纹理与生命周期

| 对象 | 实际结果 | 证明范围 |
| --- | --- | --- |
| macOS 原生 H.264 夹具 | 1 包 → 1 帧，320×720；VideoToolbox 硬件帧、保留 CVPixelBuffer；缩放快照 14×32，非黑、alpha 255 | 固定单 IDR 夹具，不是吞吐或长稳基准 |
| macOS Flutter 远控 | `h264/videotoolbox`；三次暂停恢复、真实多色快照、精确释放通过 | 严格性能用例另验证实际 Flutter 合成计数与目标输入逐轮一致 |
| iOS 模拟器远控 | VideoToolbox 初始化不可用后回退 `h264` 软件；三次暂停恢复、真实像素、精确释放通过 | 不能证明实体 iOS 硬件解码 |
| macOS Dart FFI | 生成的布局直接读取真实 Rust 状态，暂停恢复、音量、销毁后调用防护通过 | 进程内地址表，不依赖 Darwin 全局符号导出 |

macOS 生命周期样本核心启动 2088ms、随后首帧 113ms，PNG 有 890 种颜色；iOS 模拟器对应为 1848ms、85ms、902 种颜色。两者均有 `nativeDeleteConfirmed=true`。这些独立运行发生在部署压缩优化之前，不代替后续性能分布。

性能运行发现诊断竞态：创建阶段的 VideoToolbox 候选名称曾先于输出被标记为运行事实，模拟器随后实际回退软件。修复后 Rust 仅在取得真实帧时写入 decoder/hardware 状态；Dart 只在真实视频帧或原生已接收音频后发布运行选择事件。配置但未送包的 Rust 测试确认 frameCount、nativeReady、硬件状态与名称均不伪造输出；Dart 测试覆盖首帧同名发布与后续回退事件。

GOP 回退缓存超过 8MiB 后立即失效，直到新的真实关键帧才重新建立；硬解回退或 Surface 重建不能重放后续 P 帧后缀。回归覆盖超限、连续 P 帧不能复活旧历史、下一关键帧恢复及配置切换失效；Mac 真实 Rust 测试通过，并重新解码 Android H.264 夹具取得有界 RGBA。

## 音频

macOS AudioQueue PCM 实际接收 12288 字节，暂停后的六次时钟采样收敛，恢复推进 1152ms，音量 0.25、静音与原生释放通过。此轮显式允许后台播放，因为自动化会话窗口处于未激活状态；默认禁止后台播放的初次 18 秒超时样本保留，不能将策略暂停误报为音频设备故障。混音租约未声称系统独占焦点，接收字节未声称扬声器可闻。

iOS 模拟器前台 PCM 生命周期同样实际通过：AudioQueue 接收 12288 字节，六次暂停采样由 6427751ms 收敛至 6427773ms，恢复推进 1450ms，音量 0.25、静音和原生精确释放通过。本轮未启用后台播放；未声明的 iOS 后台能力不因此视为支持。扬声器可闻证据仍为 false。

## 生产组装补验

完整 ADB Dart API、偏好归属和生产组装修复冻结后，使用 `media_runtime_lifecycle_test.dart` 通过真实 `DeviceRuntime` 请求连接、视频、声音和完整快照，没有绕过产品编排直接调用 raw core。两平台均验证暂停恢复、只含纹理的 Flutter GPU 读回、一次 output-ready 事件、停止和 shutdown。

| 对象与策略 | 视频与实际纹理 | 音频与组装结论 |
| --- | --- | --- |
| iOS arm64 模拟器，产品默认 backgroundKeepAlive=true，前台 resumed | `h264` 软件，576×1280，1570 色 | AudioQueue 实际接收 4096 字节、nativeReady、源 PCM、时钟推进和 playingConfirmed 均通过；完整快照含 Dart transfers，停止清理通过 |
| macOS，backgroundKeepAlive=false，锁屏 | `h264/videotoolbox` 硬件，576×1280，1718 色 | 保留初次超时失败；诊断复测 visible=false、backgroundPaused=true、nativeReady=false、bytesWritten=0，未声称前台播放通过 |
| macOS，显式 backgroundKeepAlive=true，锁屏 | `h264/videotoolbox` 硬件，576×1280，1717 色 | AudioQueue 实际接收 8192 字节；完整生产组装、PCM 和快照、暂停恢复、停止清理通过，仅证明允许后台播放的场景 |

iOS 前台样本同时记录 visible=true、backgroundAllowed=true、backgroundReady=false：未声明系统后台能力不会阻止可见时的前台声音，也没有因此声称支持后台播放。Mac 的独立 AppKit 检查得到前台应用为 `com.apple.loginwindow`；即使对本次测试应用调用激活 API 返回 true，实际 active 仍为 false。测试没有解锁用户会话或把允许后台的结果改称前台验收。音频接收字节仍不等于扬声器可闻证据。

本轮也补充 Dart 尺寸事件回归：仅在新的真实解码帧改变尺寸后发布有代际的元数据；普通帧、过期 renderer/capture/texture 和质量重建期间的旧尺寸不能更新已提交输出。新渲染器的帧计数独立于旧渲染器，旧 200 帧不能阻止新解码器第 5 帧的尺寸变化。Mac 包测试通过；这项包级证据本身不等同实际旋转验收。iOS 组装运行期间被控主机正在构建 APK，其启动时间不纳入严格性能分布。

## 性能结果

测试预先完成设备连接，不计 Flutter 进程启动；每轮重新启动投屏，三轮各八次输入。输入延迟包含读回识别开销，末尾实际 Flutter 纹理合成计数必须与目标一致。预算保持首像素 1000ms、P50 200ms、P95 300ms。模拟器和被控 AVD 不在同一设备；严格运行时避免并发构建争用被控 AVD 主机 CPU。

| 样本 | 首像素三轮（ms） | 输入 P50 / P95（ms） | 结论 |
| --- | --- | --- | --- |
| macOS，压缩部署前 | 1632 / 2000 / 1998 | 136 / 214 | 输入通过；三轮启动超预算，不能归因于仅冷启动 |
| macOS，压缩部署后及诊断修复 | 2150 / 1816 / 1769 | 142 / 222 | 输入通过；三轮启动仍超预算，真实 VideoToolbox 帧 |
| iOS 模拟器，压缩部署后 | 1410 / 1257 / 1418 | 121 / 141 | 输入通过；三轮启动超预算，实际软件解码 |

同条件 iOS 单轮定位（不替代三轮分布）得到首像素 1412ms = 核心启动 1333ms + 输出就绪 79ms，输入 126ms。核心累计里程碑为 validated 142、uploaded 775、metadata 1222、encodedKeyFrame 1277、processVerified 1329、total 1329ms；因此该轮主要耗时在连接部署而非软件解码。诊断只发布真实 `h264` / hardware=false，Flutter 合成计数、释放和清理通过，默认首像素预算仍失败。

上述各轮都通过实际 Flutter 合成计数匹配、原生精确释放、夹具卸载与 Settings 恢复。首像素字段包含 `session.start` 与输出就绪，三轮 iOS 性能报告未拆分这两段，单轮定位另行记录，不能用其替代三轮统计。初始失败原始报告不会因后续修复而删除或改为通过。

## 测试代理单轮对照

在相同 Mac 媒体实现下，分别用旧 15557 代理及同上游、仅两端启用 TCP_NODELAY 的 15558 代理做单轮分段。两轮均在无归档传输和无重型并发编译条件下取得真实 VideoToolbox 帧、Flutter 计数匹配、精确释放与夹具清理。

| 代理 | 首像素 / coreStart / outputToDecoded（ms） | 核心累计 uploaded / metadata / total（ms） |
| --- | --- | --- |
| 15557 原条件 | 2008 / 1872 / 136 | 1350 / 1760 / 1865 |
| 15558 TCP_NODELAY | 1341 / 1209 / 132 | 720 / 1142 / 1204 |

这提供测试网络转发影响部署耗时的线索，不能凭单轮认定统计显著、产品代码改善或替代三轮分布；两轮仍超 1000ms。首次额外基线在同时复制 90MB 归档时得到 3401ms，因网络争用被单独保留为受干扰样本，不纳入有效对照。原来三轮严格结果未因此改写。

## 交付与局限

冻结后普通入口 `build/verified/macos-release.tar.gz` 为 51,374,713 字节，SHA-256 `caabeeca171958cae15c1d075504c5beef0755961f36a5db3048cf6012acf3b5`；包含完整 ADB API、Dart 偏好和生产组装修复、实际解码尺寸通知、代际计数隔离、压缩部署、诊断与 GOP 修复，`build_host` 完整构建验包和 `codesign --verify --deep --strict` 实际通过。同一冻结源码的 iOS 普通入口模拟器 Debug `build/verified/ios-simulator-debug.tar.gz` 为 90,709,155 字节，SHA-256 `9dc996fdf253825584cb601f0d27a57ee80675228073c56fea28a6377b658b82`；真实构建、Apple 包内容校验和深层签名检查通过。这两份归档均在完整 ADB API 迁移、Dart 控制与偏好组装、最终尺寸通知及 Rust 机械静态检查修复冻结后重新构建；不是生命周期测试入口。macOS 使用本机临时签名，未使用 Developer ID、未公证；iOS 交付为模拟器 Debug 应用归档，不能安装实体设备。模拟器没有证明真实 iOS 硬解、设备功耗、扬声器输出、OEM、长稳、P99 或实体触控链路延迟。

原始 JSON、截图和日志保留在本轮系统临时目录 `media-codec-apple-evidence`，不作为项目规范或长期包资源。

## profile3 审计整改后的复验（2026-10-23）

本节是后续工作区结果，前面的历史性能分布、失败样本和旧包摘要保持原义。本轮通过固定来源的版本化FFmpeg补丁、VT强制硬件会话、Apple颜色转换和池化、延迟消费、音频pause/flush/close与实际水位修复，具体A1–A18见[专项实施表](scrcpy-audit-mobile-apple-fixes.md)。

在隔离工作区 `/tmp/scrcpy-audit-apple-20261023` 实际重建macOS arm64、iOS Simulator arm64/x86_64、iphoneos arm64受控依赖；Mac与iOS arm64模拟器经SSH反向转发连接API36被控AVD，使用生产DeviceRuntime组装夹具，均有 `mediaAcceptanceComplete=true`。Mac真实 `h264/videotoolbox`、hardwareVerification=hardware，Flutter Texture读回2080色；iOS实际软件 `h264`，Texture读回2362色；两者均576×1280。Mac显式允许后台播放；iOS前台。两者原生PCM接收7940字节，playingConfirmed、时钟推进、暂停恢复、停止与shutdown通过。接收字节和时钟仍不证明扬声器可闻；音频时间为源PTS锚定值，不当作测试运行时长。没有重测P50/P95/P99，因此不修改前面的历史性能结论。

最终普通 `lib/main.dart` 的macOS Release、Simulator Debug和iphoneos Release无签名SDK编译全部通过。最终Mac与Simulator通过bundle内容、arm64 Rust、Flutter、裁剪FFmpeg回执和深层签名校验；macOS使用本机临时签名，未做Developer ID/公证；Simulator归档不能装实体iPhone；iphoneos编译不等于签名安装或硬解运行。最后AudioQueue连续underrun逻辑时钟细化由真实Mac夹具再次验证，最终普通入口对象晚于源码并包含该修复。

最终Mac arm64归档30568023字节，SHA-256 `258c54c19875783dfc3adb5d20bc343f3248544dd2eefc1da45d475579ec9d0f`；Simulator Debug归档90974345字节，SHA-256 `abcdf2388374bc0d7b0dc5f8bad90a5a768bad177ec87e1c54326ddc15f582d1`。本机文件与远端App路径见专项记录。Mac架构由原通用包变为arm64，本节体积不能直接作为同条件缩减比例。真实像素/Metal/AudioQueue夹具及JSON/普通构建日志保留于 `/tmp/media-codec-platform-check/`；本次创建的临时模拟器均删除，原Booted iPhone Duo保留。实体iPhone、HDR、扬声器可闻、路由中断、长稳和端到端延迟仍未验证。
