# SurfaceTexture 队列的异步与取帧语义

2026-10-18，核查 AOSP `android-16.0.0_r1` 的正常 VirtualDisplay→SurfaceTexture 路径。保留以下源码结论，删除已放弃的自定义捕获/信用实验方案。

## 可以确认的机制

| 事实 | 来源 |
| --- | --- |
| VirtualDisplaySurface构造时在首帧入队前对实际sink调用 `setAsyncMode(true)`；SurfaceFlinger另设置swap interval 0 | [VirtualDisplaySurface](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/DisplayHardware/VirtualDisplaySurface.cpp#50)、[SurfaceFlinger](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/SurfaceFlinger.cpp#3880) |
| `queueBuffer`在最后一项可丢弃时替换它，发 `onFrameReplaced`；否则追加并发available | [BufferQueueProducer](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueueProducer.cpp#1113) |
| 正常async从空队列起生效且不改变时，待获取项保持0或1 | 由上述入队/替换规则推导；不等于GPU或编码器无积压 |
| `updateTexImage`只acquire一次；expectedPresent=0不执行按时间戳跳帧；无新buffer仍可返回成功并保留旧图像 | [EGLConsumer](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/nativedisplay/surfacetexture/EGLConsumer.cpp#88)、[BufferQueueConsumer](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueueConsumer.cpp#85) |
| JNI listener只实现available，replaced沿默认空实现；Java无去重投递不证明每次源绘制都新增callback | [JNI listener](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/jni/android_graphics_SurfaceTexture.cpp#184)、[ConsumerBase](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/include/gui/ConsumerBase.h#42) |

因此，不能只因acquire传0就判定正常VDS必然积压同步FIFO旧帧；也不能从Java `sendEmptyMessage`推定callback数量无界。

## 仍需区分的边界

Java `Surface(surfaceTexture)` 与SurfaceFlinger的producer wrapper不是同一个连接对象，controlledByApp标志不能互相代入。上述async设置的实际返回值、ROM差异和SurfaceControl回退仍需观测。[NativeWindowSurface](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/services/surfaceflinger/NativeWindowSurface.cpp#32)、[setAsyncMode](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/BufferQueueProducer.cpp#265)

“最新”指获取瞬间最新已入队帧，不证明最新应用绘制已合成、GPU完成或立即编码。若先同步积累旧头部再切async，替换尾项不会清空那些头部。时间戳不变也不是正式queue-empty信号；公共Java API没有queue-size或async setter。[SurfaceTexture合约](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/graphics/java/android/graphics/SurfaceTexture.java#312)

源VDS队列与GL→编码器输入Surface是不同队列。在后者设置 `eglSwapInterval(0)` 会改变后者的丢弃行为，不能当作源队列修复。ImageReader的 `acquireLatestImage` 是另一种consumer，需正确保留余量并及时close，不是SurfaceTexture的配置开关。[Surface](https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-16.0.0_r1/libs/gui/Surface.cpp#587)、[ImageReader](https://developer.android.com/reference/android/media/ImageReader#acquireLatestImage())

Android16 GraphicBufferSource静态repeat上限为10，并受暂停、输入可用性与新源帧影响；不能将repeat视为无限心跳。[GraphicBufferSource](https://android.googlesource.com/platform/frameworks/av/+/refs/tags/android-16.0.0_r1/media/module/bqhelper/GraphicBufferSource.cpp#746)
