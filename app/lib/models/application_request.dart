import 'package:scrcpy_connect/models/application_command.dart'
    show ApplicationCommand;

export 'package:scrcpy_connect/models/application_command.dart'
    show ApplicationCommand;

typedef Json = Map<String, dynamic>;

class RequestFailure implements Exception {
  const RequestFailure(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Object? details;
  @override
  String toString() => message;
}

/// 应用内产品命令回调，由页面和协调器请求所属业务所有者。
typedef ApplicationRequest = Future<Json> Function(
  String command, [
  Json params,
]);

/// 应用内执行接口；wire 名称只由入口适配器解析。
typedef ApplicationCommandExecutor = Future<Json> Function(
  ApplicationCommand command,
  Json params,
);
