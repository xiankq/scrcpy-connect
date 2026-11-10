import 'package:scrcpy_connect/models/settings_snapshot.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:scrcpy_connect/models/preference_schema.dart';

const _format = 'scrcpy-connect-preferences';
const _maxBytes = 8 * 1024 * 1024;
final _queues = <String, Future<void>>{};
final _random = Random.secure();

/// 独立持久化的偏好所有者，不写入、重命名或删除设备记录和授权身份。
/// 只在同一 isolate 内使用，其他 isolate 应向该所有者发请求。
/// POSIX 建议锁不能串行化同一进程内的多个 isolate。
final class SettingsStore {
  SettingsStore._(this.directory, this.schema);
  final Directory directory;
  final PreferenceSchema schema;
  late SettingsSnapshot _current;
  SettingsSnapshot get current => _current;
  File get _file => File.fromUri(directory.uri.resolve('preferences.json'));

  static Future<SettingsStore> open({
    required Directory directory,
    required PreferenceSchema schema,
  }) async {
    await directory.create(recursive: true);
    final owner = SettingsStore._(
      Directory(await directory.resolveSymbolicLinks()),
      schema,
    );
    await owner._exclusive(() async {
      final saved = await owner._read();
      if (saved != null) {
        owner._current = saved;
        return;
      }
      final legacy = File.fromUri(owner.directory.uri.resolve('devices.json'));
      Map<String, Object?> values;
      try {
        final document = await _readJson(legacy);
        if (document is! Map || document['version'] is! int) {
          throw const PreferenceFailure('preferences_corrupt', '旧设备记录格式无效。');
        }
        values = schema.migrateLegacy(
          document.containsKey('settings')
              ? document['settings']
              : <String, Object?>{},
          version: document['version'] as int,
        );
      } on PathNotFoundException {
        values = schema.defaults;
      }
      final initial = SettingsSnapshot(1, values);
      await owner._write(initial);
      owner._current = initial;
    });
    return owner;
  }

  Future<SettingsSnapshot> reload() => _exclusive(() async {
    final saved = await _read();
    if (saved == null) {
      throw const PreferenceFailure(
        'preferences_missing',
        '设置文件已消失，请重新检查本机存储。',
      );
    }
    return _current = saved;
  });

  Future<SettingsSnapshot> update(Object? changes, {int? expectedRevision}) {
    final validated = schema.validate(changes);
    return _commit(
      (current) => schema.merge(current, validated),
      expectedRevision: expectedRevision,
    );
  }

  Future<SettingsSnapshot> reset({Set<String>? keys, int? expectedRevision}) {
    final defaults = schema.defaults;
    if (keys != null && keys.any((key) => !defaults.containsKey(key))) {
      throw const PreferenceFailure('invalid_argument', '重置包含未知设置。');
    }
    return _commit(
      (current) => keys == null
          ? defaults
          : {...current, for (final key in keys) key: defaults[key]},
      expectedRevision: expectedRevision,
    );
  }

  Future<SettingsSnapshot> _commit(
    Map<String, Object?> Function(Map<String, Object?>) change, {
    required int? expectedRevision,
  }) => _exclusive(() async {
    final saved = await _read();
    if (saved == null) {
      throw const PreferenceFailure(
        'preferences_missing',
        '设置文件已消失，请重新检查本机存储。',
      );
    }
    final expected = expectedRevision ?? _current.revision;
    if (saved.revision != expected) {
      _current = saved;
      throw PreferenceFailure('preferences_conflict', '设置已被其他操作更新，请重新检查。', {
        'expectedRevision': expected,
        'actualRevision': saved.revision,
      });
    }
    final next = SettingsSnapshot(
      saved.revision + 1,
      schema.validate(change(saved.toMap())),
    );
    await _write(next);
    return _current = next;
  });

  Future<SettingsSnapshot?> _read() async {
    Object? document;
    try {
      document = await _readJson(_file);
    } on PathNotFoundException {
      return null;
    }
    if (document is! Map ||
        document['format'] != _format ||
        document['version'] != 1 ||
        document['revision'] is! int ||
        (document['revision'] as int) < 1) {
      throw const PreferenceFailure('preferences_corrupt', '设置记录格式或版本无效。');
    }
    return SettingsSnapshot(
      document['revision'] as int,
      schema.merge(schema.defaults, schema.validate(document['settings'])),
    );
  }

  Future<void> _write(SettingsSnapshot snapshot) async {
    final bytes = utf8.encode(
      jsonEncode({
        'format': _format,
        'version': 1,
        'revision': snapshot.revision,
        'settings': snapshot.values,
      }),
    );
    if (bytes.length > _maxBytes) {
      throw const PreferenceFailure('preferences_too_large', '设置记录过大。');
    }
    final temporary = File.fromUri(
      directory.uri.resolve(
        '.preferences-$pid-${_random.nextInt(0x7fffffff)}.tmp',
      ),
    );
    try {
      final output = await temporary.open(mode: FileMode.writeOnly);
      try {
        await output.writeFrom(bytes);
        await output.flush();
      } finally {
        await output.close();
      }
      try {
        await temporary.rename(_file.path);
      } on FileSystemException catch (error) {
        // 替换可能已完成但回执丢失；报错前核对目标，绝不回滚已提交的 revision。
        try {
          final installed = await _file.readAsBytes();
          var matches = installed.length == bytes.length;
          for (var index = 0; matches && index < bytes.length; index++) {
            matches = installed[index] == bytes[index];
          }
          if (matches) return;
        } catch (_) {
          /* 保留原始文件系统错误。 */
        }
        throw PreferenceFailure(
          'preferences_write_unknown',
          '设置提交结果未知，请重新读取后核对。',
          {'revision': snapshot.revision, 'cause': error.osError?.errorCode},
        );
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final key = directory.path;
    final previous = _queues[key] ?? Future<void>.value();
    final result = previous.then((_) async {
      final lock = await File.fromUri(
        directory.uri.resolve('.preferences.lock'),
      ).open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.blockingExclusive);
        return await action();
      } finally {
        await lock.close();
      }
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_queues[key], tail)) _queues.remove(key);
      }),
    );
    return result;
  }
}

Future<Object?> _readJson(File file) async {
  if (await file.length() > _maxBytes) {
    throw const PreferenceFailure('preferences_too_large', '本机设置记录过大。');
  }
  try {
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxBytes) {
      throw const PreferenceFailure('preferences_too_large', '本机设置记录过大。');
    }
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const PreferenceFailure('preferences_corrupt', '本机设置记录损坏，原文件已保留。');
  }
}
