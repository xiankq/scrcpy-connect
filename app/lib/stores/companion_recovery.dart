import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/models/companion_exception.dart';
import 'package:scrcpy_connect/services/companion_process.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';

const _maximumBytes = 1024 * 1024;
const _maximumEntries = 4096;
final _queues = <String, Future<void>>{};

final class CompanionRecovery {
  CompanionRecovery(this.directory);

  final Directory directory;

  Future<void> remember(
    String deviceId,
    String serial,
    CompanionDeploymentIdentity identity,
  ) => _exclusive(
    create: true,
    action: (root) async {
      _validateText(deviceId);
      _validateText(serial);
      final entries = await _read(root);
      final existing = entries
          .where((entry) => entry.identity.jarPath == identity.jarPath)
          .firstOrNull;
      if (existing != null) {
        if (existing.deviceId != deviceId ||
            existing.serial != serial ||
            existing.identity.pid != identity.pid ||
            existing.identity.started != identity.started) {
          _unknown('原互联服务部署路径的恢复身份冲突。');
        }
        return;
      }
      entries.add(_Entry(deviceId, serial, identity));
      await _write(root, entries);
    },
  );

  Future<void> recover(
    String deviceId,
    String? serial,
    DeviceConnection connection,
    AdbCancellation cancellation,
  ) => _exclusive(
    create: false,
    action: (root) async {
      cancellation.check();
      final entries = await _read(root);
      final pending = entries
          .where((entry) => entry.deviceId == deviceId)
          .toList();
      if (pending.isEmpty) return;
      if (serial == null || pending.any((entry) => entry.serial != serial)) {
        _unknown('候选设备序列号与原互联服务恢复身份不符。');
      }
      for (final entry in pending) {
        cancellation.check();
        await cleanupCompanionDeployment(
          connection,
          entry.identity,
          timeout: const Duration(seconds: 7),
        );
        // 取消不能丢失原责任；远端已退出时，下次仍能精确确认 absent。
        cancellation.check();
        entries.remove(entry);
        await _write(root, entries);
      }
    },
  );

  Future<void> _exclusive({
    required bool create,
    required Future<void> Function(Directory root) action,
  }) async {
    try {
      if (create) {
        await directory.create(recursive: true);
      } else if (!await directory.exists()) {
        return;
      }
      final root = Directory(await directory.resolveSymbolicLinks());
      final key = root.path;
      final result = (_queues[key] ?? Future<void>.value()).then((_) async {
        // 空恢复不创建账本或锁；另一实例稍后写入的债务归后续恢复处理。
        if (!create &&
            await FileSystemEntity.type(_file(root).path, followLinks: false) ==
                FileSystemEntityType.notFound) {
          return;
        }
        final lockFile = File.fromUri(
          root.uri.resolve('.pending_companion_deployments.lock'),
        );
        final type = await FileSystemEntity.type(
          lockFile.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.file) {
          _unknown('互联服务恢复锁不是普通文件。');
        }
        final lock = await lockFile.open(mode: FileMode.append);
        try {
          await lock.lock(FileLock.blockingExclusive);
          await action(root);
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
      await result;
    } on FileSystemException {
      _unknown('互联服务恢复记录读写未确认，保留原清理责任。');
    }
  }

  File _file(Directory root) =>
      File.fromUri(root.uri.resolve('pending_companion_deployments.json'));

  Future<List<_Entry>> _read(Directory root) async {
    final file = _file(root);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return [];
    if (type != FileSystemEntityType.file) {
      _unknown('互联服务恢复记录不是普通文件，原路径已保留。');
    }
    if (await file.length() > _maximumBytes) _unknown('互联服务恢复记录超过容量。');
    final bytes = await file.readAsBytes();
    if (bytes.length > _maximumBytes) _unknown('互联服务恢复记录超过容量。');
    try {
      final document = jsonDecode(utf8.decode(bytes));
      if (document is! Map ||
          document['version'] is! int ||
          document['version'] != 1 ||
          document['entries'] is! List) {
        _unknown('互联服务恢复记录格式或版本无效，原文件已保留。');
      }
      final values = document['entries'] as List;
      if (values.length > _maximumEntries) _unknown('互联服务恢复条目超过容量。');
      final entries = <_Entry>[];
      final jars = <String>{};
      for (final value in values) {
        if (value is! Map ||
            value['deviceId'] is! String ||
            value['serial'] is! String ||
            value['identity'] is! Map) {
          _unknown('互联服务恢复条目格式无效，原文件已保留。');
        }
        final deviceId = value['deviceId'] as String;
        final serial = value['serial'] as String;
        _validateText(deviceId);
        _validateText(serial);
        final rawIdentity = value['identity'] as Map;
        if (rawIdentity.keys.any((key) => key is! String)) {
          _unknown('互联服务恢复部署身份格式无效。');
        }
        final identity = CompanionDeploymentIdentity.fromJson(
          Map<String, Object?>.from(rawIdentity),
        );
        if (!jars.add(identity.jarPath)) _unknown('互联服务恢复部署路径重复。');
        entries.add(_Entry(deviceId, serial, identity));
      }
      return entries;
    } on FormatException {
      _unknown('互联服务恢复记录损坏，原文件已保留。');
    } on ArgumentError {
      _unknown('互联服务恢复部署身份无效，原文件已保留。');
    }
  }

  Future<void> _write(Directory root, List<_Entry> entries) async {
    if (entries.length > _maximumEntries) _unknown('互联服务恢复条目超过容量。');
    final bytes = utf8.encode(
      jsonEncode({
        'version': 1,
        'entries': [
          for (final entry in entries)
            {
              'deviceId': entry.deviceId,
              'serial': entry.serial,
              'identity': entry.identity.toJson(),
            },
        ],
      }),
    );
    if (bytes.length > _maximumBytes) _unknown('互联服务恢复记录超过容量。');
    final temporary = await root.createTemp('.companion-recovery-');
    try {
      final file = File.fromUri(temporary.uri.resolve('record'));
      await file.writeAsBytes(bytes, flush: true);
      await file.rename(_file(root).path);
    } finally {
      try {
        await temporary.delete(recursive: true);
      } on FileSystemException {
        // 临时目录清理不能改变已经提交的恢复责任。
      }
    }
  }
}

final class _Entry {
  const _Entry(this.deviceId, this.serial, this.identity);
  final String deviceId, serial;
  final CompanionDeploymentIdentity identity;
}

void _validateText(String value) {
  if (value.trim().isEmpty ||
      value.length > 256 ||
      value.codeUnits.any((unit) => unit < 32 || unit == 127)) {
    _unknown('互联服务恢复设备身份无效。');
  }
}

Never _unknown(String message) =>
    throw CompanionException('cleanup_unconfirmed', message);
