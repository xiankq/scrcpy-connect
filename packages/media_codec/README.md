# media_codec

Native packet video decoding and 48kHz stereo signed-16 PCM output for Flutter. Exports `MediaCodecController`, `MediaCodecSource` and `MediaCodecView`; capture/ADB remain source-owned. There is no file player, demuxer, HTTP reader or encoder.

```dart
final controller = MediaCodecController.video();
await controller.open(source);
final widget = MediaCodecView.controller(controller);
// Refresh/rebuild from controller.events when metadata changes.
await controller.dispose();
```

Sources carry process-local IDs, generations and attach/detach capabilities; never persist or log their addresses. Compressed packets stay native. Source ABI v2 transfers packet ownership and producer wakeups; the borrowed v1 ABI remains compatible. Control/status use generated FFI; platform code owns textures, audio devices and destruction.

System backends use MediaCodec, D3D11VA, VAAPI/CUDA or VideoToolbox with explicit software fallback, including libdav1d. Availability does not prove hardware selection or a copy-free path; reported component/verification describe actual output. Mount the texture before `waitForPresentation()` because import may require raster demand. Decoding, texture preparation, Flutter composition and scanout are distinct signals.

PCM retains partial-write tails and uses actual device clocks for bounded drift correction; pause flushes queues. Accepted bytes do not prove audible output. Snapshots are explicit bounded RGBA copies, never an implicit open/resume readback.

See [architecture](../../docs/implementation/architecture.md), [dependency/build contract](../../docs/implementation/repository-tooling.md), [native test setup](native/tests/README.md), and [platform validation](../../docs/implementation/validation.md).
