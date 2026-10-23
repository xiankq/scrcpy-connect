# Android / Apple scrcpy 源码审计实施记录

本记录对应冻结研究 [移动与 Apple 审计](../research/scrcpy-source-audit-mobile-apple.md) 的 A1–A18，记录 2026-10-23 工作区实现与实际验收层级；研究文档中的旧代码事实不随实施回写。共有解码、控制面和普通 Release 投屏的最终结论还需与主验收记录一起阅读。这里的“已实现”不等于各厂商设备已验收。

## 逐项对照

| 项 | 实际实现与入口 | 证据、保留成本和验证边界 |
| --- | --- | --- |
| A1 Apple 颜色矩阵 | `darwin/Classes/MediaCodecPlugin.mm`：BGRA、601 NV12 保留匹配的直接输出；709 等 NV12 经 CoreImage/Metal 转池化 BGRA，设置矩阵、primaries、transfer 属性；未指定矩阵统一默认709。软件帧 swscale 按帧矩阵、range 转换。 | Mac arm64 像素夹具实际检查 601/709 limited、601 full 红色与709 NV12 GPU转换，均通过。GPU转换仍有计算与目标buffer；没有播放时同步 CPU readback。尚未覆盖 HDR、广色域显示器、真实 iPhone 和所有色彩组合。 |
| A2 硬件读回颜色属性 | 共有 Rust 硬件读回后复制 AVFrame 属性，转换跟随同一帧元数据；平台快照原子获取帧和sequence。 | 属于共有核心修改；Apple软件颜色夹具通过。不能把一个颜色块外推全部驱动下载格式与HDR。 |
| A3 Surface 销毁同步 | Android Java SurfaceProducer cleanup 在 callback 返回前同步撤回 native target；`decoderLock` 序列化绑定与销毁。JNI 窗口交换仅短暂持锁，各软件renderer自己保留 ANativeWindow 引用；dispose/engine detach 先在主线程 abandon texture consumer，再等待原生回调与renderer退出。 | 三ABI JNI编译及ART回调合同检查通过；额外 ImageReader 实时CPU producer/consumer close夹具实际通过，验证消费者abandon期间producer退出；AVD的异步buffer替换没有复现阻塞dequeue，不能称已实测取消任意阻塞。Android ANativeWindow 没有公开的任意取消 lock 接口，不能承诺驱动故障下固定超时退出；OEM trim/连续重绑尚需设备压测。 |
| A4 crop / rotation | Java 查询 `SurfaceProducer.handlesCropAndRotation()`；不支持时释放该producer并使用 SurfaceTextureEntry，交由 Flutter 的 SurfaceTexture transform 路径处理。 | Android16 API36 AVD 覆盖实际可用的Flutter接口与构建。尚需厂商非对齐编码尺寸、带crop/SAR、旋转真实画面逐像素夹具；SurfaceTexture仍有BufferQueue/GPU同步成本。 |
| A5 Surface 重绑重开 | JNI 相同 native window 跳过；受控 FFmpeg patch 暴露 `av_mediacodec_set_output_window`，NDK 可用时动态调用 `AMediaCodec_setOutputSurface` 并更新双方持有的window引用；失败才进入共有核心重开/历史恢复。 | Android三ABI受控依赖实际构建并检查公开符号。原位换surface是否被codec/OEM接受仍有设备条件；失败重开仍有解码器初始化与GOP恢复成本，不能称所有情况零重开。 |
| A6 无 Surface 后台软解 | 共有核心撤回窗口后暂停视频解码器输出处理，保留有界恢复历史，窗口恢复后重建/恢复；不再因为 null target 选择持续CPU软件解码。 | 源码与共有核心回归确认；后台电耗和所有内存压力时序未实测。维持远端capture本身仍有网络、编码和历史保留成本。 |
| A7 low-latency | 版本化 FFmpeg patch 新增 `low_latency` 选项并配置 MediaFormat `low-latency`；核心请求该模式，OEM拒绝时关闭可选key重试同一个平台解码器，再考虑软件回退。 | Android三ABI profile3构建成功。请求key不等于codec声明或实际采用低延迟；没有宣称固定毫秒收益。 |
| A8 真实硬解证据 | FFmpeg公开实际component名称；Android API29+按实际/标准名称匹配 MediaCodecList 的 `isHardwareAccelerated/isSoftwareOnly`；旧API仅识别确定的软件名，其余unknown。状态区分 backendHardwareFrames、hardwareVerification、hardwareAccelerated。VT patch 对各codec要求硬件会话，失败走显式软件回退。 | 真正硬件验证不再只靠opaque pixel format。AVD可合理报告软件component；Mac真实生产组装另取得 `h264/videotoolbox`、hardwareVerification=hardware 的真实流；颜色夹具的人工VT格式帧本身只验证转换。其他codec与设备仍需实机流。 |
| A9 Apple 软件buffer分配/交换 | 移除RGBA临时图和逐像素RGBA→BGRA交换；软件swscale直接写CVPixelBufferPool BGRA，缓存SwsContext，pool有界分配。 | Mac颜色夹具每组12轮转换与释放复用通过。必要的YUV→BGRA写入、Flutter纹理导入和池内缓冲仍存在；不能等同SDL平面YUV直接上传。 |
| A10 丢帧前转换 | Apple只保留最新AVFrame与sequence，在Flutter `copyPixelBuffer`消费时转换并缓存结果；Android软件输出交独立单槽renderer，覆盖过时pending任务，转换直接写dequeue buffer。 | Mac实像素夹具、原生构建通过。每次已开始的转换/dequeue不能撤销；跨线程AVFrame引用、调度和Flutter compositor仍有成本。硬件Surface输出不经过软件renderer。 |
| A11 真正暂停/flush | `mc_config.audio_pause`连接正常FFI控制到Android AudioTrack pause/flush和Apple AudioQueue Pause/Reset；平台音频控制锁与write串行，重置提交计数并增加clock generation。 | 代码已连接正常控制路径，不再依赖未调用的MethodChannel分支。Mac与iOS模拟器实际生产组装暂停恢复、停止和shutdown通过；终端听感、并发pause压力仍待设备验收。 |
| A12 PCM JNI | NewDirectByteBuffer借用PCM，AudioTrack非阻塞write；原生工作线程TLS仅首次attach JVM，退出时detach，不再每包byte[]复制/attach-detach。 | JNI/Java/ART合同验证通过。仍每callback分配一个DirectByteBuffer包装对象，AudioTrack内部仍复制到系统音频buffer；未虚构消除全部音频拷贝或定量时延收益。 |
| A13 音频水位与尾部 | Android反馈unsigned playback-head wrap和submitted差值；Apple反馈AudioQueue相对于本次Start的sample clock；generation区分flush/重建。Mac实际probe发现Reset后sampleTime继续从3385增加到5068，已修复旧代码把恢复后新960帧立刻算为全部played的问题；新夹具验证恢复后queued仍大于0。完全underrun后重启AudioQueue时，以累计submitted帧重定raw时钟原点，保留连续逻辑帧计数和generation，避免无PCM的空闲时间吞掉迟到PCM。平台仅返回frame对齐实际接收字节，核心保留部分write尾部并结合实际水位调节。`audio_close`终止回调释放AudioTrack/AudioQueue；iOS处理共享AVAudioSession租约、route change、中断与显式恢复。 | 设备音频输出并非“接受=已经扬声器播放”。iOS SDK/模拟器编译与真实音频路由、中断运行必须区分。长时间漂移、蓝牙、耳机拔插和播放时钟异常仍需设备回归。 |
| A14 呈现与错误 | 帧/sequence原子快照；`mc_report_present`独立记录平台准备成功数、sequence、path、error；Android检查window lock/convert/post，核心检查releaseOutputBuffer错误；Apple检查转换与导入准备。Dart分别读解码与呈现状态。 | 平台准备成功不证明Flutter随后完成纹理import、合成、vsync或物理屏幕扫描。Mac和iOS模拟器另通过真实Flutter Texture多色读回；持续显示、vsync和物理扫描仍需时间戳/录屏证据。 |
| A15 50ms控制面轮询 | 原生像素路径独立于Dart控制面；当前Controller仍用50ms FFI状态轮询，并合并变化后的metadata。 | 保留20Hz状态读取/map/字符串成本和最多一轮询周期的尺寸/错误感知差异；没有把50ms加到所有视频帧延迟。若后续改事件唤醒，以共有核心/控制面验收记录为准。 |
| A16 workaround/线程/恢复 | 核心补profile mismatch兼容与AV1新session重建等针对性恢复；Android可选low-latency失败先同硬解重试。软件线程策略和错误恢复上限由共有核心明确控制。 | 这些设置不证明所有OEM/GPU均兼容。低延迟线程数与吞吐并行度有取舍；软件回退启动和GOP恢复不是无成本操作，需具体分辨率/codec负载基准。 |
| A17 小分配/锁/线程 | 核心复用decode packet/frame；Apple复用scaler/pool并延迟消费；Android直写window、稳定JVM附着与最新slot renderer，原生texture不经过Dart逐帧像素数据。 | AVFrame clone/ref、短锁、JNI包装、调度、Flutter自身buffer与合成仍存在。没有把这些描述成固定若干毫秒或绝对零拷贝。 |
| A18 Release JNI/R8 abort | consumerProguardFiles随AAR保留所有JNI literal callback；每次GetMethodID后立刻检查异常，不携带NoSuchMethodError继续JNI。JNI_OnLoad注册FFmpeg JavaVM；缺回调转换为IllegalStateException，清理引用。 | Android16 x64 ART负例验证缺第1、第2callback不会abort，完整callback进入attach参数检查。普通Release/R8及三ABI交付由主代理单独验证；用户arm64 Android16截图本身不含tombstone，不能宣称与AVD历史根因完全相同。 |

## 实际构建与运行证据

- Android受控FFmpeg：`android-x64`、`android-arm64`、`android-arm`均实际构建；receipt记录profile3、固定来源和当前patch hash，并保留对应源码、patch与许可证。缓存身份随patch变更，不复用旧补丁产物。
- Android JNI：NDK三ABI语法/编译检查、Java编译通过。`connectedDebugAndroidTest`在Android16 x64 AVD实际执行3项callback合同，0失败/错误/跳过；日志保存在本次调试临时目录。最终新增ImageReader消费者关闭回归也通过，共4项；两类证据不能互相替代。
- Apple环境：`xiankq@100.100.1.2`，Darwin27 arm64/M1 Pro、Xcode27.1、Rust1.99.1、Flutter3.47.7；隔离工作区 `/tmp/scrcpy-audit-apple-20261023`，旧工作区只读取并APFS clone依赖缓存。profile3裁剪FFmpeg实际重建macOS arm64、iOS Simulator arm64/x86_64和iphoneos arm64；receipt固定来源及patch SHA `1437ad9aacede31e6b501f6e789564786f76ce0bdecdd86d61166b1613767bc0`。
- Apple像素/音频：最终源码的 `darwin/tests/pixel_output_test.mm` 在真实Mac编译运行exit0，检查601/709/full-range软件颜色、buffer池重复使用、709 NV12经CoreImage/Metal转换的实际像素，以及真实AudioQueue静音PCM、完全underrun后迟到PCM水位、pause/flush、恢复水位与terminal close。最终日志 `/tmp/media-codec-platform-check/apple-pixel-audio-final.log`。夹具的GPU读回只用于断言，播放路径没有同步CPU readback。
- macOS真实生产组装：`media_runtime_lifecycle_test.dart` 经DeviceRuntime连接远端API36 AVD、启动视频和声音。`mediaAcceptanceComplete=true`；实际 `h264/videotoolbox`、hardwareVerification=hardware、576×1280，Flutter Texture读回2080色；原生PCM接受7940字节/6包，playingConfirmed与实际播放时钟推进通过；暂停恢复、停止和shutdown通过。测试显式允许后台播放，不外推默认后台策略或扬声器可闻。报告 `/tmp/media-codec-platform-check/apple-macos-assembled-result.json`。此运行包含首次时钟原点修复；最后连续underrun逻辑帧细化由最终夹具和普通入口构建覆盖，未重复整轮Mac组装。
- iOS Simulator真实生产组装：隔离iPhone18Pro/iOS27 arm64模拟器，同一真实DeviceRuntime夹具通过；`mediaAcceptanceComplete=true`，实际 `h264`软件解码、576×1280，Flutter Texture读回2362色；原生PCM接受7940字节/12包，playingConfirmed与时钟推进通过，暂停恢复、停止和shutdown通过。报告 `/tmp/media-codec-platform-check/apple-ios-assembled-result.json`。不是实体iPhone硬解或扬声器输出证据。本轮创建的两台模拟器均已关闭删除，用户原有Booted iPhone Duo保持不变。
- 最终普通入口：明确 `-t lib/main.dart` 的macOS Release、iOS Simulator Debug双架构和iphoneos Release `--no-codesign`均编译成功。macOS与Simulator通过Apple bundle内容、arm64 Rust/Flutter/media回执校验及 `codesign --verify --deep --strict`；Mac使用临时本机签名，无Developer ID/公证；iPhoneOS仅无签名SDK编译，未安装实体设备。构建日志分别为 `/tmp/media-codec-platform-check/apple-{macos-release,ios-sim,ios-device}-delivery.log`。

## 最终记录

最终交付包含最后AudioQueue完全underrun时钟细化、共享Rust OOM失败路径、诊断和可重试shutdown修复。Mac插件源码两端SHA一致为 `bf9fa2b9bad5695f58dbae9ed4bcc2d8efe96999385c8a44062f7db9ead2afb2`；远端源码mtime 12:11:51，普通Release对象12:13:38，确认最终重新编译。共享Rust源码两端SHA为 `324175d95c2a08e3b42d823f63df336de8e6aafe59e1c51bb65688c1bf481e65`。

| 本机最终交付（仓库根目录下） | 字节 | SHA-256 |
| --- | ---: | --- |
| `build/verified/macos-release.tar.gz` | 30568023 | `258c54c19875783dfc3adb5d20bc343f3248544dd2eefc1da45d475579ec9d0f` |
| `build/verified/ios-simulator-debug.tar.gz` | 90974345 | `abcdf2388374bc0d7b0dc5f8bad90a5a768bad177ec87e1c54326ddc15f582d1` |

远端归档分别在隔离工作区 `build/verified/macos-release.tar.gz` 与 `/tmp/scrcpy-audit-ios-simulator-debug.tar.gz`；普通App保留于隔离工作区 `app/build/macos/Build/Products/Release/`、`app/build/ios/iphonesimulator/` 和 `app/build/ios/iphoneos/`。本次Mac是arm64包，不能将其大小与此前通用双架构包比较后声称同条件优化。详细日志、源码/object时间回执与组装result.json留在本次临时证据目录，不作为长期包资源。

物理Android arm64主控、实体iPhone、OEM crop/rotation/后台trim、蓝牙/路由/中断、长时间音频漂移、HDR、持续vsync/物理显示、扬声器可闻与端到端P99未在本专项取得证据。20Hz控制面成本及A1–A18表内剩余成本仍保留；完成代码修复不表示与原版scrcpy所有性能链路完全等价。
