# 应用命令契约

`commands.json` 定义应用内 Dart 命令、请求与结果的字段形状，以及状态核验要求。生成输出仅为 `app/lib/application/transport/commands_generated.dart`；业务分派与资源所有权由应用模块负责。FRB 类型契约、平台 MethodChannel 和伴生服务 RPC 分别维护，不使用这份应用命令表。

修改后从仓库根目录运行 `dart tool/protocol_codegen.dart`。`--check` 在临时目录格式化预期输出，再与当前文件比较，不重写产物。主检查脚本分别核验应用命令和 FRB 生成物。

请求和结果直接使用 Dart Map，由 `command_contract.dart` 核验必需字段及已提供的可选字段。没有应用 JSON 编解码桥，也不生成 Rust 命令分派器。可选字段为 null 时视为缺省，未知字段允许扩展；范围、默认值、权限、设备归属、资源代次和副作用仍由对应所有者核验。

添加命令时声明稳定字段，重新生成，在责任模块中实现分派并验证行为。需要等待状态对账的操作声明 `requiresVerifiedState`；按键和触摸 UP/CANCEL 的清理例外由状态恢复模块维护。
