import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late AdbIdentities identities;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('adb-identity-receipt-');
    identities = (await createNativeAdbApi()) as AdbIdentities;
  });
  tearDown(() => directory.delete(recursive: true));

  test('公开 Dart 身份能力核验真实 RSA，读取缺失身份不创建文件', () async {
    final path = p.join(directory.path, 'identity.pem');
    expect(await identities.inspectIdentity(path), isNull);
    expect(await File(path).exists(), isFalse);
    await identities.prepareIdentity(path);
    final info = (await identities.inspectIdentity(path))!;
    final validated = await identities.validateIdentity(
      await File(path).readAsString(),
    );
    expect(info.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(validated.fingerprint, info.fingerprint);
    expect(info.fingerprintAlgorithm, 'sha256');
    expect(info.fingerprintInput, 'adb-public-key-interop-v1');
    expect(info.bits, 2048);
    expect(info.exponent, 65537);
    await expectLater(
      identities.validateIdentity('不是私钥'),
      throwsA(isA<AdbException>()),
    );
    expect(
      (await identities.inspectIdentity(path))!.fingerprint,
      info.fingerprint,
    );
  });

  test('真实 CAS 替换区分冲突、相同密钥与成功发布，不覆盖迟到调用的目标', () async {
    final path = p.join(directory.path, 'identity.pem');
    final candidate = p.join(directory.path, 'candidate.pem');
    await identities.prepareIdentity(path);
    await identities.prepareIdentity(candidate);
    final oldInfo = (await identities.inspectIdentity(path))!;
    final newInfo = (await identities.inspectIdentity(candidate))!;
    final oldPem = await File(path).readAsString();
    final newPem = await File(candidate).readAsString();
    final conflict = await identities.replaceIdentity(path, newPem);
    expect(conflict.state, AdbIdentityCommitState.unchanged);
    expect(conflict.error, 'adb_identity_conflict');
    expect(await File(path).readAsString(), oldPem);
    final same = await identities.replaceIdentity(
      path,
      oldPem,
      expectedFingerprint: oldInfo.fingerprint,
    );
    expect(same.state, AdbIdentityCommitState.unchanged);
    expect(same.error, isNull);
    final committed = await identities.replaceIdentity(
      path,
      newPem,
      expectedFingerprint: oldInfo.fingerprint,
    );
    expect(committed.state, AdbIdentityCommitState.committed);
    expect(committed.identity!.fingerprint, newInfo.fingerprint);
    expect(committed.error, isNull);
    final stale = await identities.replaceIdentity(
      path,
      oldPem,
      expectedFingerprint: oldInfo.fingerprint,
    );
    expect(stale.state, AdbIdentityCommitState.unchanged);
    expect(stale.error, 'adb_identity_conflict');
    expect(
      (await identities.inspectIdentity(path))!.fingerprint,
      newInfo.fingerprint,
    );
  });
}
