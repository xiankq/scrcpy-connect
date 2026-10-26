# 设备夹具

根目录先 `flutter pub get`；构建不安装 APK。支持 video、audio-focus、input、share、notification、content-delivery：

```sh
dart --disable-dart-dev scripts/build_fixture.dart video
```

`--sdk/--output` 选择工具链与系统临时输出；输入和签名身份决定缓存复用。设备流程从 `app/` 运行，driver/target 成对选择；使用专用授权设备，仅清理本轮安装、文件与转发。

视频夹具由当前的[视频测量流程](../../docs/implementation/video-performance.md)使用。
