# 视频性能目标夹具

独立测试 APK，不属于产品依赖。四个色块编码一个 4 bit 计数器。真实 scrcpy 控制通道发送 DPAD_DOWN 后，Android View 更新计数并绘制新图；主控从实际解码 RGBA 识别同一计数，每轮结束另核对 Flutter 合成纹理。因此保留旧帧、空白纹理或仅收到控制写入回执不能通过。

运行 `dart tool/e2e/video_fixture/build.dart --output /tmp/connect-video-fixture` 构建。驱动安装前要求该独立包不存在，结束后卸载本次夹具并返回系统设置；不替换已有安装。截图、日志和 JSON 保存在系统临时目录。

## 当前 packet-source 路径

目标为 `app/integration_test/video_performance_test.dart`，驱动为 `tool/driver/video_performance.dart`。完整命令、时钟定义和预算见[视频性能测量](../../../docs/implementation/video-performance.md)。

当前固定 H.264、最大边 720、60fps、4Mbps，实际尺寸由解码回执记录。可通过以下 Dart define 调整采样数量和严格预算：

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `CONNECT_PERF_ROUNDS` | 3 | 独立创建并停止会话的轮数，1–30 |
| `CONNECT_PERF_TRANSITIONS` | 8 | 每轮真实按键次数，1–100 |
| `CONNECT_PERF_MAX_START_MS` | 1000 | 从 session.start 前到实际首帧校验的预算 |
| `CONNECT_PERF_MAX_P50_MS` | 200 | 输入到新解码像素的 P50 预算 |
| `CONNECT_PERF_MAX_P95_MS` | 300 | 输入到新解码像素的 P95 预算 |

`CONNECT_E2E_ADDRESS`、`CONNECT_E2E_PORT` 指向被控 adbd。`CONNECT_E2E_DATA_DIRECTORY` 可指定隔离主控数据目录；若使用已授权实验密钥，在该目录准备 `host_identity.pem`。不要覆盖用户的授权身份。

Driver 要求 `CONNECT_E2E_ADB`、互不相同的 `CONNECT_E2E_DEVICE`/`CONNECT_E2E_TARGET`、`CONNECT_E2E_VIDEO_FIXTURE`，可用 `CONNECT_E2E_CAPTURE_DIR` 指定系统临时目录。桌面主控的 DEVICE 仅作身份标记，TARGET 必须是实验 ADB 可访问的真实 serial。

输入耗时包含派发、目标绘制、编码、传输、解码、回读与轮询，是输入到可读像素的上界。每轮末尾的 Flutter 合成核对不属于每个输入的计时，也不证明物理面板延迟。暂停恢复、精确会话销毁、夹具清理与预算均通过，才将 `videoPerformanceComplete` 设为 true；失败样本仍保留。

`CONNECT_E2E_VIDEO_MOTION=true` 让夹具持续改变采样带外的彩色块，增加目标绘制和编码负载。它与默认静态组分别报告；请求动画刷新不等于实际达到 60fps。旧 fvp 路径的 trace、snapshot stress、码流归档及可配置 codec 参数不再属于当前性能入口。

## 断网恢复

`tool/driver/video_recovery.dart` 和 `app/integration_test/video_recovery_test.dart` 使用隔离 TCP 代理切断真实 adbd 连接，核对新会话、真实像素与 Flutter 合成。沿用上述 ADB、双设备和夹具变量，在 `app/` 中运行：

```sh
flutter drive -d emulator-5554 --no-pub \
  --driver=../tool/driver/video_recovery.dart \
  --target=integration_test/video_recovery_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=25557
```

代理上游默认为 127.0.0.1:25556，可用 `CONNECT_E2E_UPSTREAM_PORT` 覆盖；本机 25557 须空闲。`CONNECT_E2E_RECOVERY_FAULT=blackhole` 可在保留 TCP 的同时丢弃旧连接数据。驱动只清理本次代理与夹具。这是故障注入，不能代替物理无线切网验收；既往结果见[连接健康验收](../../../docs/implementation/connection-health.md)。

## 历史追踪分析

本目录 `analyze_codec_trace.dart`、`analyze_capture_slots.dart`、`analyze_first_counter.dart`、`analyze_player_archive.dart` 是既有 Perfetto/原始码流证据的离线分析器。历史 Matroska/HTTP 和 fvp 方法见[首帧研究](../../../docs/research/scrcpy-first-frame-performance.md)，不作为新媒体路径的验收入口。`capture_first_counter.dart` 是独立 raw-drain 诊断，未经过当前 Flutter/Rust 播放路径，不能用其数字替代产品延迟。
