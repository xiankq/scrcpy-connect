# 设备夹具

根目录先 `flutter pub get`；构建不安装 APK。支持 video、audio-focus、input、share、notification、content-delivery：

```sh
dart --disable-dart-dev tool/e2e/build_fixture.dart video
```

`--sdk/--output` 选择工具链与系统临时输出；输入和签名身份决定缓存复用。设备流程从 `app/` 运行，driver/target 成对选择；使用专用授权设备，仅清理本轮安装、文件与转发。

`video_fixture/` 下 trace/slot/counter 分析器使用 `--help`；Perfetto 需要官方 trace_processor，像素分析需要显式 FFmpeg。`capture_first_counter.dart` 是原始 H264 实验，不代表 Flutter 延迟；正式方法见[视频测量](../../docs/implementation/video-performance.md)。[音调夹具](audio_fixture/README.md)仅提供目标端 PCM 输入。
