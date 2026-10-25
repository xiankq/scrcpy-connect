# 开发工具

仓库根使用 `dart --disable-dart-dev tool/<entry>.dart`；设备测试从 `app/` 运行。

| 任务 | 入口 |
| --- | --- |
| Android 分 ABI 发布 | `android.dart build`；通用包显式 `--abi universal` |
| 桌面/Apple 构建 | `build_host.dart` |
| 生成及漂移检查 | `generate.dart` / `generate.dart --check` |
| 应用命令 | `protocol_codegen.dart` |
| 完整门禁 | `check.sh`；`--android` 默认仅 arm64 调试包 |
| 测试预算 | `check_test_budget.dart`；`--report` 只读 |
| JVM 原生契约 | `native_contracts.dart` |
| 设备流程与夹具 | `driver/`、[e2e](e2e/README.md) |
| 图像比较/token | [visual_parity](visual_parity/README.md)、[design_tokens](design_tokens/README.md) |

纯宿主工具测试独立运行，不触发 Flutter 原生 hooks：

```sh
cd tool/host
dart pub get --enforce-lockfile
dart test
```

日常仅跑受影响测试；完整门禁及产物保留规则见[工具链](../docs/implementation/repository-tooling.md)。
