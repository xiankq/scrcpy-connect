/// Build and verify the native libraries in a final host application bundle.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'src/core_tooling.dart';

final root = repositoryRoot();

int peMachine(File path) {
  final bytes = path.readAsBytesSync();
  if (bytes.length < 64 || bytes[0] != 0x4d || bytes[1] != 0x5a) {
    throw FormatException('Invalid PE file: ${path.path}');
  }
  final data = ByteData.sublistView(bytes);
  final offset = data.getUint32(0x3c, Endian.little);
  if (offset + 6 > bytes.length ||
      bytes[offset] != 0x50 ||
      bytes[offset + 1] != 0x45 ||
      bytes[offset + 2] != 0 ||
      bytes[offset + 3] != 0) {
    throw FormatException('Invalid PE signature: ${path.path}');
  }
  return data.getUint16(offset + 4, Endian.little);
}

Iterable<File> bundleFiles(Directory directory) =>
    directory.listSync(recursive: true, followLinks: true).whereType<File>();

void verifyWindows(Directory bundle) {
  final files = bundleFiles(bundle).toList();
  for (final name in [
    'scrcpy_connect.exe',
    'flutter_windows.dll',
    'interop_bridge.dll',
    'mdk.dll',
    'ffmpeg-9.dll',
  ]) {
    final matches = files
        .where((file) => p.basename(file.path) == name)
        .toList();
    if (matches.length != 1 || peMachine(matches.single) != 0x8664) {
      throw StateError('Final Windows bundle lacks one x64 $name');
    }
  }
  if (!File(p.join(bundle.path, 'data/flutter_assets/AssetManifest.bin'))
      .existsSync()) {
    throw StateError('Windows bundle lacks Flutter assets');
  }
}

String bundleExecutable(File plist) {
  final bytes = plist.readAsBytesSync();
  if (bytes.length >= 6 &&
      ascii.decode(bytes.take(6).toList(), allowInvalid: true) == 'bplist') {
    // Binary plists are native Apple build outputs; plutil handles both encodings.
    final result = runTool([
      'plutil',
      '-convert',
      'json',
      '-o',
      '-',
      plist.path,
    ], quiet: true);
    return (jsonDecode(result.stdout as String)
            as Map<String, dynamic>)['CFBundleExecutable']
        as String;
  }
  final document = XmlDocument.parse(utf8.decode(bytes));
  final values = document.findAllElements('dict').first.childElements.toList();
  for (var i = 0; i + 1 < values.length; i++) {
    if (values[i].name.local == 'key' &&
        values[i].innerText == 'CFBundleExecutable') {
      return values[i + 1].innerText;
    }
  }
  throw const FormatException('Info.plist lacks CFBundleExecutable');
}

void verifyApple(Directory bundle, String platform) {
  final contents = platform == 'macos'
      ? Directory(p.join(bundle.path, 'Contents'))
      : bundle;
  final name = bundleExecutable(File(p.join(contents.path, 'Info.plist')));
  final binary = platform == 'macos'
      ? p.join(contents.path, 'MacOS', name)
      : p.join(contents.path, name);
  runTool(['xcrun', 'lipo', '-verify_arch', 'arm64', binary]);
  final files = bundleFiles(contents).toList();
  if (!files.any(
    (file) =>
        p.basename(file.path) ==
        (platform == 'macos' ? 'FlutterMacOS' : 'Flutter'),
  )) {
    throw StateError('Apple bundle lacks its Flutter engine');
  }
  final rust = files
      .where(
        (file) =>
            p.basename(file.path).contains('interop_bridge') &&
            !{'.plist', '.json', '.h'}.contains(p.extension(file.path)),
      )
      .toList();
  if (rust.isEmpty) {
    throw StateError('Apple bundle lacks its Rust interop library');
  }
  for (final library in rust) {
    runTool(['xcrun', 'lipo', '-verify_arch', 'arm64', library.path]);
  }
  if (!files.any((file) => p.basename(file.path) == 'mdk')) {
    throw StateError('Apple bundle lacks its MDK framework');
  }
}

void archiveBundle(Directory bundle, String platform, Directory artifacts) {
  artifacts.createSync(recursive: true);
  if (platform == 'windows') {
    final archive = Archive();
    for (final entity in bundle.listSync(recursive: true)) {
      final name = p
          .relative(entity.path, from: bundle.path)
          .split(p.separator)
          .join('/');
      if (entity is File) {
        final bytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      } else if (entity is Directory) {
        archive.addFile(ArchiveFile('$name/', 0, <int>[])..isFile = false);
      }
    }
    File(p.join(artifacts.path, 'windows-release.zip'))
        .writeAsBytesSync(ZipEncoder().encode(archive)!);
  } else {
    // Native tar preserves executable modes and framework symlinks. Never
    // traverse framework links or rebuild the archive from plain file bytes.
    runTool([
      'tar',
      '-czf',
      p.join(artifacts.absolute.path, '$platform-release.tar.gz'),
      '-C',
      bundle.parent.path,
      p.basename(bundle.path),
    ]);
  }
}

void main(List<String> arguments) {
  try {
    final parser = ArgParser()
      ..addFlag('verify-only', negatable: false)
      ..addFlag('help', abbr: 'h', negatable: false);
    final args = parser.parse(arguments);
    if (args['help'] as bool) {
      stdout.writeln(
        'Usage: dart tool/build_host.dart <windows|ios|macos>\n${parser.usage}',
      );
      return;
    }
    if (args.rest.length != 1 ||
        !['windows', 'ios', 'macos'].contains(args.rest.single)) {
      throw ArgumentError(
        'Usage: dart tool/build_host.dart <windows|ios|macos> [--verify-only]',
      );
    }
    final platform = args.rest.single;
    if (!(args['verify-only'] as bool)) {
      runTool([
        executable('flutter') ?? 'flutter',
        'build',
        platform,
        '--release',
        '--no-pub',
        if (platform == 'ios') '--no-codesign',
      ], cwd: root);
    }
    late Directory bundle;
    if (platform == 'windows') {
      bundle = Directory(p.join(root.path, 'build/windows/x64/runner/Release'));
      verifyWindows(bundle);
    } else {
      final directory = Directory(
        p.join(
          root.path,
          platform == 'ios'
              ? 'build/ios/iphoneos'
              : 'build/macos/Build/Products/Release',
        ),
      );
      final bundles = directory
          .listSync()
          .whereType<Directory>()
          .where((directory) => directory.path.endsWith('.app'))
          .toList();
      if (bundles.length != 1) {
        throw StateError('Expected one final application in ${directory.path}');
      }
      bundle = bundles.single;
      verifyApple(bundle, platform);
    }
    archiveBundle(
      bundle,
      platform,
      Directory(p.join(root.path, 'build/verified')),
    );
    stdout.writeln(
      'PASS: final $platform application, Flutter engine, Rust library and MDK',
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
