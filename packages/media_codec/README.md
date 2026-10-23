# media_codec

Remote video decoding and PCM output for Flutter. This package owns one native
decoder/output per controller; the source continues to own capture and ADB.
It exports `MediaCodecController`, `MediaCodecSource` and `MediaCodecView`.
There is no file player, container demuxer, HTTP reader or encoder.

The caller supplies a process-local source capability (source ID, generation,
attach/detach function addresses). Compressed video packets stay native, pass
through the bounded source ABI and enter the Rust FFmpeg core directly. Control
and status use generated Dart FFI; Flutter platform code owns textures, audio
devices, snapshots and destruction. Never persist or log capability addresses.

```dart
final controller = MediaCodecController.video();
await controller.open(source);
// Refresh/rebuild from controller.events when texture metadata changes.
final widget = MediaCodecView.controller(controller);
// Closing the route does not implicitly stop the remote capture.
await controller.dispose();
```

Android uses MediaCodec/SurfaceProducer, Windows D3D11VA/DXGI shared handles,
Linux VAAPI DMA-BUF/EGL or software pixels, and Apple VideoToolbox/pixel buffers.
Windows imports the shared handle into Flutter's own D3D device. If decoding
and rendering use different GPU adapters, presentation uses CPU readback and
uploads on Flutter's adapter; it cannot share a legacy DXGI handle across GPUs.
Linux NVDEC can copy device planes into GL textures through CUDA/GL interop;
unsupported device/import combinations retain explicit CPU fallback. VAAPI
imports DMA-BUF planes and retains source frames until GPU fences complete.
Flutter still requires an RGB texture on desktop, including a conversion pass.
Backend availability alone does not establish a copy-free presentation path.
The selected component and hardware verification are reported after output
exists. Android API 29+ classifies the actual component through system codec
properties; older unknown components are not reported as verified hardware.
Software fallback remains available, including static libdav1d for AV1.

The v2 source ABI transfers exclusive packet ownership with decoder padding and
notifies blocked producers when capacity returns. The legacy borrowed ABI remains
available. Decoding and preparing a platform texture are separate status signals;
neither proves Flutter composition or display scanout. Mount the texture before
awaiting `waitForPresentation()`, since some platforms import on raster demand.

Audio accepts 48kHz stereo signed 16-bit PCM. Partial writes retain their tail;
actual device playback/queue clocks drive bounded drift correction. Pause flushes
device queues on the PCM worker. Accepted bytes, device playback and audible
speaker output are distinct evidence. Snapshots are explicit bounded RGBA copies;
opening or resuming video does not force a readback.

Pinned dependency inputs and SHA-256 values are in `third_party/`. The builder
uses Python, Meson/Ninja, an appropriate C toolchain and Rust, plus NASM for x64.
Android additionally needs the NDK; Windows needs MSVC and the Windows SDK;
Apple needs Xcode and CocoaPods. The independent `rust/` Cargo workspace uses
bindgen against the exact built FFmpeg headers. CMake/CocoaPods drive these
builds and cache them under the repository `.dart_tool/media_codec/` directory.
Build receipts and third-party notices accompany the final application.

Validation records distinguish SDK compilation, actual decoding, Flutter
presentation and physical hardware. Host drivers remain system dependencies.
