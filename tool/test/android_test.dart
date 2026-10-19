import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../android.dart' as android;

void main() {
  late Directory temporary;
  setUp(() => temporary = Directory.systemTemp.createTempSync('android-test-'));
  tearDown(() => temporary.deleteSync(recursive: true));

  test('stale integration registration fails before Flutter is invoked', () {
    final base = Directory(p.join(temporary.path, 'android'))..createSync();
    File(p.join(base.path, 'key.properties')).createSync();
    final registrant = File(
      p.join(
        base.path,
        'app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
      ),
    );
    registrant.parent.createSync(recursive: true);
    registrant.writeAsStringSync(
      'new dev.flutter.plugins.integration_test.IntegrationTestPlugin()',
    );
    expect(
      () => android.buildApk(application: temporary, noPub: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('--no-pub'),
        ),
      ),
    );
  });

  List<int> apk({
    bool kernel = false,
    bool wrongMachine = false,
    bool includeRust = true,
  }) {
    final archive = Archive();
    void entry(String name, List<int> bytes) => archive.addFile(
      ArchiveFile(name, bytes.length, bytes)..compress = false,
    );
    for (final name in [
      'AndroidManifest.xml',
      'classes.dex',
      'resources.arsc',
    ]) {
      entry(name, [1, 2, 3]);
    }
    if (kernel) entry('assets/flutter_assets/kernel_blob.bin', [1]);
    for (final name in [
      'libflutter.so',
      if (!kernel) 'libapp.so',
      if (includeRust) 'libinterop_bridge.so',
    ]) {
      final header = List<int>.filled(20, 0);
      header.setRange(0, 6, [0x7f, 0x45, 0x4c, 0x46, 2, 1]);
      header[18] = wrongMachine && name == 'libinterop_bridge.so' ? 40 : 183;
      entry('lib/arm64-v8a/$name', header);
    }
    return ZipEncoder().encode(archive)!;
  }

  test('APK checks reject mismatched requested and native architectures', () {
    expect(android.verifyApkArchive(apk(), ['arm64-v8a']), ['arm64-v8a']);
    expect(android.verifyApkArchive(apk(kernel: true), ['arm64-v8a']), [
      'arm64-v8a',
    ]);
    expect(() => android.verifyApkArchive(apk(), ['x86_64']), throwsStateError);
    expect(
      () => android.verifyApkArchive(apk(wrongMachine: true)),
      throwsStateError,
    );
    expect(
      () => android.verifyApkArchive(apk(includeRust: false)),
      throwsStateError,
    );
  });

  test('APK CRC verification rejects corrupt stored data', () {
    final bytes = apk();
    // The first local header is followed by the required manifest's stored
    // payload. Its fixed CRC must no longer match after mutation.
    final nameLength = bytes[26] | bytes[27] << 8;
    final extraLength = bytes[28] | bytes[29] << 8;
    bytes[30 + nameLength + extraLength] ^= 1;
    expect(() => android.verifyApkArchive(bytes), throwsA(anything));
  });

  test('APK CRC verification includes central directory records', () {
    final bytes = apk();
    for (var index = 0; index + 20 < bytes.length; index++) {
      if (bytes[index] == 0x50 &&
          bytes[index + 1] == 0x4b &&
          bytes[index + 2] == 0x01 &&
          bytes[index + 3] == 0x02) {
        bytes[index + 16] ^= 1;
        expect(() => android.verifyApkArchive(bytes), throwsStateError);
        return;
      }
    }
    fail('Fixture lacks a ZIP central directory');
  });

  test('signing refuses to replace an existing key without its properties', () {
    final key = File(
      p.join(temporary.path, 'keystores/connect-local-release.jks'),
    );
    key.parent.createSync(recursive: true);
    key.writeAsStringSync('existing identity');
    expect(
      () => android.initializeSigning(android: temporary),
      throwsStateError,
    );
    expect(key.readAsStringSync(), 'existing identity');
  });
}
