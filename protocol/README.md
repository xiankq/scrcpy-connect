# 应用命令契约

`commands.json` 定义 Dart 应用命令字段及 `requiresVerifiedState`；仅生成 `app/lib/application/transport/commands_generated.dart`。FRB、MethodChannel 和 companion RPC 各自维护。

```sh
dart tool/protocol_codegen.dart
dart tool/protocol_codegen.dart --check
```

`--check` 只比较输出。请求/结果使用 Map；可选 null 视为缺省，未知字段允许扩展。范围、权限、设备及资源代次由业务所有者核验，生成器不实现分派。
