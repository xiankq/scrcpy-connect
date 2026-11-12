import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/identity/models/identity_host_record.dart';

/// 每代宿主的恢复记录只属于该代 scope；旧 isolate 不能覆盖后继记录。
final class NativeHostRecord {
  NativeHostRecord({
    required this.policy,
    Map<String, IdentityHostRecord>? identities,
  }) : identities = {...?identities};

  final Map<String, Object?> policy;
  final Map<String, IdentityHostRecord> identities;

  static File _file(Directory directory, String scopeId) {
    if (!RegExp(r'^[a-zA-Z0-9-]{1,128}$').hasMatch(scopeId)) {
      throw const FormatException('宿主准入句柄格式无效。');
    }
    return File(p.join(directory.path, 'host-$scopeId.json'));
  }

  static Future<NativeHostRecord> read(
    Directory directory,
    String scopeId,
  ) async {
    final file = _file(directory, scopeId);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('存活宿主缺少可核验的恢复记录。');
    }
    if (await file.length() > 1024 * 1024) {
      throw const FormatException('宿主恢复记录过大。');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 1024 * 1024) {
      throw const FormatException('宿主恢复记录过大。');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['policy'] is! Map ||
        value['identities'] is! Map) {
      throw const FormatException('宿主恢复记录格式无效。');
    }
    final entries = <String, IdentityHostRecord>{};
    for (final entry in (value['identities'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('宿主身份记录格式无效。');
      }
      entries[entry.key as String] = IdentityHostRecord.fromJson(
        Map<String, Object?>.from(entry.value as Map),
      );
    }
    return NativeHostRecord(
      policy: Map<String, Object?>.from(value['policy'] as Map),
      identities: entries,
    );
  }

  Future<void> write(Directory directory, String scopeId) async {
    await directory.create(recursive: true);
    final target = _file(directory, scopeId);
    final temporary = await directory.createTemp('.host-');
    try {
      final file = File(p.join(temporary.path, 'record'));
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'policy': policy,
          'identities': {
            for (final entry in identities.entries)
              entry.key: entry.value.toJson(),
          },
        }),
        flush: true,
      );
      await file.rename(target.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}

bool sameHostPolicy(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.entries.every(
          (entry) =>
              right.containsKey(entry.key) &&
              sameHostPolicy(entry.value, right[entry.key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(
          left.length,
          (index) => sameHostPolicy(left[index], right[index]),
        ).every((value) => value);
  }
  return left == right;
}
