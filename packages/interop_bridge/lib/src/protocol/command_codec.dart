import 'dart:convert';

import '../interop_exception.dart';
import 'commands_generated.dart';

export 'commands_generated.dart' show InteropCommand;

typedef ProtocolJson = Map<String, dynamic>;

/// The single serialization seam shared by every runtime caller.
/// Values remain extensible; command names and declared fields come from the
/// same source as Rust. Domain authorization stays with its existing owner.
class CoreRequest {
  CoreRequest(this.command, [ProtocolJson params = const {}])
    : params = Map.unmodifiable(params) {
    if (!command.core) {
      throw const InteropException('unknown_command', '此操作由主控平台处理。');
    }
    _validate(params, command.required, command.optional, 'invalid_argument');
  }

  factory CoreRequest.named(String name, [ProtocolJson params = const {}]) {
    final command = InteropCommand.tryParse(name);
    if (command == null) {
      throw InteropException('unknown_command', '未知操作：$name');
    }
    return CoreRequest(command, params);
  }

  final InteropCommand command;
  final ProtocolJson params;

  String encode() {
    final raw = jsonEncode({
      'protocolVersion': protocolVersion,
      'command': command.wire,
      'params': params,
    });
    if (utf8.encode(raw).length > 1048576) {
      throw const InteropException('request_limit', '操作内容过长。');
    }
    return raw;
  }

  ProtocolJson decodeResponse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const InteropException('invalid_response', '互联核心返回了无法解析的结果。');
    }
    if (decoded is! Map<String, dynamic> || decoded['ok'] is! bool) {
      throw const InteropException('invalid_response', '互联核心返回了无效的结果。');
    }
    if (decoded['protocolVersion'] is! int ||
        decoded['protocolVersion'] != protocolVersion) {
      throw const InteropException(
        'protocol_version',
        '界面与互联核心版本不一致，请重新安装完整应用。',
      );
    }
    if (decoded['ok'] == false) {
      final error = decoded['error'];
      if (error is! Map<String, dynamic> ||
          error['code'] is! String ||
          (error['code'] as String).isEmpty ||
          error['message'] is! String) {
        throw const InteropException('invalid_response', '互联核心返回了无效的错误结果。');
      }
      throw InteropException(
        error['code'] as String,
        error['message'] as String,
        error['details'],
      );
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const InteropException('invalid_response', '互联核心返回的内容必须是对象。');
    }
    _validate(data, command.result, const {}, 'invalid_response');
    return data;
  }
}

void _validate(
  ProtocolJson data,
  Map<String, ProtocolFieldType> required,
  Map<String, ProtocolFieldType> optional,
  String code,
) {
  for (final field in required.entries) {
    if (!_accepts(field.value, data[field.key])) {
      throw InteropException(code, '缺少或无效的字段：${field.key}');
    }
  }
  for (final field in optional.entries) {
    final value = data[field.key];
    if (value != null && !_accepts(field.value, value)) {
      throw InteropException(code, '无效的字段：${field.key}');
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
