# 视频性能目标夹具

独立APK以四个色块编码4bit计数。真实DPAD_DOWN驱动目标绘制，主控核对新解码像素及每轮Flutter合成纹理。运行 `dart tool/e2e/video_fixture/build.dart --output /tmp/connect-video-fixture`；只安装原本不存在的夹具，结束仅卸载本轮安装。日志/图像/JSON留在系统临时目录。

性能入口为 `video_performance_test.dart` / `tool/driver/video_performance.dart`，完整命令和时钟定义见[性能测量](../../../docs/implementation/video-performance.md)。固定H.264、最大边720、60fps、4Mbps；可配置Dart define：

| 参数 | 默认 | 范围/含义 |
| --- | --- | --- |
| `CONNECT_PERF_ROUNDS` |3|1–30轮独立会话 |
| `CONNECT_PERF_TRANSITIONS` |8|每轮1–100次按键 |
| `CONNECT_PERF_MAX_START_MS` |1000|首帧预算 |
| `CONNECT_PERF_MAX_P50_MS` |200|输入至新像素P50 |
| `CONNECT_PERF_MAX_P95_MS` |300|输入至新像素P95 |

`CONNECT_E2E_ADDRESS`/`CONNECT_E2E_PORT` 指向adbd；`CONNECT_E2E_DATA_DIRECTORY` 隔离身份，可放测试 `host_identity.pem`，不覆盖用户身份。Driver要求 `CONNECT_E2E_ADB`、互异的 `CONNECT_E2E_DEVICE`/`CONNECT_E2E_TARGET` 和 `CONNECT_E2E_VIDEO_FIXTURE`；`CONNECT_E2E_CAPTURE_DIR` 指定临时输出。桌面DEVICE仅作身份标记，TARGET须是真实实验serial。

输入计时为派发至可读像素的上界，每轮合成核对不纳入单次计时。预算、暂停恢复、销毁和清理均通过才返回 `videoPerformanceComplete=true`。`CONNECT_E2E_VIDEO_MOTION=true` 增加独立动画负载，须与默认静态组分别报告，不据此声称实际60fps。

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
