import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 每代宿主的恢复记录只属于该代 scope；旧 isolate 不能覆盖后继记录。
final class ApplicationHostRecord {
  ApplicationHostRecord({
    required this.policy,
    Map<String, ApplicationIdentityHost>? identities,
  }) : identities = {...?identities};

  final Map<String, Object?> policy;
  final Map<String, ApplicationIdentityHost> identities;

  static File _file(Directory directory, String scopeId) {
    if (!RegExp(r'^[a-zA-Z0-9-]{1,128}$').hasMatch(scopeId)) {
      throw const FormatException('宿主准入句柄格式无效。');
    }
    return File(p.join(directory.path, 'host-$scopeId.json'));
  }

  static Future<ApplicationHostRecord> read(
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
    final entries = <String, ApplicationIdentityHost>{};
    for (final entry in (value['identities'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('宿主身份记录格式无效。');
      }
      entries[entry.key as String] = ApplicationIdentityHost.fromJson(
        Map<String, Object?>.from(entry.value as Map),
      );
    }
    return ApplicationHostRecord(
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

final class ApplicationIdentityHost {
  const ApplicationIdentityHost({
    required this.identityPath,
    required this.fingerprint,
    required this.directory,
    this.serverId,
  });
  final String identityPath, fingerprint, directory;
  final String? serverId;

  factory ApplicationIdentityHost.fromJson(Map<String, Object?> value) {
    for (final key in ['identityPath', 'fingerprint', 'directory']) {
      if (value[key] is! String || (value[key] as String).isEmpty) {
        throw const FormatException('宿主身份事实缺失。');
      }
    }
    if (value['serverId'] != null && value['serverId'] is! String) {
      throw const FormatException('宿主服务器身份无效。');
    }
    return ApplicationIdentityHost(
      identityPath: value['identityPath'] as String,
      fingerprint: value['fingerprint'] as String,
      directory: value['directory'] as String,
      serverId: value['serverId'] as String?,
    );
  }

  ApplicationIdentityHost withServer(String id) => ApplicationIdentityHost(
    identityPath: identityPath,
    fingerprint: fingerprint,
    directory: directory,
    serverId: id,
  );

  Map<String, Object?> toJson() => {
    'identityPath': identityPath,
    'fingerprint': fingerprint,
    'directory': directory,
    'serverId': serverId,
  };
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
