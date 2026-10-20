# SurfaceTexture 源队列：Android 16 的实际异步与取帧语义

2026-10-18。依据AOSP `android-16.0.0_r1` 以及[已弃用的有界输入候选](capture-input-queue.md)核查API36调用链。固定源码说明机制，不证明实际ROM的队列状态或性能；运行结果见候选实验。

## 结论

正常的 AOSP Android 16 VirtualDisplay → SurfaceTexture 路径，不能依据
`acquireBufferLocked(item, 0)` 就判定它积压同步 FIFO 旧帧：
**VirtualDisplaySurface 在第一帧入队之前对实际 sink 调用 `setAsyncMode(true)`**。
SurfaceFlinger 随后还对虚拟显示的 native window 设置 swap interval 0，并转发到
同一 sink。异步标志使每个入队项可丢弃；后续入队替换尚未消费的最后一个项。
从空队列开始且异步模式保持不变时，队列最多有一个待获取项，获取队首即获取
获取瞬间最新的已入队帧。它不保证最新应用绘制已被 SurfaceFlinger 合成、GPU
已完成，或该帧立即编码和呈现。
来源：[VirtualDisplaySurface 构造及转发](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/DisplayHardware/VirtualDisplaySurface.cpp#50)、
[SurfaceFlinger 虚拟显示初始化](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/SurfaceFlinger.cpp#3880)、
[Surface::setSwapInterval](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/Surface.cpp#587)、
[queueBuffer](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueueProducer.cpp#1113)。

同样，Java `postEventFromNative()` 确实无去重地 `sendEmptyMessage(0)`，但不能
因此推断每次源绘制都堆积一个 Java callback：原生替换走 `onFrameReplaced`，
SurfaceTexture 的两个 JNI listener 路径都没有实现该通知，继承的默认实现为空。
异步队列因此已在原生层把未获取帧的替换通知合并；需要真实计数才能把 Java
callback 积压当成瓶颈。来源：[Java 投递](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/graphics/java/android/graphics/SurfaceTexture.java#473)、
[JNI listener](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/jni/android_graphics_SurfaceTexture.cpp#184)、
[默认 onFrameReplaced](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/include/gui/ConsumerBase.h#42)、
[新 listener proxy](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/nativedisplay/include/surfacetexture/SurfaceTexture.h#523)。

## 固定版本与本地对象

所有下列 AOSP 源码链接固定为发布标签 `android-16.0.0_r1`，不是滚动 master。
标签与 API 版本不是当前 AVD 二进制摘要证明，厂商及后续补丁差异仍须运行时核验。

候选的 `ScreenCapture.start()` 先由 `OpenGLRunner.start()` 返回新的 input Surface，
再把它传入 DisplayManager 的虚拟显示；失败时可能回退 SurfaceControl。本地
`OpenGLRunner.run()` 创建 `new SurfaceTexture(textureId)`、设置默认尺寸、创建
`new Surface(surfaceTexture)`，在 GL Handler 的 source callback 中调用一次
`updateTexImage()`，随后把 `getTimestamp()` 交给 `BoundedInputFlow.onSource()`。
信用完成与定时 drain 也在同一 GL Handler 上。此处研究的是前一段源队列；
GL 输出到编码器的 Surface 是另一条队列。
## 创建与生产连接：哪些标志实际成立

1. Java 单参数构造转到双参数构造，`singleBufferMode=false`。JNI 的两种编译分支
   都把 `!singleBufferMode=true` 传为原生 consumer 的 controlledByApp；旧分支
   显式 `BufferQueue::createBufferQueue()`，新分支由 ConsumerBase 创建 BufferQueue。
   ConsumerBase 将这个布尔值传入 `consumerConnect()`，后者存入
   `mConsumerControlledByApp`。来源：[Java 构造](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/graphics/java/android/graphics/SurfaceTexture.java#145)、
   [JNI 两分支](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/jni/android_graphics_SurfaceTexture.cpp#260)、
   [ConsumerBase 创建和连接](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/ConsumerBase.cpp#64)、
   [consumer 标志](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueueConsumer.cpp#571)。
2. Android 16 的 Java 对象经 JNI 使用的是 libnativedisplay `SurfaceTexture` /
   `EGLConsumer`，不是直接使用旧 `GLConsumer`。两者有相似注释，分析时仍应引用
   实际类。原生 SurfaceTexture 继承 ConsumerBase，`updateTexImage()` 在锁内转到
   `mEGLConsumer.updateTexImage(*this)`。来源：[JNI include 和调用](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/jni/android_graphics_SurfaceTexture.cpp#32)、
   [原生构造与 update](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/nativedisplay/surfacetexture/SurfaceTexture.cpp#38)。
3. Java `Surface(surfaceTexture)` 的 JNI wrapper 确实创建 controlledByApp=true
   的 Surface；但它不是 SurfaceFlinger 最终连接的 producer wrapper。虚拟显示的
   `NativeWindowSurface` 创建 controlledByApp=false 的 Surface，RenderSurface
   以 `NATIVE_WINDOW_API_EGL` 连接；VirtualDisplaySurface 的 `connect()` 将该标志
   原样传给 sink。不要把 Java wrapper 的标志代入 SurfaceFlinger 的连接。
   来源：[Java Surface JNI](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/jni/android_view_Surface.cpp#155)、
   [NativeWindowSurface](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/NativeWindowSurface.cpp#32)、
   [RenderSurface::initialize](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/CompositionEngine/src/RenderSurface.cpp#81)、
   [VDS connect](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/DisplayHardware/VirtualDisplaySurface.cpp#546)。
4. `BufferQueueProducer::connect()` 只有在 consumer 和 producer 均 controlledByApp
   时才开启对应的 cannot-block / queue-can-drop 标志。此路径不能凭 consumer 的
   true 推出这两个标志为 true。不过 VDS 构造明确启用的 `mAsyncMode` 独立生效，
   `connect()` 不把它重置为 false。`setAsyncMode()` 有状态/容量错误返回；VDS 构造
   没有检查返回值，因此“设备上实际成功”仍是运行时证据边界。
   来源：[connect 全函数](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueueProducer.cpp#1403)、
   [setAsyncMode 全函数](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueueProducer.cpp#265)。

SurfaceFlinger 为 `state.isVirtual()` 构造 VDS，把 `state.surface` 作为 sink，GPU
与 HWC 两类虚拟显示均经过这个构造。GPU backed 分支将 dequeue/queue 直接转发
sink；HAL HWC 分支在 `onFrameCommitted()` 把输出缓冲 queue 到同一 sink；mixed
路径另外使用 scratch BQ，它不是 scrcpy SurfaceTexture 的 BQ。
来源：[SF 创建 VDS](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/SurfaceFlinger.cpp#3995)、
[GPU queue](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/DisplayHardware/VirtualDisplaySurface.cpp#460)、
[HWC commit](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/DisplayHardware/VirtualDisplaySurface.cpp#238)。

## 获取、丢弃与“最新”的准确含义

`EGLConsumer::updateTexImage()` 的完整函数只调用一次 `st.acquireBufferLocked(&item, 0)`，
然后更新/释放旧缓冲并绑定新图像。没有循环挑选队尾；没有可用缓冲时把原生
`NO_BUFFER_AVAILABLE` 转为成功，继续保留当前图像。Java 返回 void，不能据返回
状态区分“获取了新图像”和“没有新缓冲”。来源：[EGLConsumer 完整 update](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/nativedisplay/surfacetexture/EGLConsumer.cpp#88)。

完整 `BufferQueueConsumer::acquireBuffer()` 的时间戳跳帧循环在
`expectedPresent != 0` 内；此调用传 0，跳过该循环。后续选择 `front`，取得一个项
并从队列移除。块外出现的 `front->mIsDroppable` 检查，是额外 acquire 限制下的
拒绝获取分支，**不是**把 FIFO 多个旧帧丢到最新帧的循环。
来源：[acquire 全函数，85–325 行](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueueConsumer.cpp#85)。

真正与 `expectedPresent=0` 无关的丢弃发生在 producer 的 `queueBuffer()`：

- `item.mIsDroppable` 包含 `mAsyncMode`，也包含 SurfaceFlinger/legacy drop 及共享缓冲
  的其他条件；本路径依赖显式 async，不依赖那些其他条件。
- 空队列 append；非空且最后一项可丢弃时释放其排队状态、以新项替换最后一项；
  否则 append。替换发 `onFrameReplaced`，append 发 `onFrameAvailable`。

来源：[queueBuffer 标志与替换](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueueProducer.cpp#1113)。

**由上述代码可推导**：假定新队列从首帧即成功启用 async 且不再切回同步，首项可
丢弃，后续项只替换唯一待获取项，获取清空它，所以队列深度归纳地保持 0 或 1。
这与 Java API 所说的 latest 语义一致；不是只引用 native 的条件性注释。
如果队列先同步积累不可丢弃的头部、之后才切换 async，替换最后一项并不清理
已有头部，单次 update 就可能仍取旧头部。该情况不能凭“SurfaceTexture 类型”
排除，但也不是已核对的正常 VDS 初始路径。
API 合约：[SurfaceTexture Java 文档及 update](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/graphics/java/android/graphics/SurfaceTexture.java#312)。

## Callback 合并与隔离候选假说

原生事件链为 BufferQueueProducer → ProxyConsumerListener → ConsumerBase →
FrameAvailableListener → JNI → Java Handler。ConsumerBase 的 replaced 转发与 available
不同；FrameAvailableListener 的 replaced 默认为空。旧 JNI listener 及新
SurfaceTexture FrameAvailableListenerProxy 都只实现 available。因此连续替换唯一
待获取帧不会连续发 Java callback；首次 empty→nonempty 仍有 callback，最终静止
帧可替换到那个待获取项，随后原 callback 会取得它。
来源：[BQ proxy](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueue.cpp#60)、
[ConsumerBase 两事件](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/ConsumerBase.cpp#231)、
[listener 默认值](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/include/gui/ConsumerBase.h#42)、
[JNI 两分支](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/jni/android_graphics_SurfaceTexture.cpp#184)。

**推论而非实测**：该候选仅 callback 执行 update、credit drain 只画当前 texture 的
实现，不能仅凭 Java sendEmptyMessage 推出“大量过期 callback 抢占 credit”。可以在
某次 update 已获取之后、其余 GL 工作尚未结束时再产生一个通知；这说明通知与
GL/credit 仍竞争同一线程，不能证明通知数量无界。把信号移到另一 Handler 并在 GL
侧合并可能改变调度，但不解决假想中的同步 FIFO，也会增加一次线程投递。
若考虑该候选，先记录 callback 投递/进入、update 前后、source timestamp、实际
编码 PTS、credit 投递/进入及 swap 前后，证明可改善的等待段。

## 可实际使用的 Java/API 选择

| 选择 | 已证明的能力与限制 |
| --- | --- |
| 保留当前 SurfaceTexture，每次通知在拥有 EGL context 的 GL 线程 update 一次 | 对上述正常 async VDS 是合理基线；不需要通过重复 update 才“追到最新”。Java API 要求 current EGL context。它不保证端到端时延。 |
| 在现有 GL Handler 上合并自己的更新请求 | 可限制应用自己投递的任务；须保留更新期间到达的新请求及最终静止帧。原生 replacements 已不发 Java callback，收益须实测。 |
| 更换为 ImageReader，调用 acquireLatestImage() | 公共 API 明确丢弃较老 Image，无新图像返回 null；须保留至少两个可获取 Image 的余量、及时 close。它不是 SurfaceTexture 的开关，需另做图像格式、GPU 导入、同步及吞吐实现与验收。 |
| JNI/native 自建可控制的 consumer | 能在自有 native 集成中显式控制 BQ，但本页没有证明跨版本稳定的公共 Java setter，也没有批准引入平台私有依赖。 |

来源：[Java SurfaceTexture 线程及 API](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/graphics/java/android/graphics/SurfaceTexture.java#312)、
[ImageReader acquireLatestImage 合约](https://developer.android.com/reference/android/media/ImageReader#acquireLatestImage())。

不应把 timestamp 不变当成正式的 queue-empty 检测：`getTimestamp()` 是当前图像的
源时间戳，空获取也成功，而时间戳含义取决于 producer。公共 SurfaceTexture 没有
queue-size、tryAcquire 状态或 Java async setter。固定次数连续 update、一直读到
timestamp 不变或持续忙循环，都不是已证明的“总能取最新且不伤调度”的算法。
来源：[timestamp 合约](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/graphics/java/android/graphics/SurfaceTexture.java#398)、
[空获取处理](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/nativedisplay/surfacetexture/EGLConsumer.cpp#100)。

尤其不要把 `eglSwapInterval(0)` 加在 OpenGLRunner 当前 EGL surface 上当成源队列
修复：那是 **GL → 编码器输入** 的另一条队列。Surface::setSwapInterval 会改变它
的 producer async 模式；允许它丢弃尚未消费的输入，可能令按每次提交 PTS 等待
精确完成的信用账本永久缺项。当前源 VDS 已有自己的 interval 0；两者职责不同。
这是由 Surface 行为及候选账本约束得出的风险推论，不是已运行出的故障。
来源：[Surface 设置](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/Surface.cpp#587)、
[候选的精确PTS归还设计](capture-input-queue.md#隔离候选最多两项输入)。

## 原生静态 repeat 与信用

Android 16 GraphicBufferSource 的 `kRepeatLastFrameCount=10`；设最新缓冲时重置该
计数，成功 repeat 后递减，只有仍大于零才安排下一次。它还受执行、暂停、可用
codec 输入缓冲及新源帧约束，所以静态流不是无限 heartbeat。
来源：[固定常量](https://android.googlesource.com/platform/frameworks/av/+/refs/tags/android-16.0.0_r1/media/module/bqhelper/include/media/stagefright/bqhelper/GraphicBufferSource.h#413)、
[repeat 及 setLatestBuffer 全函数](https://android.googlesource.com/platform/frameworks/av/+/refs/tags/android-16.0.0_r1/media/module/bqhelper/GraphicBufferSource.cpp#746)。

此候选的 SurfaceEncoder 移除 `KEY_REPEAT_PREVIOUS_FRAME_AFTER`，转由
LatestInputWindow 发 repeat 并分配唯一实际编码 PTS。因而原生十次上限不能直接
解释该候选静态阶段的所有输出节奏，也不能为任意未知输出 PTS 补造信用。
## 尚需运行时证明

- 实际系统/ROM 与标签的差异、实际是否走正常 DisplayManager/VDS 路径。
- 对应 SurfaceTexture BQ 的 `mAsyncMode`、队列深度及首次设置成功；AOSP
  BufferQueueCore dump 已输出 async/drop/FIFO 状态，可作为有权限时的观测对象。
  [dump 字段](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueueCore.cpp#156)。
- callback、update、GL fence/swap、编码输出、完整 write、credit 返回的实际分段。
  async 一项待取帧不等于这些阶段均短，也不等于信用释放时已处理最新源通知。
- source timestamp 必须独立于 ledger 实际编码 PTS 记录；repeat、微秒单调递增
  修正及同一图像重提交可能令两者不同。不能用一个字段混称原始源时刻和编码时刻。

因此，本页推翻“只因 acquire 传 0，所以该 VDS 队列必为旧帧 FIFO”的充分性；
它不宣称 callback 调度、GPU、编码器、write 或主控呈现中的任何一段已通过性能门槛。
