# scrcpy 链路审计整改与验收

本记录对应 2026-10-23 未提交工作区，对照[固定源码总审计](../research/scrcpy-source-audit.md)。研究报告保留当时发现；当前架构由 [architecture.md](architecture.md) 维护。下列“实施”不自动代表所有实体设备完成验收。

专项逐项记录：[桌面 D01–D24](scrcpy-audit-desktop-fixes.md)、[移动与 Apple A1–A18](scrcpy-audit-mobile-apple-fixes.md)、[传输控制 T01–T29](scrcpy-audit-transport-fixes.md)。

## 共享视频核心 C01–C18

| 项 | 本轮实施与边界 |
| --- | --- |
| C01 | source ABI v2 移交原始 Vec 所有权，附加 64 字节零 padding；FFmpeg AVBuffer 与 GOP 引用同一存储。PCM 正常移交同样不再入口复制。ABI v1 兼容夹具仍复制，只清 padding；ADB payload 重组和平台纹理成本另计。真实 worker 测试核对输入与 PCM callback 的数据地址相同、所有者恰释放一次。 |
| C02 | v2 注册带所有权的容量唤醒器；出队、暂停丢弃 PCM 队列及结束都会唤醒等待者。生产者等待 Notify 与取消，保留 3 秒异常背压界限；旧 v1 保留 2ms 兼容重试。容量为 8 包、总共 16MiB，不宣称稳定运行时会填满。 |
| C03 | GOP 单独限制 8MiB；软件路径不保存持续重播历史。MediaCodec 支持时原位切换 Surface，避免常规重开；不支持时仍有有界恢复成本。超过预算后废弃不完整 GOP，等待新关键帧。 |
| C04 | 解码 AVFrame、AVPacket 和 latest AVFrame 复用，发布使用 unref/ref。平台异步使用帧仍需独立引用，其寿命不能以消除小对象为由缩短。 |
| C05 | send EAGAIN 后 drain 再重试；不把 EAGAIN/ENOMEM 当硬件失效，也不对已软解路径触发所谓硬件回退。实际硬件错误仍可关闭、软解重开并有界重播。 |
| C06 | AV1 相同配置的新 session 也重开 decoder；其余相同配置保留复用。实际 AV1 OEM session 恢复仍需设备验证。 |
| C07 | END 使用独立结束标记，不能被包队列满拒绝；worker 排空后标记 ended。真实 worker 测试填满 8 包队列再送 END，核对所有 PCM 及 ended。 |
| C08 | 新增帧与 sequence 原子快照、平台准备计数/路径/失败回流。解码、平台准备与 Flutter 合成/显示分开取证；公开 Flutter API 不提供所有平台的最终显示确认。 |
| C09 | 保留 50ms 状态 FFI 采样与首帧 10ms 等待；它们影响状态/布局反应及小对象开销，不进入原生每帧像素路径。未将这一保留成本声称消除。 |
| C10 | 正常启动和恢复移除强制 32×32 snapshot；播放器确认解码后返回纹理供 Flutter 挂载。平台按需导入后的证据独立上报。显式截图仍可能整帧 GPU 下载。 |
| C11 | hwframe transfer 后复制 AVFrame properties，保留颜色矩阵/范围；平台 fallback 转换同一已取得帧，避免混用另一个 sequence。 |
| C12 | slice 并行采用 FFmpeg CPU 选择，不启用增加排帧延迟的 frame threading；dav1d 保留其低延迟行/瓦片并行。不以此未经性能测量宣称更快。 |
| C13 | H.264 对齐 ALLOW_PROFILE_MISMATCH；不扩展为所有 codec 无条件忽略 profile。 |
| C14 | 到达 PTS 相对增长仍是兜底，不能测绝对端到端延迟、首次已有积压或 compositor 成本。自动 RESET 改为独立有界控制任务，视频继续收包，SESSION 与 write receipt 通过 segment 防乱序。算法测量边界保留。 |
| C15 | 保留到达即解码与 latest-frame 覆盖，不增加可选视频抖动缓冲。符合当前低延迟目标，与 scrcpy 默认 video_buffer=0 的比较边界一致。 |
| C16 | source 与 decoder 单包上限统一 16MiB；GOP 恢复预算独立，不因允许大包而无限保留历史。 |
| C17 | 创建时校验 latest AVFrame 分配；worker 初始化分配失败时置 stopping 并唤醒 source、Surface 和 PCM barrier，清理不再 unref 空 packet。FFmpeg `av_max_alloc` 独立子进程故障注入核对创建拒绝、清理不崩溃及两个同步控制均能返回；不是实体低内存 soak。 |
| C18 | 生产日志识别实际 codec/backend/component，保留平台确认的软硬解状态；未知 Android 组件仍记未知。纹理首次准备、路径/代际变化有界去重，保留平台准备与界面显示的证据区别。组件名和路径仍按机器标识白名单过滤，不放开原始 native 日志。普通 Android Release 日志已读回实际组件及 Surface 路径。 |

## 共享音频 S01–S11

| 项 | 本轮实施与边界 |
| --- | --- |
| S01 | 正常 FFI pause 交给 PCM worker 同步执行平台 pause/flush，确认完成再返回；暂停打断部分写入重试。退出回调 audio_close 在同 worker 释放输出资源。 |
| S02 | 部分接受保留尾部，0 接受等待后重试；不合法返回或持续 3 秒无进展明确失败。真实部分写测试核对 32 字节按每次 4 字节完整送达。过量积压的整包舍弃另有计数，不能伪称写入成功。 |
| S03 | 四平台提供真实 played/queued frames 与设备 generation。公共调节器以 20ms 目标水位作平滑、限幅漂移补偿，流式立体声插值保留分包相位；暂停/重开重置调节器。正负 1000ppm、各 30 分钟的模拟通过，不是实体设备 30 分钟 soak。 |
| S04 | 位置来自设备已播样本映射远端 PTS，重建 generation 保持累计时钟；提交字节与排队样本分别报告，均不证明扬声器可闻。 |
| S05 | v2 移交 PCM 原始存储；Android DirectByteBuffer 替代 byte[]，JNI 线程持续附着至退出。实际需要调节采样率/音量时仍有计算和输出存储。 |
| S06 | 有真实设备时钟时，待写积压超过 80ms 按整包舍弃旧包并累计 dropped frames，至少保留最后一包；单个大包仍可能超过该水位，80ms 不是端到端硬上限。平台缓冲容量、调节目标与真实延迟不能混为一值。 |
| S07 | v2 容量通知代替 source 定时重试；WASAPI 事件等待、AudioTrack 非阻塞写、ALSA 有界 wait、AudioQueue 回调与部分接受。公共 0 写重试仍有短等待。 |
| S08 | Windows 默认端点变化/失效恢复、ALSA 无法恢复时重开、Apple route/interruption 链路已实施；真实热插拔和所有设备路由仍需分别验证。 |
| S09 | Apple 音频会话共享租约在最后输出退出后 deactivate；桌面应用焦点租约不冒充系统焦点，Android 保留原系统焦点策略。 |
| S10 | 保留非 1.0 音量的公共标量增益计算；未为这项未经测量的轻量开销增加平台依赖或声称 SIMD 优化。 |
| S11 | 保留每设备共享音源及独立抓音进程，避免按窗口合并导致重复抓音。额外部署和进程成本仍存在，见传输专项。 |

## 受控依赖

FFmpeg 保持 revision `2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e`，构建 profile 3。受控补丁 `0001-remote-decode-platform-contract.patch` 的 SHA-256 为 `1437ad9aacede31e6b501f6e789564786f76ce0bdecdd86d61166b1613767bc0`，提供 Android 实际 component、NDK 原位 Surface 切换、low_latency 请求及 VT 强制硬件契约。Android OEM 拒绝可选 low_latency key 时先关闭该 key 重试同一解码器，再考虑软解。

Linux 增加 libdrm 构建与链接；此前 CONFIG_LIBDRM=0 会令 VAAPI→DRM 映射失败、退 CPU。原始源码/归档不覆盖，patch identity 进入缓存、回执与对应源码/许可证交付。无需增加 avformat、网络、容器或编码器。

## 交付后故障复核（2026-10-23）

用户的 Android16 arm64 主控在打开画面时失败；Android15 被控也出现同类问题。用户另确认错误页小字仅为“此视频操作已结束，不会恢复旧画面”。两张日志只证明控制会话停止及播放器取消：一例先出现声音 `unsupported`，另一例在会话断开之后才出现 `audio.start/session_required`。不能据此把视频失败归因于声音，或断言被控版本过低。此实体组合尚未完成复验。

已用实际 ADB 控制流夹具复现另一项确定缺陷：控制 EOF、未知消息与写入无确认超时被投影成正常 `stopped`，原始原因丢失。相同命令 `cargo test -p interop-core control_failure_cause -- --nocapture` 修前 3 项失败，修后 10 项通过；scrcpy 模块 62 通过、2 项设备环境明确忽略，严格 Clippy 通过。各异常在取消前记录稳定 `failureCode/failureStage`；后续停止、清理和应用启动结果未知的收尾保留首因，正常取消及画质替换保持独立。

Dart 回归复现了远端失败在等待本机输出时被覆盖成 `cancelled`；现将会话失败传入精确播放器输出并保留到启动 Future。原生创建可能先 detach、再经 MethodChannel 返回异常；其迟到 `media_codec_create` 单独保留阶段诊断，避免只留下取消。FFI 状态测试还验证了解码、平台呈现、源结束与轮询失败的固定分类及数字原生错误。生产日志新增会话哈希关联及白名单阶段，不输出原始异常消息、地址、Java 日志或媒体内容。此次修复解决原因丢失，不能代替实体设备开屏恢复的证据。 最终普通三 ABI APK 已在 API36 x86_64 AVD 打开真实被控 Settings（进程 3703）；随后只终止本次拥有的 scrcpy 服务，生产日志实际记录 `failed/control_closed/control_read` 及与播放器一致的会话哈希，输出释放回执成功，主控进程保持 3703 且 crash buffer 为空。该故障注入证明新包的原因保留链路，不等同于复现用户 OEM 真机根因。Dart 能力包与初始化回归 113 项、主应用 428 项通过；真实媒体 FFI Controller 12 项通过，静态分析无问题。

### Android arm64 带标签指针导致开屏取消

后续修复定位到独立于原因保留链路的实际启动缺陷：Android 64 位堆指针的最高字节可携带 tag，经过 JNI `Long`、MethodChannel 和 Dart 有符号 `int` 后可表示为负数。旧 `NativeControls` 用 `decoder <= 0` 拒绝非空 decoder；这发生在原生输出创建成功、source 已 attach 之后。Controller 的失败收尾随即 dispose 平台输出，Rust destroy/detach 再取消共享会话，能够形成“控制会话 stopped → 视频 cancelled”的结果。该缺陷位于主控进程，与被控 Android15 或16 无关；x86_64 AVD 的通常正地址不会暴露此检查错误。

修复仅将 decoder 检查改为非零，并完整保留指针位值，不做去 tag、取绝对值或关闭系统指针标记。函数入口地址与正数 Session ID 具有不同含义，其校验不变。Android 官方说明及固定 Bionic 实现分别见[堆指针标记](https://source.android.com/docs/security/test/tagged-pointers)和[`malloc_tagged_pointers.h`](https://android.googlesource.com/platform/bionic/+/8880cab65/libc/bionic/malloc_tagged_pointers.h)；原有 tag 必须保留以供平台释放。

`packages/media_codec/test/controller_test.dart` 的 `Android arm64 tagged decoder reaches the first frame without detaching` 经真实 MethodChannel codec 和 NativeCallable FFI 传递最高字节为 `0xb4` 的负位型。修前命令 `flutter test --no-pub test/controller_test.dart --plain-name "Android arm64 tagged decoder"` 在真实 `NativeControls` 抛出 `Native decoder controls are unavailable`；修后同一回归成功，模拟首帧状态可读，暂停、恢复和音量均逐次核对指针位值未变，启动时不 dispose，最终双重 dispose 仅释放一次。另保留零指针拒绝及清理测试。这里的首帧来自原生回调夹具，并未在 x86_64 解引用伪造的 ARM 地址，不能等同于真机解码成功。

本次 Controller 14/14 通过，包含加载实际 Linux Rust 媒体动态库的生成 FFI 集成，未跳过该项；scrcpy_client 100/100 通过；媒体包 `dart analyze lib test` 无问题。回归原始日志位于系统临时目录的 `android-tagged-pointer-{red,green,suite,client-suite,analysis}.log`。这确认了上述代码缺陷的修复；用户实体 arm64/API36 设备未接入，实际 JNI 带标签分配、硬解、画面呈现与关闭仍需该设备复验，不能把其截图当作已提取到完整根因堆栈。

Windows 用户普通启动出现“函数不正确（os error 1）”。真实初始化后调用 `media.cache.configure` 已精确复现：Windows canonical 路径的 `Prefix(VerbatimDisk)`（如 `\\?\C:`）并非完整路径，逐组件元数据查询在此失败。现仅跳过前缀自身的查询，继续校验根目录及全部目录组件，不吞真实文件系统错误。Windows 注册、重开及 junction 拒绝 2 项回归通过；真正 `application.main()` 集成启动进入设备首页；最终普通 ZIP 独立解压后运行 EXE，实际窗口可见，生产日志记录 `bootstrap.ready`，正常关闭退出码 0，并确认该进程拥有的私有 ADB 已退出。此前完整媒体组装从 `DeviceRuntime.initialize` 开始，没有覆盖默认 bootstrap 后续缓存登记，因此不能用旧 A/V 验证推断普通启动无误。配套默认入口回归隔离测试目录并保留真实 ADB/Core。

## 当前回归证据

- 公共媒体 Rust 核心 8/8 通过，显式启用实际 Android H.264 录制夹具，没有把 ignored 算作通过；包含部分写、所有权/满队列 END、GOP 溢出、缩放读回、漂移模拟及分配失败注入。媒体核心与根 Rust workspace clippy 均通过。
- 媒体 Dart 与 scrcpy_client 108 通过，包含实际 Rust 动态库的生成 FFI、解码/平台准备证据分离、平台失败回流、取消与截图资源所有权。主应用完整 428 项、生产日志 9 项（日志页面 4 项包含于主应用）、工具 70 项通过；生成一致性、静态分析、共享服务器产物检查通过。
- ADB 关闭保留失败 owner，允许重试并合并并发；DeviceRuntime.shutdown 同样只在失败时清除缓存 Future。Windows 完整 A/V 回归后确认本次私有进程和端口自动消失，未手动杀掉该轮 server；另有两平台 20 项关闭/ADB 回归通过及 1 项授权设备夹具显式跳过。

| 主控环境 | 本轮实际证据 | 验证边界 |
| --- | --- | --- |
| Android16 x86_64 AVD | 最终普通三 ABI Release 安装；打开真实被控 Settings、关闭再开、后台返回，同一 PID 8463，crash buffer 为空；ART JNI/consumer abandonment 4/4。生产日志记录 `h264_mediacodec`、`c2.goldfish.h264.decoder`、`android-mediacodec-surface` 和 PCM | AVD 平台把 goldfish 组件报告为硬件路径，不证明实体 Android 芯片；用户 arm64/API36 真机尚未复验 |
| Linux x86_64 / Intel | 最终普通 Release 与依赖裁剪核验；实际 VAAPI→DMA-BUF→EGL 十二帧；完整 DeviceRuntime 组装 H.264/VAAPI、仅 Texture 子树 1455 色、PCM 8196 字节、播放时钟/暂停恢复/停止/shutdown | 测试显式配置隔离 sysroot 的 iHD 驱动；CUDA、双 GPU、热插拔、长期 soak 未代验 |
| Windows x64 / GTX 1650 | SSH 上普通 Release/CTest 2/2；完整组装 H.264/D3D11VA、`d3d11va/dxgi`、仅 Texture 子树 1966 色、PCM 时钟和关闭；AV1 三轮软件回退纹理均通过 | 使用交互会话完成成像；跨 GPU、显式 consumer fence、真实路由切换仍有各自边界 |
| macOS arm64 | SSH 上普通 Release；真实组装 `h264/videotoolbox`，硬件帧与平台验证均 true，Texture 2080 色，PCM 7940 字节，时钟/暂停恢复/关闭；真实 CoreImage Metal 颜色及 AudioQueue clock/reset/underrun 夹具 | 非同条件延迟基准；不据此承诺所有 Mac 芯片或显示合成无额外成本 |
| iOS arm64 模拟器 | SSH 上普通模拟器 SDK 整包、安装启动；真实组装软件 H.264，Texture 2362 色，PCM 7940 字节，时钟/暂停/关闭；另有 iphoneos Release 无签名 SDK 编译 | 模拟器软件解码正常；未签名 Runner.app 不能代替 iPhone 签名安装、硬解和温控验收 |

完整组装回归为 576×1280 输入，其返回 quality 为默认 balanced；测试额外参数不覆盖该结果，不能把这些样本标注为 640 分辨率性能测试。各平台明细、原始失败与修复结果见上方专项记录。

主控实体 Android arm64/API36、iPhone、Linux NVIDIA/CUDA 与多 GPU 的验证层级必须独立记录。任何平台编译、模拟器或局部 GPU 夹具都不能替代它们。

## 最终普通入口交付

根目录 `build/verified/SHA256SUMS` 对应以下本轮文件；审计前验收文档中的旧摘要不代表这些产物。

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| `android-universal-release.apk` | 53891281 | `c0edf49463847f06dc57ba9a552d51c6dc272a27ed63e690799f4b2f6c24ab4c` |
| `windows-release.zip` | 33248331 | `accc16ed20b906cbd38b5507604777ad21fdc2528623671983ac02f7e9d2b31e` |
| `linux-release.tar.gz` | 31813500 | `5855d0c9fef5c9962e3bd31d60c1cbe882d07a1f9237c600c81ffb7ea6a23ea3` |
| `macos-release.tar.gz` | 30568023 | `258c54c19875783dfc3adb5d20bc343f3248544dd2eefc1da45d475579ec9d0f` |
| `ios-simulator-debug.tar.gz` | 90974345 | `abcdf2388374bc0d7b0dc5f8bad90a5a768bad177ec87e1c54326ddc15f582d1` |

Android 为包含上述 arm64 指针校验修复的三 ABI 普通 Release（`lib/main.dart`），通过签名、ZIP 完整性、16KiB 页对齐和共享服务器摘要检查。相对同为三 ABI 普通 Release 的旧 fvp 基准 59971009 字节，减少 6079728 字节（10.14%）；未用单 ABI 或 Debug 包制造降幅。Windows 为 x64；Linux 为 x86_64。Mac 本轮为 arm64 本机临时签名 Release，无 Developer ID/公证，不能与旧通用双架构包直接比较体积。iOS 归档为 arm64/x86_64 模拟器 Debug，不能用于实体 iPhone；无签名 iphoneos Release 的 SDK 编译产物另保留在 Mac 工作目录。

SSH 实际构建工作区分别为 Windows `C:\Users\xiankq\source\scrcpy-connect-desktop-fixes-20261023`、Mac `/private/tmp/scrcpy-audit-apple-20261023`。两处保留最终源码、构建与回归日志、普通 App；Windows ZIP、Mac tar 位于各自 `build/verified/`，模拟器 tar 另在 Mac `/private/tmp/scrcpy-audit-ios-simulator-debug.tar.gz`。临时路径只作为本次验收线索，产品和架构不依赖其长期存在。

收尾已关闭本次两个 AVD，删除本轮两台 iOS 模拟器、转发、独立测试身份、临时 mksh 解包和重复下载归档，移除主控 AVD 的测试设备记录，恢复目标 USB adbd。临时 SSH 凭据文件已删除。保留用户既有 AVD 定义、默认 ADB server、原 Booted Apple 模拟器、受控依赖源码/许可证、复用缓存和上述最终包；交付后故障复核收尾时本机约 32GiB 可用。关键运行日志和截图保留于系统临时证据目录。
