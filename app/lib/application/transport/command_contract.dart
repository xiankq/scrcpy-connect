import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/application/transport/commands_generated.dart';

/// Dart 业务模块共用的命令契约；验证结构，授权和资源代次由实际所有者核验。
ApplicationCommand validateCommandRequest(
  String name,
  Map<String, dynamic> params,
) {
  final command = ApplicationCommand.tryParse(name);
  if (command == null) {
    throw ApplicationCommandException('unknown_command', '未知操作：$name');
  }
  _validate(params, command.required, command.optional, 'invalid_argument');
  return command;
}

void validateCommandResult(
  ApplicationCommand command,
  Map<String, dynamic> result,
) {
  _validate(result, command.result, const {}, 'invalid_response');
}

void _validate(
  Map<String, dynamic> data,
  Map<String, ProtocolFieldType> required,
  Map<String, ProtocolFieldType> optional,
  String code,
) {
  for (final field in required.entries) {
    if (!_accepts(field.value, data[field.key])) {
      throw ApplicationCommandException(code, '缺少或无效的字段：${field.key}');
    }
  }
  for (final field in optional.entries) {
    final value = data[field.key];
    if (value != null && !_accepts(field.value, value)) {
      throw ApplicationCommandException(code, '无效的字段：${field.key}');
    }
  }
}

bool _accepts(ProtocolFieldType type, Object? value) => switch (type) {
  ProtocolFieldType.string =>
    value is String && value.isNotEmpty && !value.contains('\u0000'),
  ProtocolFieldType.text => value is String && !value.contains('\u0000'),
  ProtocolFieldType.integer => value is int,
  ProtocolFieldType.number => value is num && value.isFinite,
  ProtocolFieldType.boolean => value is bool,
  ProtocolFieldType.object => value is Map<String, dynamic>,
  ProtocolFieldType.array => value is List,
};
