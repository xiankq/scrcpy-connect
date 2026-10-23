# Android / Apple scrcpy 源码审计实施记录

2026-10-23 工作区的 A1–A18 结果。上游机制见[固定源码研究](../research/scrcpy-source-audit.md)；公共 C/S 项和最终交付归[总表](scrcpy-audit-fixes.md)。

## 逐项对照

| 项 | 实施与特有限制 |
| --- | --- |
| A1–A2 | Apple BGRA/601 NV12 可直出，709 等 NV12 通过 CoreImage/Metal 转池化 BGRA，设置颜色属性；软件 swscale 按矩阵/range，unspecified 默认709。公共硬件下载复制同一帧属性。Mac 实测601/709 limited、601 full与709 NV12 GPU颜色；HDR/广色域/iPhone未验。 |
| A3 | SurfaceProducer cleanup 同步撤回 target；decoderLock 序列化绑定销毁，renderer 持有 ANativeWindow，dispose 先 abandon consumer 再等待退出。ART 与 ImageReader producer/consumer close 通过；没有公开 API 可取消任意阻塞 window lock，OEM 驱动卡死不能承诺固定退出时间。 |
| A4 | 查询 handlesCropAndRotation，不支持则释放 producer 并使用 SurfaceTexture transform。API36 AVD 构建/接口通过；厂商 crop/SAR/非对齐尺寸和旋转逐像素尚待验证。 |
| A5–A7 | 相同 window 跳过；NDK 动态 setOutputSurface 可用时原位切换，否则重开/GOP恢复。无 Surface 暂停输出处理，不持续切 CPU 软解。请求可选 low-latency，OEM 拒绝先关闭 key 重试同 codec。三 ABI 构建通过，实际收益/OEM接受度未测。 |
| A8 | 公开实际 component；API29+查 MediaCodecList 硬软属性，旧API只识别确定软件名、其余 unknown。VT 请求硬件会话，否则显式软件回退。Mac 真实流确认 VideoToolbox 硬件，模拟器为软件H.264。 |
| A9–A10 | Apple 复用 scaler/CVPixelBufferPool，保留最新 frame 到 copyPixelBuffer 才转换；Android 软件输出单槽覆盖旧 pending，直接写 window buffer。必要转换、已开始工作及 Flutter buffer/合成成本保留。Mac池复用与实像素通过。 |
| A11–A13 | 正常 FFI pause 经 worker 串行 AudioTrack pause/flush、AudioQueue Pause/Reset；DirectByteBuffer 借用 PCM，JVM线程持续附着。平台返回对齐的实际接受字节、played/queued及generation；Apple reset/完全underrun重定原点，保留连续逻辑帧。Mac夹具与两平台生产组装通过；Android包装对象/系统复制仍存在，蓝牙、路由、中断与长漂移未验。 |
| A14 | 原子 frame/sequence 与独立平台准备 path/error 回流；Android检查lock/convert/post与releaseOutputBuffer，Apple检查转换/导入准备。真实Flutter Texture另验，平台准备计数不提供scanout回执。 |
| A15 | Controller 保留50ms FFI状态采样，合并metadata；20Hz map/字符串和最多一轮询周期的尺寸/错误感知成本尚在，像素路径独立。 |
| A16–A17 | 公共核心针对H.264 profile、AV1新session和硬件回退；复用packet/frame、短锁、JNI与平台池。线程与恢复策略仍有吞吐/启动成本，未建立同条件负载基准。 |
| A18 | AAR consumerProguardFiles 保留JNI literal callback；每次GetMethodID立即检查异常，JNI_OnLoad注册FFmpeg JavaVM。缺callback抛IllegalStateException并清理。API36 x64 ART负例及consumer close通过，普通Release真实开屏通过；用户arm64设备另待复验。 |

## 实际构建与运行证据

- Android：profile3固定FFmpeg在 arm/x64/arm64 实际构建；三ABI JNI/Java检查及API36 x64 ART回归通过。普通三ABIRelease开屏和带标签指针修复见[总表](scrcpy-audit-fixes.md#启动与故障原因修复)。
- Apple：M1 Pro/Darwin27 arm64、Xcode27.1、Rust1.99.1、Flutter3.47.7；实际重建macOS arm64、Simulator arm64/x86_64及iphoneos arm64依赖。`darwin/tests/pixel_output_test.mm`真实运行颜色、池复用、CoreImage/Metal与AudioQueue clock/reset/underrun、pause/flush/close。
- DeviceRuntime：Mac真实 `h264/videotoolbox` 硬件、Texture2080色；iOS arm64模拟器软件H.264、Texture2362色；均576×1280、PCM7940字节，时钟/暂停恢复/停止/shutdown通过。Mac显式允许后台播放；iOS前台。
- 普通main：Mac Release、Simulator Debug整包及iphoneos Release无签名SDK编译成功。Mac本机临时签名，无Developer ID/公证；Simulator不能装实体iPhone。最后AudioQueue完全underrun细化由真实Mac夹具及最终构建覆盖，未重复整轮Mac组装。

最终依赖和包摘要只维护于[总表](scrcpy-audit-fixes.md#最终普通入口交付)。平台环境、性能样本与复现入口见[Apple验收](apple-native-media-validation.md)。实体Android arm64/iPhone、OEM trim、HDR、路由热插拔、持续vsync/物理显示、可闻输出及端到端P99未取得本轮证据。
