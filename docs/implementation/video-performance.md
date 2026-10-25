# 视频测量

固定入口为 `video_performance_test.dart` 与 `tool/driver/video_performance.dart`，使用独立目标夹具。从仓库根构建夹具：

```sh
dart --disable-dart-dev tool/e2e/video_fixture/build.dart --output /tmp/connect-video-fixture
```

从app运行：

```sh
CONNECT_E2E_ADB=<SDK>/platform-tools/adb \
CONNECT_E2E_DEVICE=<主控serial> CONNECT_E2E_TARGET=<目标serial> \
CONNECT_E2E_VIDEO_FIXTURE=/tmp/connect-video-fixture/video-fixture.apk \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-video-measurement \
flutter drive -d <主控serial> \
  --driver=../tool/driver/video_performance.dart \
  --target=integration_test/video_performance_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=<目标IP> \
  --dart-define=CONNECT_E2E_PORT=<目标端口>
```

首像素从session.start计到真实解码像素；输入延迟从session.key计到夹具计数出现在解码帧，是端到端上界，不是纯解码或scanout时间。轮末另核对Flutter纹理计数、暂停恢复与资源释放。

默认预算：首像素≤1000ms，输入P50≤200ms/P95≤300ms。放宽阈值只作诊断；记录宿主、后端、构建模式、分辨率与连接方式，保持目标内容和负载一致。夹具及ADB资源只清理本次创建项，已有同名安装时拒绝覆盖。
