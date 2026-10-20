import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../build_host.dart' as host;
import '../generate.dart' as generate;
import '../src/core_tooling.dart';

void main() {
  late Directory temporary;
  setUp(
    () => temporary = Directory.systemTemp.createTempSync('delivery-test-'),
  );
  tearDown(() => temporary.deleteSync(recursive: true));

  test('FRB Rust formatting uses workspace edition and preserves siblings', () {
    final output = File(p.join(temporary.path, generate.outputs.first));
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      'use example::{transform_result_dco, Lifetimeable, Lockable};\n',
    );
    final sibling = File(p.join(output.parent.path, 'lib.rs'))
      ..writeAsStringSync('pub fn unrelated( ) { }\n');
    final original = sibling.readAsBytesSync();
    generate.formatFrbRust(temporary);
    expect(
      output.readAsStringSync(),
      'use example::{Lifetimeable, Lockable, transform_result_dco};\n',
    );
    expect(sibling.readAsBytesSync(), original);
    final first = output.readAsBytesSync();
    generate.formatFrbRust(temporary);
    expect(output.readAsBytesSync(), first);
  });

  test('FRB isolation copies sources and metadata without workspace links', () {
    final source = Directory(p.join(temporary.path, 'source'))..createSync();
    final isolated = Directory(p.join(temporary.path, 'isolated'))
      ..createSync();
    for (final name in [
      'Cargo.toml',
      'Cargo.lock',
      'rust-toolchain.toml',
      'flutter_rust_bridge.yaml',
      'pubspec.yaml',
      'pubspec.lock',
      'app/pubspec.yaml',
      'app/lib/main.dart',
      'app/lib/generated.g.dart',
      'app/.dart_tool/flutter_build/cache',
      'app/build/app.apk',
      'app/android/local.properties',
      'app/android/key.properties',
      'crates/bridge/src/lib.rs',
      'crates/bridge/target/cache',
      '.dart_tool/package_config.json',
    ]) {
      final file = File(p.join(source.path, name));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(name);
    }
    generate.copyFrbInputs(source, isolated);
    for (final name in [
      'app/pubspec.yaml',
      'app/lib/main.dart',
      'app/lib/generated.g.dart',
    ]) {
      expect(File(p.join(isolated.path, name)).readAsStringSync(), name);
    }
    for (final name in ['app/.dart_tool', 'app/build', 'app/android']) {
      expect(Directory(p.join(isolated.path, name)).existsSync(), isFalse);
    }
    final copied = File(p.join(isolated.path, 'crates/bridge/src/lib.rs'))
      ..writeAsStringSync('generator edit');
    expect(copied.readAsStringSync(), 'generator edit');
    expect(
      File(p.join(source.path, 'crates/bridge/src/lib.rs')).readAsStringSync(),
      'crates/bridge/src/lib.rs',
    );
    expect(
      File(p.join(isolated.path, 'crates/bridge/target/cache')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(isolated.path, '.dart_tool/package_config.json'))
          .readAsStringSync(),
      '.dart_tool/package_config.json',
    );
  });

  test('Windows bundle requires a unique valid packaged x64 Rust library', () {
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
      'interop_bridge.dll',
      'mdk.dll',
      'ffmpeg-9.dll',
    ]) {
      File(p.join(bundle.path, name)).writeAsBytesSync(header);
    }
    final assets = File(
      p.join(bundle.path, 'data/flutter_assets/AssetManifest.bin'),
    );
    assets.parent.createSync(recursive: true);
    assets.writeAsStringSync('assets');
    host.verifyWindows(bundle);
    final library = File(p.join(bundle.path, 'interop_bridge.dll'))
      ..deleteSync();
    expect(
      () => host.verifyWindows(bundle),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('interop_bridge'),
        ),
      ),
    );
    data.setUint16(68, 0x14c, Endian.little);
    library.writeAsBytesSync(header);
    expect(() => host.verifyWindows(bundle), throwsStateError);
    data.setUint16(68, 0x8664, Endian.little);
    library.writeAsBytesSync(header);
    final duplicate = File(p.join(bundle.path, 'nested/interop_bridge.dll'));
    duplicate.parent.createSync();
    duplicate.writeAsBytesSync(header);
    expect(() => host.verifyWindows(bundle), throwsStateError);
    duplicate.deleteSync();
    final artifacts = Directory(p.join(temporary.path, 'artifacts'));
    host.archiveBundle(bundle, 'windows', artifacts);
    final archive = ZipDecoder().decodeBytes(
      File(p.join(artifacts.path, 'windows-release.zip')).readAsBytesSync(),
      verify: true,
    );
    expect(archive.findFile('interop_bridge.dll')!.content, header);
    expect(
      archive.findFile('data/flutter_assets/AssetManifest.bin')!.content,
      utf8.encode('assets'),
    );
  });

  test('Apple archive preserves executable mode and framework symlinks', () {
    final bundle = Directory(p.join(temporary.path, 'Connect.app'))
      ..createSync();
    final binary = File(p.join(bundle.path, 'Contents/MacOS/Connect'));
    binary.parent.createSync(recursive: true);
    binary.writeAsStringSync('executable');
    runTool(['chmod', '755', binary.path]);
    final version = Directory(
      p.join(bundle.path, 'Contents/Frameworks/Engine.framework/Versions/A'),
    )..createSync(recursive: true);
    File(p.join(version.path, 'Engine')).writeAsStringSync('engine');
    Link(p.join(version.parent.path, 'Current')).createSync('A');
    final artifacts = Directory(p.join(temporary.path, 'artifacts'));
    host.archiveBundle(bundle, 'macos', artifacts);
    final extracted = Directory(p.join(temporary.path, 'extracted'))
      ..createSync();
    runTool([
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
  }, skip: Platform.isWindows);
}
