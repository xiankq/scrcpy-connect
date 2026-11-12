# media_codec

Flutter 原生视频包解码与 48 kHz 双声道 signed-16 PCM 输出；不负责 ADB、捕获、文件播放或编码。

```dart
final controller = MediaCodecController.video();
await controller.open(source);
final widget = MediaCodecView.controller(controller);
// 根据 controller.events 刷新元数据；使用完后：
await controller.dispose();
```

来源 ID、代次和地址仅限本进程，不能持久化或写日志。压缩包留在原生通道；来源附着与播放器输出分别拥有生命周期。`dispose()` 等待已受理操作，销毁失败保留同一 controller 重试。

状态、暂停和音量通过 FRB 调用同一 Rust 解码器；平台插件负责创建、销毁、纹理及系统音频。控制 ID 在销毁时撤销，不跨动态库使用。平台与媒体生产者仍使用内部 C ABI，Dart 不维护另一套媒体 FFI 绑定。Apple 宿主使用动态 CocoaPods framework（`use_frameworks!`）。

先挂载 texture，再等待 `waitForPresentation()`。解码、纹理准备、Flutter 合成与屏幕显示分别取证；硬解可用不表示本次选中硬解。快照是显式 RGBA 复制，PCM 接纳字节不证明声音可闻。单边解码尺寸上限 16384，不限制 scrcpy 协议表达范围。

依赖与构建见[脚本入口](../../scripts/README.md)，受控补丁及对应源码要求见[patches](third_party/patches/README.md)。
