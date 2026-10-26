import 'dart:io';

import 'package:adb/adb.dart';

/// 身份文件和元数据使用真实磁盘，只替换本测试不关心的 RSA 计算。
final class DiskIdentities implements AdbIdentities {
  DiskIdentities({this.conflictError = 'conflict'});
  final String? conflictError;
  bool unknownReplacement = false;
  AdbIdentityInfo _info(String pem) => AdbIdentityInfo(
    fingerprint: (pem == 'key-a' ? 'a' : 'b') * 64,
    fingerprintAlgorithm: 'sha256',
    fingerprintInput: 'adb-public-key-interop-v1',
    bits: 2048,
    exponent: 65537,
  );
  @override
  Future<void> prepareIdentity(String path) async {
    final file = File(path);
    if (!await file.exists()) await file.writeAsString('key-a', flush: true);
  }

  @override
  Future<AdbIdentityInfo?> inspectIdentity(String path) async {
    final file = File(path);
    return await file.exists() ? _info(await file.readAsString()) : null;
  }

  @override
  Future<AdbIdentityInfo> validateIdentity(String pem) async => _info(pem);
  @override
  Future<AdbIdentityCommitReceipt> replaceIdentity(
    String path,
    String pem, {
    String? expectedFingerprint,
  }) async {
    if ((await inspectIdentity(path))?.fingerprint != expectedFingerprint) {
      return AdbIdentityCommitReceipt(
        state: AdbIdentityCommitState.unchanged,
        error: conflictError,
      );
    }
    final file = File('$path.tmp');
    await file.writeAsString(pem, flush: true);
    await file.rename(path);
    if (unknownReplacement) {
      return const AdbIdentityCommitReceipt(
        state: AdbIdentityCommitState.unknown,
      );
    }
    return AdbIdentityCommitReceipt(
      state: AdbIdentityCommitState.committed,
      identity: _info(pem),
    );
  }
}
