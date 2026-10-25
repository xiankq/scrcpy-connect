# 视频性能目标夹具

独立APK以四个色块编码4bit计数。真实DPAD_DOWN驱动目标绘制，主控核对新解码像素及每轮Flutter合成纹理。运行 `dart tool/e2e/video_fixture/build.dart --output /tmp/connect-video-fixture`；只安装原本不存在的夹具，结束仅卸载本轮安装。日志/图像/JSON留在系统临时目录。

性能入口为 `video_performance_test.dart` / `tool/driver/video_performance.dart`，完整命令和时钟定义见[性能测量](../../../docs/implementation/video-performance.md)。参数和预算以 integration_test 与 driver 为准。设备实验需要互异的专用主控/被控目标，显式指定 ADB、夹具及临时输出目录；仅清理本轮安装和样本。

## 断网恢复

`video_recovery.dart` / `video_recovery_test.dart` 使用隔离TCP代理验证新会话及真实像素。沿用上述变量，从 `app/` 运行：

```sh
flutter drive -d emulator-5554 --no-pub \
  --driver=../tool/driver/video_recovery.dart \
  --target=integration_test/video_recovery_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=25557
```

代理上游默认 `127.0.0.1:25556`，可设 `CONNECT_E2E_UPSTREAM_PORT`；本机25557须空闲。`CONNECT_E2E_RECOVERY_FAULT=blackhole` 保留TCP但丢数据。仅清理本轮资源，不替代物理切网验收。离线/原始码流分析入口见[上级说明](../README.md)。
