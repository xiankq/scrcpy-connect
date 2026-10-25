import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../src/fixture_cache.dart';

void main() {
  late Directory directory;
  late File apk;
  late File receipt;
  late File source;
  late File key;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('fixture-cache-');
    apk = File(p.join(directory.path, 'fixture.apk'))..writeAsStringSync('apk');
    receipt = File(p.join(directory.path, 'receipt.json'));
    source = File(p.join(directory.path, 'Source.java'))
      ..writeAsStringSync('source');
    key = File(p.join(directory.path, 'test.keystore'))
      ..writeAsStringSync('signer A');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Future<String> identity([String version = 'JDK 21']) =>
      fixtureFingerprint({'source': source, 'signer': key}, [version]);

  test('复用同时核对源码、工具版本、签名身份及实际 APK', () async {
    final original = await identity();
    await recordFixture(apk, receipt, original);
    var verified = 0;
    Future<void> verify() async {
      verified++;
    }

    expect(await canReuseFixture(apk, receipt, original, verify), isTrue);
    expect(verified, 1);
    source.writeAsStringSync('changed source');
    expect(
      await canReuseFixture(apk, receipt, await identity(), verify),
      isFalse,
    );
    source.writeAsStringSync('source');
    key.writeAsStringSync('signer B');
    expect(
      await canReuseFixture(apk, receipt, await identity(), verify),
      isFalse,
    );
    key.writeAsStringSync('signer A');
    expect(
      await canReuseFixture(apk, receipt, await identity('JDK 22'), verify),
      isFalse,
    );
    apk.writeAsStringSync('damaged apk');
    expect(await canReuseFixture(apk, receipt, original, verify), isFalse);
    expect(verified, 1);
  });

  test('损坏清单或签名验证失败不能命中', () async {
    final fingerprint = await identity();
    receipt.writeAsStringSync('{broken');
    expect(
      await canReuseFixture(apk, receipt, fingerprint, () async {}),
      isFalse,
    );
    await recordFixture(apk, receipt, fingerprint);
    expect(
      await canReuseFixture(apk, receipt, fingerprint, () async {
        throw ProcessException('apksigner', [], 'Invalid signature');
      }),
      isFalse,
    );
  });
}
