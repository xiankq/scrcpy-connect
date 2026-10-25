import 'package:scrcpy_connect/models/companion_exception.dart';

import 'dart:convert';
import 'dart:typed_data';

/// 按字节限制单帧；不先把无换行输入解码为无界字符串。
Stream<Uint8List> companionLines(
  Stream<Uint8List> chunks, {
  required int maximumBytes,
}) async* {
  final pending = BytesBuilder(copy: false);
  await for (final chunk in chunks) {
    var start = 0;
    for (var index = 0; index < chunk.length; index++) {
      if (chunk[index] != 10) continue;
      if (pending.length + index - start > maximumBytes) {
        throw const CompanionException('protocol_error', '互联服务消息超过限制。');
      }
      pending.add(chunk.sublist(start, index));
      yield pending.takeBytes();
      start = index + 1;
    }
    if (pending.length + chunk.length - start > maximumBytes) {
      throw const CompanionException('protocol_error', '互联服务消息超过限制。');
    }
    pending.add(chunk.sublist(start));
  }
  if (pending.isNotEmpty) {
    throw const CompanionException('protocol_error', '互联服务消息在帧结束前中断。');
  }
}

Map<String, Object?> companionMessage(Uint8List frame) {
  try {
    final value = jsonDecode(utf8.decode(frame));
    if (value is! Map<String, dynamic>) throw const FormatException();
    return Map<String, Object?>.unmodifiable(value);
  } on FormatException {
    throw const CompanionException('protocol_error', '互联服务返回了无效 JSON 对象。');
  }
}
