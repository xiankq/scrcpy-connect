# 仓库脚本

仓库根使用 `dart --disable-dart-dev scripts/<entry>.dart`。

| 任务 | 入口 |
| --- | --- |
| Android 构建与交付校验 | `android.dart build` / `android.dart verify <APK> [--abis ...]`；通用包显式 `--abi universal` |
| 桌面/Apple 构建 | `build_host.dart` |
| 生成及漂移检查 | `generate.dart` / `generate.dart --check` |
| 完整门禁 | `check.sh`；`--android` 默认仅 arm64 调试包 |
| 设计 token | [design_tokens](design_tokens/README.md) |

构建入口会核验最终产物；Android 的独立 `verify` 复用同一签名、ABI、manifest 与共享资源检查。`generate` 负责生成物和共享资源同步，设备端源码及产物构建统一由 `servers/build.dart` 处理。`src/` 仅放公共实现，不作为命令入口。


测试选择与运行见[测试说明](../test/README.md)；受控产物及来源保留规则见[执行端约束](../servers/AGENTS.md)。
