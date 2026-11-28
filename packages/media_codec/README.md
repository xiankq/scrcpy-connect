# media_codec

Flutter 原生视频解码和音频输出包：把压缩视频包解码成画面，把音频输出为 48 kHz、双声道、signed 16-bit PCM。

不负责：ADB、屏幕捕获、播放本地文件、编码。

```dart
final controller = MediaCodecController.video();
await controller.open(source);
final widget = MediaCodecView.controller(controller);
// 监听 controller.events 更新分辨率等元数据；用完后：
await controller.dispose();
```

## 生命周期

- 来源 ID、代次和地址只在当前进程内有效。不要持久化，也不要写进日志。
- 压缩视频包只在原生层流动，不经过 Dart。
- "来源附着"和"播放器输出"各自有独立的生命周期，分别创建和释放。
- `dispose()` 会等待已经接受的操作完成。销毁失败时保留同一个 controller 再次调用 `dispose()`。
- 控制 ID 在销毁时作废，不能跨动态库使用。

## 实现结构

- 状态查询、暂停和音量通过 FRB 调用 Rust 解码器；平台插件负责创建、销毁、纹理和系统音频输出。
- 平台代码和媒体生产者（如 scrcpy 包）之间使用内部 C ABI。Dart 侧不另外维护一套媒体 FFI 绑定。
- Apple 平台以动态 CocoaPods framework 方式集成（Podfile 使用 `use_frameworks!`）。

## 确认画面真的显示了

1. 先把 texture 挂到界面上，再调用 `waitForPresentation()` 等待。
2. 解码完成、纹理准备好、Flutter 合成、屏幕显示、声音实际播放，是五个不同的阶段，分别验证，不能用前一个推断后一个。
3. 需要知道用的是哪个解码后端时，从控制器读取实际值，不按平台推测。

其他约定：

- 快照会显式复制一份 RGBA 数据。
- PCM 计数记录的是已被接收的字节数。
- 解码画面的宽或高最大 16384。

## 构建

依赖和构建命令见[脚本说明](../../scripts/README.md)。FFmpeg 补丁及对应源码要求见 [patches](third_party/patches/README.md)。
