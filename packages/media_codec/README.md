# media_codec

Native packet video decoding and 48kHz stereo signed-16 PCM output for Flutter. Exports `MediaCodecController`, `MediaCodecSource` and `MediaCodecView`; capture/ADB remain source-owned. There is no file player, demuxer, HTTP reader or encoder.

```dart
final controller = MediaCodecController.video();
await controller.open(source);
final widget = MediaCodecView.controller(controller);
// 元数据变化时根据 controller.events 刷新界面。
await controller.dispose();
```

Sources carry process-local IDs, generations and attach/detach capabilities; never persist or log their addresses. Compressed packets stay native. Source ABI v2 transfers packet ownership and producer wakeups; the borrowed v1 ABI remains compatible. Control/status use generated FFI; platform code owns textures, audio devices and destruction.

`dispose()` 同步停止控制准入并等待已受理操作；平台销毁失败或明确未确认时，控制器保留原输出句柄，调用方须持有同一控制器重试。创建后的地址校验失败也沿用这份清理责任；销毁确认前不能把失败当成资源已退出。

本机解码与像素转换的单边尺寸上限为 16384。解码器创建和两版来源 ABI 均核验该资源上限；所有权 ABI 拒绝输入时不接管负载。此限制属于本包，不作为 scrcpy 协议或设备显示能力的上限。

System backends use MediaCodec, D3D11VA, VAAPI/CUDA or VideoToolbox with explicit software fallback, including libdav1d. Availability does not prove hardware selection or a copy-free path; reported component/verification describe actual output. Mount the texture before `waitForPresentation()` because import may require raster demand. Decoding, texture preparation, Flutter composition and scanout are distinct signals.

PCM retains partial-write tails and uses actual device clocks for bounded drift correction; pause flushes queues. Accepted bytes do not prove audible output. Snapshots are explicit bounded RGBA copies, never an implicit open/resume readback.

See [architecture](../../docs/implementation/architecture.md), [dependency/build contract](../../docs/implementation/repository-tooling.md), [native test setup](native/tests/README.md), and [platform validation](../../docs/implementation/validation.md).
