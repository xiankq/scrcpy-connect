# 仓库测试

应用与能力包用例留在所属模块；这里存放仓库工具测试、设备 driver 和夹具。`scripts/` 只保留构建、生成和检查入口。

宿主测试使用独立 Dart 依赖与锁文件，避免触发 Flutter 原生 hooks：

```sh
cd test/host
dart pub get --enforce-lockfile
dart test
```

设计 token 测试通过 `npm test --prefix scripts/design_tokens` 运行。完整门禁为 `scripts/check.sh`；`--android` 还运行 JVM 原生契约。

设备测试从 `app/` 运行，driver 与目标成对使用。只收集截图和报告的流程（启动、声音活动、文件搜索、纹理回放）共用 `driver/capture.dart`，断言留在目标测试：

```sh
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-capture flutter drive -d <device> \
  --driver=../test/driver/capture.dart --target=integration_test/<test>.dart
```

未指定输出目录时使用独立的系统临时目录。操作 ADB、系统界面或外部夹具的流程使用各自 driver；夹具构建与设备使用见 [fixtures](fixtures/README.md)。
