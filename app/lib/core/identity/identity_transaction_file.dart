import 'package:scrcpy_connect/core/identity/identity_transaction.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'package:scrcpy_connect/core/application/request_failure.dart';
import 'package:scrcpy_connect/core/devices/device_record.dart'
    show validDeviceId;

/// 由身份所有者的串行队列独占；私有目录的边界在应用初始化时统一核验。
final class IdentityTransactionFile {
  IdentityTransactionFile(Directory directory)
    : file = File(p.join(directory.path, 'identity_transaction.json'));
  final File file;

  Future<IdentityTransaction?> read() async {
    try {
      if (await file.length() > 64 * 1024) _corrupt();
      final bytes = await file.readAsBytes();
      if (bytes.length > 64 * 1024) _corrupt();
      final document = jsonDecode(utf8.decode(bytes));
      if (document is! Map<String, Object?>) _corrupt();
      final version = document['version'];
      if (version is int && version > 1) {
        throw const RequestFailure('storage_version', '身份事务版本较新，请更新应用；原文件已保留。');
      }
      if (version is! int || version != 1) _corrupt();
      final kind = IdentityTransactionKind.values
          .where((kind) => kind.name == document['kind'])
          .firstOrNull;
      final affected = document['affected'];
      final global = document['global'];
      final device = document['deviceId'];
      final previous = document['previousFingerprint'];
      final fingerprint = document['fingerprint'];
      if (kind == null ||
          affected is! List ||
          affected.length > 256 ||
          affected.any((id) => id is! String || !validDeviceId(id)) ||
          global is! bool ||
          device != null && (device is! String || !validDeviceId(device)) ||
          previous != null && !_fingerprint(previous) ||
          fingerprint != null && !_fingerprint(fingerprint)) {
        _corrupt();
      }
      final ids = affected.cast<String>().toSet();
      if (ids.length != affected.length ||
          kind == IdentityTransactionKind.key && fingerprint == null ||
          kind == IdentityTransactionKind.useGlobal && device == null ||
          kind != IdentityTransactionKind.retire &&
              global != (device == null) ||
          device != null && (ids.length != 1 || !ids.contains(device))) {
        _corrupt();
      }
      return IdentityTransaction(
        kind: kind,
        affected: ids,
        global: global,
        deviceId: device as String?,
        previousFingerprint: previous as String?,
        fingerprint: fingerprint as String?,
      );
    } on PathNotFoundException {
      return null;
    } on FormatException {
      _corrupt();
    }
  }

  Future<void> write(IdentityTransaction transaction) async {
    final bytes = utf8.encode(jsonEncode(transaction.toJson()));
    final temporary = File(
      '${file.path}.${pid}_${Random.secure().nextInt(0x7fffffff)}.tmp',
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
        await temporary.rename(file.path);
      } on FileSystemException {
        // 发布完成但回执丢失时核对实际字节，不重新执行密钥替换。
        if (!await _matches(file, bytes)) rethrow;
      }
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        /* 未发布的临时文件不改变事务结果。 */
      }
    }
  }

  Future<void> clear() async {
    try {
      await file.delete();
    } on PathNotFoundException {
      // 删除后的迟到回执或重复清理均已完成。
    }
  }
}

bool _fingerprint(Object value) =>
    value is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
Never _corrupt() => throw const RequestFailure(
  'identity_transaction_corrupt',
  '身份事务损坏，原文件已保留；请核对本机存储。',
);
Future<bool> _matches(File file, List<int> expected) async {
  try {
    final actual = await file.readAsBytes();
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  } on FileSystemException {
    return false;
  }
}
