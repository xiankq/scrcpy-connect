# 视频性能测量

当前路径为 Rust scrcpy packet source → Rust 媒体核心 → 裁剪 FFmpeg → 平台纹理。构建来源见[工具链契约](repository-tooling.md#原生媒体与官方-adb)，所有权见[架构](architecture.md)。性能结果按实际版本、后端、构建模式与运行环境记录于[验收索引](validation.md)。

## 指标与证据

- 完整首像素从 `session.start` 前计时，到真实首帧像素校验结束；不包含 Flutter 进程启动或此前 `devices.connect`。冷启动、暖启动分别保留。
- 输入到新像素通过真实 `session.key` 改变独立目标夹具的 4bit 计数，再从解码帧识别同一计数。耗时包含派发、目标绘制、编码、传输、解码、回读与轮询，是输入到可读像素的上界，不能称作纯解码或面板延迟。
- Flutter 纹理挂载、合成窗口像素与暂停恢复单独验证。`RepaintBoundary` 截图只说明测试绑定的合成结果；系统截图与普通 Driver 的测量不能混入同一分布。
- 首包、解码器打开、有效 snapshot 和最终屏幕显示分别记录。后端事件描述实际选中的 decoder；候选列表、MediaCodec 接口或模拟器标志都不单独证明物理硬解。
- 停止、取消、重建、过期代际和原生资源释放也必须通过。未知回执不作为成功；失败样本不从分布中删去。

默认严格预算保持首像素 ≤1000ms、输入 P50≤200ms/P95≤300ms。显式放宽预算的运行只作诊断，须在结果中记录阈值，不能冒称严格验收。样本数量、请求与实际尺寸、码率、帧率、编码器、ADB 模式、构建模式、主控与目标环境同样记录。

## 重复测量入口

先用独立目标准备已授权 TCP 端口，再构建仅供测试的夹具：

```sh
dart tool/e2e/video_fixture/build.dart --output /tmp/connect-video-fixture
```

从 `app/` 运行：

```sh
CONNECT_E2E_ADB=<SDK>/platform-tools/adb \
CONNECT_E2E_DEVICE=<主控serial> CONNECT_E2E_TARGET=<目标serial> \
CONNECT_E2E_VIDEO_FIXTURE=/tmp/connect-video-fixture/video-fixture.apk \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-video-measurement \
flutter drive -d <主控serial> \
  --driver=../tool/driver/video_performance.dart \
  --target=integration_test/video_performance_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=<目标地址> \
  --dart-define=CONNECT_E2E_PORT=<目标端口> \
  --dart-define=CONNECT_PERF_ROUNDS=3 \
  --dart-define=CONNECT_PERF_TRANSITIONS=20
```

当前入口固定 H.264、最大边720、60fps，实际尺寸由会话回执记录。Driver 临时安装独立夹具并清理；发现已有同名安装时拒绝覆盖。证据写入新建的系统临时目录。计时期间停止并行编译，重复运行时保持目标内容、AVD资源、构建模式、画质和网络相同。比较协议或后端时一次只改变一个变量，不把各段中位数相加重建端到端耗时。

`app/integration_test/media_video_lifecycle_test.dart` 验证挂载纹理之前取得真实像素、暂停恢复与精确会话释放；`media_audio_lifecycle_test.dart` 检查 PCM 原生接收字节、时钟、焦点与生命周期。音频字节被平台接受不等于已听见扬声器输出。

## 时钟与限制

PTS 用于帧身份，不直接作为跨设备时钟。同一主控进程的阶段使用单调时钟。目标绘制与主控关联必须额外测量时钟偏移范围，保留量化、休眠与时钟跳变限制；缺失或重复身份不能用最近帧替代。

AVD 与本机 GPU、SDK 编译、协议夹具和实体设备分别提供证据。当前机器通过不能外推所有 CPU/OEM、真实无线漫游、P99、小时级长稳、温度功耗、多活动并发或音画同步。Apple 未经 SDK/机器验收时明确标记未验证。具体版本的测量结果写入验收记录，不更新本文件为临时样本数或路径。
