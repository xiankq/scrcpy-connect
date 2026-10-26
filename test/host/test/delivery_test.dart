import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../../../scripts/build_host.dart' as host;
import '../../../scripts/generate.dart' as generate;
import '../../../scripts/src/repository_tooling.dart';
import '../../../scripts/src/generation_workspace.dart';

void main() {
  late Directory temporary;
  setUp(
    () => temporary = Directory.systemTemp.createTempSync('delivery-test-'),
  );
  tearDown(() => temporary.deleteSync(recursive: true));

  test('异步生成结束前始终持有工作区文件锁', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final owner = withGenerationWorkspace(temporary, (_, _) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final child = File(p.join(temporary.path, 'contender.dart'))
      ..writeAsStringSync('''
import 'dart:io';
Future<void> main(List<String> args) async {
  final file = await File(args[0]).open(mode: FileMode.append);
  stdout.writeln('waiting');
  await stdout.flush();
  await file.lock(FileLock.blockingExclusive);
  File(args[1]).writeAsStringSync('acquired');
  await file.close();
}
''');
    final marker = File(p.join(temporary.path, 'acquired'));
    final process = await Process.start(dartExecutable, [
      child.path,
      p.join(temporary.path, 'lock'),
      marker.path,
    ]);
    final errors = process.stderr.drain<void>();
    try {
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(marker.existsSync(), isFalse);
      release.complete();
      await owner;
      expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
      expect(marker.readAsStringSync(), 'acquired');
    } finally {
      if (!release.isCompleted) release.complete();
      await owner;
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await errors;
    }
  });

  test(
    'FRB Rust formatting uses workspace edition and preserves siblings',
    () async {
      final output = File(p.join(temporary.path, generate.outputs.first));
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        'use example::{transform_result_dco, Lifetimeable, Lockable};\n',
      );
      final sibling = File(p.join(output.parent.path, 'lib.rs'))
        ..writeAsStringSync('pub fn unrelated( ) { }\n');
      final original = sibling.readAsBytesSync();
      await generate.formatFrbRust(temporary, [generate.outputs.first]);
      expect(
        output.readAsStringSync(),
        'use example::{Lifetimeable, Lockable, transform_result_dco};\n',
      );
      expect(sibling.readAsBytesSync(), original);
      final first = output.readAsBytesSync();
      await generate.formatFrbRust(temporary, [generate.outputs.first]);
      expect(output.readAsBytesSync(), first);
    },
  );

  test('FRB isolation copies sources and metadata without workspace links', () {
    final source = Directory(p.join(temporary.path, 'source'))..createSync();
    final isolated = Directory(p.join(temporary.path, 'isolated'))
      ..createSync();
    final copiedNames = [
      'Cargo.toml',
      'Cargo.lock',
      'rust-toolchain.toml',
      'pubspec.yaml',
      'pubspec.lock',
      for (final module in generate.frbModules) module.config,
      'app/pubspec.yaml',
      'packages/adb/pubspec.yaml',
      'packages/adb/lib/adb.dart',
      'packages/media_codec/pubspec.yaml',
      'packages/media_codec/native/media_codec.h',
      'packages/media_codec/third_party/ffmpeg.lock.json',
      'rust/media_codec/Cargo.lock',
      'rust/media_codec/src/api.rs',
      'rust/scrcpy/src/lib.rs',
    ];
    final excludedNames = [
      'app/lib/main.dart',
      'app/lib/generated.g.dart',
      'app/assets/servers/manifest.json',
      'packages/media_codec/third_party/ffmpeg.tar.xz',
      'servers/vendor/unused.jar',
      'app/.dart_tool/flutter_build/cache',
      'app/build/app.apk',
      'app/android/local.properties',
      'app/android/key.properties',
      'rust/adb/target/cache',
    ];
    for (final name in [
      ...copiedNames,
      ...excludedNames,
      'rust/adb/src/lib.rs',
      '.dart_tool/package_config.json',
    ]) {
      final file = File(p.join(source.path, name));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(name);
    }
    generate.copyFrbInputs(source, isolated);
    for (final name in copiedNames) {
      expect(File(p.join(isolated.path, name)).readAsStringSync(), name);
    }
    for (final name in excludedNames) {
      expect(File(p.join(isolated.path, name)).existsSync(), isFalse);
    }
    final copied = File(p.join(isolated.path, 'rust/adb/src/lib.rs'))
      ..writeAsStringSync('generator edit');
    expect(copied.readAsStringSync(), 'generator edit');
    expect(
      File(p.join(source.path, 'rust/adb/src/lib.rs')).readAsStringSync(),
      'rust/adb/src/lib.rs',
    );
    expect(
      File(p.join(isolated.path, 'rust/adb/target/cache')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(isolated.path, '.dart_tool/package_config.json'))
          .readAsStringSync(),
      '.dart_tool/package_config.json',
    );
    final originalTime = DateTime.utc(2000);
    final unchanged = File(p.join(isolated.path, 'packages/adb/lib/adb.dart'))
      ..setLastModifiedSync(originalTime);
    File(p.join(source.path, 'rust/adb/src/lib.rs')).deleteSync();
    File(p.join(isolated.path, 'obsolete.rs')).writeAsStringSync('stale');
    generate.copyFrbInputs(source, isolated);
    expect(unchanged.lastModifiedSync(), originalTime.toLocal());
    expect(File(p.join(isolated.path, 'obsolete.rs')).existsSync(), isFalse);
    expect(copied.existsSync(), isFalse);
  });

  test(
    'Windows bundle requires a unique valid packaged x64 Rust library',
    () async {
      final bundle = Directory(p.join(temporary.path, 'bundle'))..createSync();
      final header = Uint8List(72);
      header.setRange(0, 2, [0x4d, 0x5a]);
      final data = ByteData.sublistView(header)
        ..setUint32(60, 64, Endian.little)
        ..setUint16(68, 0x8664, Endian.little);
      header.setRange(64, 68, [0x50, 0x45, 0, 0]);
      for (final name in [
        'scrcpy_connect.exe',
        'flutter_windows.dll',
        'interop_scrcpy_bridge.dll',
        'media_codec_plugin.dll',
        'adb/adb.exe',
        'adb/AdbWinApi.dll',
        'adb/AdbWinUsbApi.dll',
      ]) {
        final binary = File(p.join(bundle.path, name));
        binary.parent.createSync(recursive: true);
        binary.writeAsBytesSync(header);
      }
      final receipt = File(
        p.join(bundle.path, 'licenses/media_codec/media-codec-build.json'),
      );
      receipt.parent.createSync(recursive: true);
      receipt.writeAsStringSync(
        jsonEncode({
          'options': [
            '--disable-everything',
            '--disable-avformat',
            '--disable-network',
            '--disable-programs',
          ],
        }),
      );
      final assets = File(
        p.join(bundle.path, 'data/flutter_assets/AssetManifest.bin'),
      );
      assets.parent.createSync(recursive: true);
      assets.writeAsStringSync('assets');
      host.verifyWindows(bundle);
      final redundantAdb = File(p.join(bundle.path, 'interop_adb_bridge.dll'))
        ..writeAsBytesSync(header);
      expect(() => host.verifyWindows(bundle), throwsStateError);
      redundantAdb.deleteSync();
      final removedBridge = File(p.join(bundle.path, 'interop_bridge.dll'))
        ..writeAsBytesSync(header);
      expect(
        () => host.verifyWindows(bundle),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('removed application bridge'),
          ),
        ),
      );
      removedBridge.deleteSync();
      final obsolete = File(p.join(bundle.path, 'mdk.dll'))
        ..writeAsBytesSync(header);
      expect(() => host.verifyWindows(bundle), throwsStateError);
      obsolete.deleteSync();
      final library = File(p.join(bundle.path, 'interop_scrcpy_bridge.dll'))
        ..deleteSync();
      expect(
        () => host.verifyWindows(bundle),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('interop_scrcpy_bridge'),
          ),
        ),
      );
      data.setUint16(68, 0x14c, Endian.little);
      library.writeAsBytesSync(header);
      expect(() => host.verifyWindows(bundle), throwsStateError);
      data.setUint16(68, 0x8664, Endian.little);
      library.writeAsBytesSync(header);
      final duplicate = File(
        p.join(bundle.path, 'nested/interop_scrcpy_bridge.dll'),
      );
      duplicate.parent.createSync();
      duplicate.writeAsBytesSync(header);
      expect(() => host.verifyWindows(bundle), throwsStateError);
      duplicate.deleteSync();
      final artifacts = Directory(p.join(temporary.path, 'artifacts'));
      await host.archiveBundle(bundle, 'windows', artifacts);
      final archive = ZipDecoder().decodeBytes(
        File(p.join(artifacts.path, 'windows-release.zip')).readAsBytesSync(),
        verify: true,
      );
      expect(archive.findFile('interop_adb_bridge.dll'), isNull);
      expect(archive.findFile('interop_scrcpy_bridge.dll')!.content, header);
      expect(
        archive.findFile('data/flutter_assets/AssetManifest.bin')!.content,
        utf8.encode('assets'),
      );
    },
  );

  test(
    'Apple archive preserves executable mode and framework symlinks',
    () async {
      final bundle = Directory(p.join(temporary.path, 'Connect.app'))
        ..createSync();
      final binary = File(p.join(bundle.path, 'Contents/MacOS/Connect'));
      binary.parent.createSync(recursive: true);
      binary.writeAsStringSync('executable');
      await runTool(['chmod', '755', binary.path]);
      final version = Directory(
        p.join(bundle.path, 'Contents/Frameworks/Engine.framework/Versions/A'),
      )..createSync(recursive: true);
      File(p.join(version.path, 'Engine')).writeAsStringSync('engine');
      Link(p.join(version.parent.path, 'Current')).createSync('A');
      final artifacts = Directory(p.join(temporary.path, 'artifacts'));
      await host.archiveBundle(bundle, 'macos', artifacts);
      final extracted = Directory(p.join(temporary.path, 'extracted'))
        ..createSync();
      await runTool([
        'tar',
        '-xzf',
        p.join(artifacts.path, 'macos-release.tar.gz'),
        '-C',
        extracted.path,
      ]);
      expect(
        File(p.join(extracted.path, 'Connect.app/Contents/MacOS/Connect'))
                .statSync()
                .mode &
            0x1ff,
        0x1ed,
      );
      expect(
        Link(
          p.join(
            extracted.path,
            'Connect.app/Contents/Frameworks/Engine.framework/Versions/Current',
          ),
        ).targetSync(),
        'A',
      );
    },
    skip: Platform.isWindows,
  );
}
