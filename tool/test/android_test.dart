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
    bool includeServers = true,
    bool embedServer = false,
    bool corruptServer = false,
    bool duplicateServer = false,
  }) {
    final archive = Archive();
    void entry(String name, List<int> bytes) =>
        archive.addFile(ArchiveFile.noCompress(name, bytes.length, bytes));
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
      if (includeRust) ...[
        'libinterop_adb_bridge.so',
        'libinterop_scrcpy_bridge.so',
      ],
    ]) {
      final header = List<int>.filled(20, 0);
      header.setRange(0, 6, [0x7f, 0x45, 0x4c, 0x46, 2, 1]);
      header[18] = wrongMachine && name == 'libinterop_scrcpy_bridge.so'
          ? 40
          : 183;
      entry('lib/arm64-v8a/$name', [
        ...header,
        if (embedServer && name == 'libinterop_scrcpy_bridge.so')
          ...File(
            p.join(android.root.path, 'servers/vendor/scrcpy-server-v5.0.1'),
          ).readAsBytesSync(),
      ]);
    }
    if (includeServers) {
      final servers = Directory(
        p.join(android.root.path, 'app/assets/servers'),
      );
      for (final file in servers.listSync().whereType<File>()) {
        final name =
            'assets/flutter_assets/assets/servers/${p.basename(file.path)}';
        final bytes = file.readAsBytesSync();
        if (corruptServer && file.path.endsWith('scrcpy.zlib')) bytes[0] ^= 1;
        entry(name, bytes);
        if (duplicateServer && file.path.endsWith('scrcpy.zlib')) {
          entry('$name.duplicate', bytes);
        }
      }
    }
    return ZipEncoder().encode(archive);
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

  test(
    'independent APK verification rejects an archive with no native ABI',
    () {
      final archive = ZipDecoder().decodeBytes(apk());
      final withoutNative = Archive();
      for (final file in archive.files) {
        if (!file.name.startsWith('lib/')) withoutNative.addFile(file);
      }
      expect(
        () => android.verifyApkArchive(ZipEncoder().encode(withoutNative)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('lacks native libraries'),
          ),
        ),
      );
    },
  );

  test('APK requires both capability libraries and rejects the removed application bridge', () {
    for (final missing in [
      'libinterop_adb_bridge.so',
      'libinterop_scrcpy_bridge.so',
    ]) {
      final archive = Archive();
      for (final entry in ZipDecoder().decodeBytes(apk()).files) {
        if (!entry.name.endsWith('/$missing')) archive.addFile(entry);
      }
      expect(
        () => android.verifyApkArchive(ZipEncoder().encode(archive)),
        throwsStateError,
      );
    }
    final archive = ZipDecoder().decodeBytes(apk());
    archive.addFile(
      ArchiveFile.noCompress('lib/arm64-v8a/libinterop_bridge.so', 3, [
        1,
        2,
        3,
      ]),
    );
    expect(
      () => android.verifyApkArchive(ZipEncoder().encode(archive)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('removed application bridge'),
        ),
      ),
    );
  });

  test('APK CRC verification rejects corrupt stored data', () {
    final bytes = apk();
    // 首个本地头之后是必要 manifest 的存储载荷；修改后固定 CRC 应不再匹配。
    //
    final nameLength = bytes[26] | bytes[27] << 8;
    final extraLength = bytes[28] | bytes[29] << 8;
    bytes[30 + nameLength + extraLength] ^= 1;
    expect(() => android.verifyApkArchive(bytes), throwsStateError);
  });

  test('APK rejects missing, corrupt, or duplicated shared server assets', () {
    expect(
      () => android.verifyApkArchive(apk(includeServers: false)),
      throwsStateError,
    );
    expect(
      () => android.verifyApkArchive(apk(corruptServer: true)),
      throwsStateError,
    );
    expect(
      () => android.verifyApkArchive(apk(duplicateServer: true)),
      throwsStateError,
    );
  });

  test('APK rejects actual same-name ZIP entries with valid CRCs', () {
    for (final corruptDuplicate in [false, true]) {
      final archive = ZipDecoder().decodeBytes(apk());
      final original = archive.files.singleWhere(
        (file) => file.name.endsWith('/scrcpy.zlib'),
      );
      final content = original.content.toList();
      if (corruptDuplicate) content[0] ^= 1;
      final duplicate = ArchiveFile.noCompress(
        '${original.name}.shadow',
        content.length,
        content,
      );
      // Archive.addFile 按名称去重；插入后再改名，使编码器写出两个各自 CRC 正确的真实条目。
      //
      archive.addFile(duplicate);
      duplicate.name = original.name;
      final bytes = ZipEncoder().encode(archive);
      final decoder = ZipDecoder()..decodeBytes(bytes);
      final headers = decoder.directory.fileHeaders.where(
        (header) => header.filename == original.name,
      );
      expect(headers, hasLength(2));
      expect(headers.every((header) => header.file!.verifyCrc32()), isTrue);
      expect(
        () => android.verifyApkArchive(bytes),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Duplicate APK entry'),
          ),
        ),
      );
    }
  });

  test('APK rejects server payloads embedded again in native libraries', () {
    expect(
      () => android.verifyApkArchive(apk(embedServer: true)),
      throwsStateError,
    );
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

  test('APK CRC verification includes local header records', () {
    final bytes = apk();
    bytes[14] ^= 1;
    expect(() => android.verifyApkArchive(bytes), throwsStateError);
  });

  test('APK CRC verification rejects matching incorrect header CRCs', () {
    final bytes = apk();
    bytes[14] ^= 1;
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
