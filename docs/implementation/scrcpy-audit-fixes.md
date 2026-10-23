# scrcpy 链路审计整改与验收

记录 2026-10-23 工作区的整改与已执行证据。上游机制见[固定源码研究](../research/scrcpy-source-audit.md)，当前责任见[架构](architecture.md)。专项结果：[桌面 D01–D24](scrcpy-audit-desktop-fixes.md)、[移动与 Apple A1–A18](scrcpy-audit-mobile-apple-fixes.md)、[传输控制 T01–T29](scrcpy-audit-transport-fixes.md)。

## 共享视频核心 C01–C18

| 项 | 结果与保留边界 |
| --- | --- |
| C01–C02 | source ABI2 移交原始 Vec、64 字节零 padding 和容量唤醒器；FFmpeg/GOP 共用存储。队列限 8 包、16MiB，异常背压限 3 秒。ABI1 兼容输入仍复制并以 2ms 重试。真实 worker 核对数据地址、单次释放和容量通知。 |
| C03 | GOP 恢复缓存限 8MiB，超限废弃到下一关键帧；软件正常路径不保留重播历史。MediaCodec 原位换 Surface 不可用时仍需重开。 |
| C04–C05 | 复用 frame/packet；send EAGAIN 先 drain 再重试，EAGAIN/ENOMEM 不误触硬件回退；异步消费者保留独立帧引用。 |
| C06–C07 | AV1 新 session 重开 decoder；END 独立于包队列容量，worker 排空后 ended。满队列 END 有真实 worker 回归，OEM AV1 恢复仍待设备验证。 |
| C08–C10 | 原子读取 frame/sequence，分开报告解码、平台准备及错误；正常启动/恢复不再强制 snapshot 读回。保留 50ms 状态采样和首帧 10ms 等待；显式截图仍可能 GPU 下载。 |
| C11–C13 | 硬件下载复制帧颜色属性，fallback 使用同一帧；slice/tile 并行保持 LOW_DELAY，H.264 单独启用 ALLOW_PROFILE_MISMATCH。 |
| C14–C16 | 到达即解码、latest-frame 覆盖；自动 RESET 独立有界任务并以 segment 隔离迟到回执。单包限 16MiB；PTS 增长检测只能发现新增积压，不能测初始或绝对延迟。 |
| C17 | 检查初始化分配；失败置 stopping 并唤醒 source、Surface、PCM barrier，空 packet 安全清理。隔离子进程 `av_max_alloc` 故障注入确认拒绝、同步返回和安全退出。 |
| C18 | 生产日志记录实际 codec/component/backend、平台准备路径及失败，按机器标识白名单过滤；未知硬件状态保留 unknown。 |

## 共享音频 S01–S11

| 项 | 结果与保留边界 |
| --- | --- |
| S01–S02 | PCM worker 串行 pause/flush/write/close；部分接受保留尾部，零写重试，持续 3 秒无进展失败。真实回归核对每次 4 字节完成 32 字节，不把丢包记为写入。 |
| S03–S04 | 四平台提供 played/queued frames 与 generation；以已播样本映射远端 PTS，20ms 目标调节器保留分包相位，重开重置。正负 1000ppm 各 30 分钟模拟通过；设备接收及其时钟没有声学证据。 |
| S05–S07 | ABI2 直接移交 PCM；有真实时钟时超过 80ms 的待写积压按整包丢旧并计数，至少留最后一包。source 容量通知及平台等待取代主要轮询；单个大包、系统缓冲和公共零写重试仍有成本。 |
| S08–S09 | Windows endpoint 失效/更换、ALSA 不可恢复错误、Apple route/interruption 有重建路径；Apple 最后共享租约退出后 deactivate。实体热插拔/路由仍需验证，桌面应用租约不是系统独占焦点。 |
| S10–S11 | 保留非 1.0 音量的标量增益、每设备共享音源及独立抓音进程。 |

## 受控依赖

FFmpeg revision `2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e`，profile 3；补丁 `0001-remote-decode-platform-contract.patch` SHA-256 为 `1437ad9aacede31e6b501f6e789564786f76ce0bdecdd86d61166b1613767bc0`。补丁提供 Android 实际 component、原位 Surface 切换、可选 low_latency 及 VT 强制硬件契约。OEM 拒绝可选 key 时先关闭它重试同一解码器。Linux 启用 libdrm，修复 VAAPI→DRM map 的 ENOSYS 回退。来源、补丁、许可证与对应源码进入缓存身份和交付回执；裁剪仍排除 avformat、网络与编码器。

## 启动与故障原因修复

- 控制 EOF、未知消息及写入确认超时原被投影为正常 stopped；现记录稳定 `failureCode/failureStage`，清理保留首因。Dart 将远端失败传到精确播放器，迟到的原生创建异常另记阶段。真实 ADB 控制夹具及 API36 x64 普通 Release 故障注入确认 `failed/control_closed/control_read` 与会话哈希贯通、输出释放、主控存活。
- Android arm64 带标签堆指针经 JNI/MethodChannel 可为负数，旧 `decoder <= 0` 错拒有效输出并触发 detach。现仅拒绝零，完整保留位值。`packages/media_codec/test/controller_test.dart` 的 tagged decoder case 通过真实 MethodChannel codec/NativeCallable 传递 `0xb4` 高字节，核对首帧状态、控制及单次释放；零指针仍拒绝。用户实体 arm64/API36 设备未接入复验，该夹具不解引用伪造地址。
- Windows canonical 路径 Prefix 被当作完整目录查询导致普通 bootstrap 错误 1；修复及真实普通入口证据见 [Windows 启动修复](windows-native-media-validation.md#普通启动-error_invalid_function-修复)。
- 私有 ADB owner 关闭成功才释放，失败可重试，runtime shutdown 失败不永久缓存；真实 Windows 完整 A/V 退出后自有进程及端口消失。

## 当前回归证据

公共核心已执行所有权/满队列 END、部分写、GOP 溢出、缩放、漂移模拟及分配失败注入；Dart 已执行真实 Rust FFI、失败回流、代际隔离、取消及截图资源回归。生成一致性、静态分析、Rust clippy 和共享产物检查通过。需要设备、网络或工具的 ignored 用例须显式执行，未计为通过。

| 主控环境 | 已验证事实 | 特有限制 |
| --- | --- | --- |
| Android16 x86_64 AVD | 普通三 ABI Release 真实开屏、关闭再开、后台返回；实际 goldfish MediaCodec Surface 与 PCM；ART callback/consumer close 回归 | goldfish 的硬件状态不能外推实体芯片；用户 arm64/API36 未复验 |
| Linux x86_64 / Intel | 普通 Release；真实 VAAPI→DMA-BUF→EGL 十二帧；DeviceRuntime Texture 像素、PCM/时钟、暂停恢复及 shutdown | 显式配置 iHD；CUDA、多 GPU、热插拔及长稳未验 |
| Windows x64 / GTX1650 | 普通 Release/CTest；真实 D3D11VA/DXGI Texture、PCM/时钟及关闭；AV1 三轮软件回退呈现 | 交互会话成像；consumer GPU fence 与跨 GPU 边界见桌面表 |
| macOS arm64 | 普通 Release；VideoToolbox 硬件状态、真实 Texture、PCM/时钟及关闭；Metal 色彩与 AudioQueue 夹具 | 后台播放显式允许；未重测最终版本延迟分布 |
| iOS arm64 模拟器 | 普通模拟器整包启动；软件 H.264 Texture、PCM/时钟及关闭；另有 iphoneos 无签名 SDK 编译 | 未进行实体 iPhone 签名安装、硬解或温控验收 |

完整组装输入为 576×1280、默认 balanced；该结果不是 640 分辨率性能样本。具体运行与复现入口见[原生](native-media-validation.md)、[Windows](windows-native-media-validation.md)、[Apple](apple-native-media-validation.md)记录。

## 最终普通入口交付

本轮 `build/verified/SHA256SUMS` 对应下表；后续清理代码未重新发布这些包。

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| `android-universal-release.apk` | 53891281 | `c0edf49463847f06dc57ba9a552d51c6dc272a27ed63e690799f4b2f6c24ab4c` |
| `windows-release.zip` | 33248331 | `accc16ed20b906cbd38b5507604777ad21fdc2528623671983ac02f7e9d2b31e` |
| `linux-release.tar.gz` | 31813500 | `5855d0c9fef5c9962e3bd31d60c1cbe882d07a1f9237c600c81ffb7ea6a23ea3` |
| `macos-release.tar.gz` | 30568023 | `258c54c19875783dfc3adb5d20bc343f3248544dd2eefc1da45d475579ec9d0f` |
| `ios-simulator-debug.tar.gz` | 90974345 | `abcdf2388374bc0d7b0dc5f8bad90a5a768bad177ec87e1c54326ddc15f582d1` |

Android 为普通三 ABI Release，签名、ZIP、16KiB 页对齐和共享摘要检查通过；相同 ABI/模式的 fvp 基准 59971009 字节，减少 10.14%。Windows x64、Linux x86_64；Mac arm64 本机临时签名，无 Developer ID/公证；iOS 为 arm64/x86_64 模拟器 Debug。Mac 不能与旧通用双架构包直接比较体积。受控依赖输入、许可证、交付与复用缓存保留；本轮自有模拟器、转发、临时身份、凭据与重复包已清理。
