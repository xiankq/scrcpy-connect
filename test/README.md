# 仓库测试

应用与能力包用例留在所属模块；这里存放仓库工具测试、设备 driver 和夹具。`scripts/` 只保留构建、生成和检查入口。

## 测试取舍

先定位行为所属的公开接口并复用现有测试。新增用例须能指出尚未覆盖的可观察结果、失败分支或兼容边界；纯转发、字段赋值和实现结构由已有行为测试或静态检查验证。

相同行为的输入变体使用具名数据表；重复准备逻辑放就近夹具，测试保留独立的期望值与关键步骤。取消、迟到回执、写入结果未知、精确资源归属和清理重试是不同保证，只有触发条件与可观察结果均相同才合并。断言命令次数仅用于证明执行、重放或所有权契约。

选择能验证行为的最低测试层：规则与状态转换使用宿主测试，控件交互使用 widget 测试，原生与协议边界在能力包验证；设备测试保留真实系统交互及独立设备证据。计时逻辑优先推进虚拟时钟，异步协作使用事件或 Completer；真实 I/O 保持有界等待。夹具只模拟边界事实，避免复刻被测算法。

修改后先跑受影响测试及静态检查；公共夹具变化运行全部使用者。`scripts/check_test_budget.dart --report` 查看预算，预算是上限；精简后收紧受影响桶，新增覆盖有必要时在同次变更中说明预算调整。

## 运行

宿主测试使用独立 Dart 依赖与锁文件，避免触发 Flutter 原生 hooks：

```sh
cd test/host
dart pub get --enforce-lockfile
dart test
```

macOS 单独运行应用的原生 ADB 测试时，先用 `packages/adb/tool/prepare_adb.dart --platform macos` 准备二进制，并设置 `INTEROP_OFFICIAL_ADB_BINARY` 为缓存中的绝对路径。临时目录用 `TMPDIR="$(cd "${TMPDIR:-/tmp}" && pwd -P)"` 解析物理路径，避免系统 `/var` 链接干扰路径归属与故障注入。完整门禁自动处理这两项。

设计 token 测试通过 `npm test --prefix scripts/design_tokens` 运行。完整门禁为 `scripts/check.sh`；`--android` 还运行 JVM 原生契约。

设备测试从 `app/` 运行，driver 与目标成对使用。只收集截图和报告的流程（启动、声音活动、文件搜索、纹理回放）共用 `driver/capture.dart`，断言留在目标测试：

```sh
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-capture flutter drive -d <device> \
  --driver=../test/driver/capture.dart --target=integration_test/<test>.dart
```

截图共用 driver 未指定输出目录时创建独立系统临时目录；专用 driver 的输出位置由各自环境变量指定。操作 ADB、系统界面或外部夹具的流程使用各自 driver；夹具构建与设备使用见 [fixtures](fixtures/README.md)。
