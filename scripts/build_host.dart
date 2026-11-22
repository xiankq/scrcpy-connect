/// 构建并核验最终宿主应用包中的原生库。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'src/repository_tooling.dart';

final root = repositoryRoot();
const macApplication = 'Interconnect.app';
const windowsExecutable = 'Interconnect.exe';
const linuxExecutable = 'interconnect';
const linuxApplicationId = 'dev.scrcpyconnect.scrcpy_connect';

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

void _rejectApplicationBridge(Iterable<File> files) {
  if (files.any(
    (file) =>
        RegExp(r'^(?:lib)?interop_bridge(?:\.|$)')
            .hasMatch(p.basename(file.path)),
  )) {
    throw StateError('Bundle contains the removed application bridge');
  }
  if (files.any(
    (file) =>
        RegExp(r'^(?:lib)?interop_adb_bridge(?:\.|$)')
            .hasMatch(p.basename(file.path)),
  )) {
    throw StateError(
      'Release bundle duplicates the composed scrcpy ADB runtime',
    );
  }
}

void verifyWindows(Directory bundle) {
  final files = bundleFiles(bundle).toList();
  _rejectApplicationBridge(files);
  const adbFiles = {'adb.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll'};
  int? adbMachine;
  for (final name in [
    windowsExecutable,
    'flutter_windows.dll',
    'interop_scrcpy_bridge.dll',
    'media_codec_plugin.dll',
    'adb.exe',
    'AdbWinApi.dll',
    'AdbWinUsbApi.dll',
  ]) {
    final matches = files
        .where((file) => p.basename(file.path) == name)
        .toList();
    if (matches.length != 1) {
      throw StateError('Final Windows bundle lacks one x64 $name');
    }
    final machine = peMachine(matches.single);
    if (adbFiles.contains(name)) {
      // 官方 platform-tools 可能包含 32 位子进程及配套 DLL；它们不会载入 x64 Flutter 进程。
      //
      if (!{0x14c, 0x8664}.contains(machine) ||
          (adbMachine != null && machine != adbMachine)) {
        throw StateError(
          'Official ADB executable and DLL architectures differ',
        );
      }
      adbMachine = machine;
    } else if (machine != 0x8664) {
      throw StateError('Final Windows bundle lacks one x64 $name');
    }
  }
  if (!File(p.join(bundle.path, 'data/flutter_assets/AssetManifest.bin'))
      .existsSync()) {
    throw StateError('Windows bundle lacks Flutter assets');
  }
  verifyMedia(bundle);
}

void verifyMedia(Directory bundle) {
  final files = bundleFiles(bundle).toList();
  if (files.any(
    (file) => RegExp(
      r'(^|lib)(mdk|fvp)|avformat|ffmpeg-\d',
      caseSensitive: false,
    ).hasMatch(p.basename(file.path)),
  )) {
    throw StateError('Bundle contains an obsolete full media runtime');
  }
  final receipts = files.where(
    (file) =>
        p.basename(file.path) == 'media-codec-build.json' &&
        p.split(file.path).contains('licenses'),
  );
  if (receipts.isEmpty) throw StateError('Missing trimmed FFmpeg receipt');
  for (final receipt in receipts) {
    final config =
        jsonDecode(receipt.readAsStringSync()) as Map<String, dynamic>;
    final options = (config['options'] as List).cast<String>();
    for (final required in [
      '--disable-everything',
      '--disable-avformat',
      '--disable-network',
      '--disable-programs',
    ]) {
      if (!options.contains(required)) {
        throw StateError('FFmpeg is missing $required');
      }
    }
  }
}

Future<void> verifyLinux(Directory bundle) async {
  final files = bundleFiles(bundle).toList();
  _rejectApplicationBridge(files);
  for (final name in [
    linuxExecutable,
    'libflutter_linux_gtk.so',
    'libinterop_scrcpy_bridge.so',
    'libmedia_codec_plugin.so',
    'adb',
  ]) {
    final matches = files
        .where((file) => p.basename(file.path) == name)
        .toList();
    if (matches.length != 1) throw StateError('Linux bundle lacks one $name');
    final bytes = matches.single.openSync();
    try {
      final header = bytes.readSync(20);
      if (header.length != 20 ||
          header[0] != 0x7f ||
          header[1] != 0x45 ||
          header[2] != 0x4c ||
          header[3] != 0x46 ||
          header[4] != 2 ||
          ByteData.sublistView(header).getUint16(18, Endian.little) != 62) {
        throw StateError('Linux bundle has a non-x64 ELF: $name');
      }
    } finally {
      bytes.closeSync();
    }
  }
  final desktopEntry = File(
    p.join(bundle.path, 'share', 'applications', '$linuxApplicationId.desktop'),
  );
  final icon = File(
    p.join(
      bundle.path,
      'share',
      'icons',
      'hicolor',
      'scalable',
      'apps',
      '$linuxApplicationId.svg',
    ),
  );
  if (!desktopEntry.existsSync() || !icon.existsSync()) {
    throw StateError('Linux bundle lacks its desktop entry or app icon');
  }
  final desktopFields = desktopEntry.readAsLinesSync();
  if (!desktopFields.contains('Exec=$linuxExecutable') ||
      !desktopFields.contains('Icon=$linuxApplicationId')) {
    throw StateError(
      'Linux desktop entry does not match its executable and icon',
    );
  }
  final entries = [
    ...files.where(
      (file) => const [linuxExecutable, 'adb'].contains(p.basename(file.path)),
    ),
    ...files.where((file) => p.basename(file.path).contains('.so')),
  ];
  final resolved = <String>{};
  for (final file in entries) {
    final canonical = file.resolveSymbolicLinksSync();
    if (resolved.contains(canonical)) continue;
    final linkage = await runTool(
      ['ldd', file.path],
      quiet: true,
      environment: const {'LD_LIBRARY_PATH': ''},
    );
    if ('${linkage.stdout}'.contains('not found')) {
      throw StateError('Unresolved Linux dependency: ${file.path}');
    }
    // ldd 在真实入口的 RUNPATH 下核验完整依赖闭包；已在此解析的库不必能单独执行，例如插件同时加载 libva-drm 和 libva。
    //
    //
    resolved.add(canonical);
    for (final line in const LineSplitter().convert('${linkage.stdout}')) {
      final arrow = line.indexOf('=> ');
      final address = line.lastIndexOf(' (');
      if (arrow < 0 || address <= arrow + 3) continue;
      final dependency = File(line.substring(arrow + 3, address).trim());
      if (dependency.existsSync()) {
        resolved.add(dependency.resolveSymbolicLinksSync());
      }
    }
  }
  verifyMedia(bundle);
}

void installMediaNotices(Directory bundle, String platform) {
  if (platform == 'macos' || platform == 'ios') {
    // runner 最终资源阶段采用实际 CocoaPods SDK 与架构前缀，并在 macOS 为嵌套的官方 adb 签名。
    //
    return;
  }
  final prefix = Directory(
    p.join(root.path, '.dart_tool/media_codec/ffmpeg/$platform-x64'),
  );
  final source = Directory(p.join(prefix.path, 'share/media_codec'));
  if (!source.existsSync()) {
    throw StateError('Missing FFmpeg provenance: ${source.path}');
  }
  copyDirectory(source, Directory(p.join(bundle.path, 'licenses/media_codec')));
  File(p.join(prefix.path, 'media-codec-build.json')).copySync(
    p.join(bundle.path, 'licenses/media_codec/media-codec-build.json'),
  );
}

Future<void> verifyApple(Directory bundle, String platform) async {
  final contents = platform == 'macos'
      ? Directory(p.join(bundle.path, 'Contents'))
      : bundle;
  final result = await runTool([
    'plutil',
    '-convert',
    'json',
    '-o',
    '-',
    p.join(contents.path, 'Info.plist'),
  ], quiet: true);
  final info = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  final name = info['CFBundleExecutable'] as String;
  if (info['CFBundleIdentifier'] != 'dev.scrcpyconnect.scrcpyConnect' ||
      info['CFBundleDisplayName'] != '邻接') {
    throw StateError('Unexpected $platform application identity');
  }
  if (platform == 'macos') {
    final icon = File(p.join(contents.path, 'Resources', 'AppIcon.icns'));
    if (!icon.existsSync()) throw StateError('macOS bundle lacks AppIcon.icns');
  } else {
    for (final key in ['CFBundleIcons', 'CFBundleIcons~ipad']) {
      if (info[key]?['CFBundlePrimaryIcon']?['CFBundleIconName'] != 'AppIcon') {
        throw StateError('iOS bundle lacks AppIcon for $key');
      }
    }
  }
  final binary = platform == 'macos'
      ? p.join(contents.path, 'MacOS', name)
      : p.join(contents.path, name);
  await runTool(['xcrun', 'lipo', '-verify_arch', 'arm64', binary]);
  final files = bundleFiles(contents).toList();
  _rejectApplicationBridge(files);
  if (!files.any(
    (file) =>
        p.basename(file.path) ==
        (platform == 'macos' ? 'FlutterMacOS' : 'Flutter'),
  )) {
    throw StateError('Apple bundle lacks its Flutter engine');
  }
  for (final name in ['interop_scrcpy_bridge']) {
    final rust = files
        .where(
          (file) =>
              p.basename(file.path).contains(name) &&
              !{'.plist', '.json', '.h'}.contains(p.extension(file.path)),
        )
        .toList();
    if (rust.isEmpty) {
      throw StateError('Apple bundle lacks its Rust capability library: $name');
    }
    for (final library in rust) {
      await runTool(['xcrun', 'lipo', '-verify_arch', 'arm64', library.path]);
    }
  }
  if (platform == 'macos') {
    await _rejectDuplicateObjectiveCClasses(contents, File(binary));
  }
  verifyMedia(bundle);
}

/// 同一插件被 CocoaPods 和 SwiftPM 同时链接时，构建成功但运行时存在类冲突。
Future<void> _rejectDuplicateObjectiveCClasses(
  Directory contents,
  File executable,
) async {
  final binaries = [executable];
  for (final framework in Directory(
    p.join(contents.path, 'Frameworks'),
  ).listSync().whereType<Directory>()) {
    if (!framework.path.endsWith('.framework')) continue;
    final binary = File(
      p.join(framework.path, p.basenameWithoutExtension(framework.path)),
    );
    if (binary.existsSync()) binaries.add(binary);
  }
  final architectures = await runTool([
    'xcrun',
    'lipo',
    '-archs',
    executable.path,
  ], quiet: true);
  for (final arch in '${architectures.stdout}'.trim().split(RegExp(r'\s+'))) {
    final owners = <String, String>{};
    for (final binary in binaries) {
      final result = await runTool([
        'xcrun',
        'nm',
        '-arch',
        arch,
        '-gU',
        binary.path,
      ], quiet: true);
      for (final line in const LineSplitter().convert('${result.stdout}')) {
        final symbol = line.trim().split(RegExp(r'\s+')).last;
        if (!symbol.startsWith('_OBJC_CLASS_\$_')) continue;
        final previous = owners[symbol];
        if (previous != null) {
          throw StateError(
            'Duplicate Objective-C class $symbol ($arch): '
            '$previous and ${binary.path}',
          );
        }
        owners[symbol] = binary.path;
      }
    }
  }
}

Future<void> archiveBundle(
  Directory bundle,
  String platform,
  Directory artifacts,
) async {
  artifacts.createSync(recursive: true);
  if (platform == 'windows') {
    final archive = Archive();
    for (final entity in bundle.listSync(recursive: true)) {
      final name = p
          .relative(entity.path, from: bundle.path)
          .split(p.separator)
          .join('/');
      // A previous incremental build can leave the former launcher beside the new one.
      if (name == 'scrcpy_connect.exe') continue;
      if (entity is File) {
        final bytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      } else if (entity is Directory) {
        archive.addFile(ArchiveFile('$name/', 0, <int>[])..isFile = false);
      }
    }
    File(p.join(artifacts.path, 'windows-release.zip'))
        .writeAsBytesSync(ZipEncoder().encode(archive));
  } else {
    // 原生 tar 保留执行权限与 framework 符号链接；不遍历 framework 链接，也不用普通文件字节重建归档。
    //
    await streamTool([
      'tar',
      '-czf',
      p.join(artifacts.absolute.path, '$platform-release.tar.gz'),
      '-C',
      bundle.parent.path,
      p.basename(bundle.path),
    ]);
  }
}

Future<void> main(List<String> arguments) async {
  try {
    final parser = ArgParser()
      ..addFlag('verify-only', negatable: false)
      ..addFlag('help', abbr: 'h', negatable: false);
    final args = parser.parse(arguments);
    if (args['help'] as bool) {
      stdout.writeln(
        'Usage: dart scripts/build_host.dart <windows|linux|ios|macos>\n${parser.usage}',
      );
      return;
    }
    if (args.rest.length != 1 ||
        !['windows', 'linux', 'ios', 'macos'].contains(args.rest.single)) {
      throw ArgumentError(
        'Usage: dart scripts/build_host.dart <windows|linux|ios|macos> [--verify-only]',
      );
    }
    final platform = args.rest.single;
    final application = applicationRoot(root);
    if (!(args['verify-only'] as bool)) {
      await streamTool([
        executable('flutter') ?? 'flutter',
        'build',
        platform,
        '--release',
        '--no-pub',
        if (platform == 'ios') '--no-codesign',
      ], cwd: application);
    }
    late Directory bundle;
    if (platform == 'windows') {
      bundle = Directory(
        p.join(application.path, 'build/windows/x64/runner/Release'),
      );
    } else if (platform == 'linux') {
      bundle = Directory(
        p.join(application.path, 'build/linux/x64/release/bundle'),
      );
    } else {
      bundle = Directory(
        p.join(
          application.path,
          platform == 'ios'
              ? 'build/ios/iphoneos/Runner.app'
              : 'build/macos/Build/Products/Release/$macApplication',
        ),
      );
      if (!bundle.existsSync()) {
        throw StateError('Missing final application at ${bundle.path}');
      }
    }
    if (!(args['verify-only'] as bool)) installMediaNotices(bundle, platform);
    switch (platform) {
      case 'windows':
        verifyWindows(bundle);
      case 'linux':
        await verifyLinux(bundle);
      default:
        await verifyApple(bundle, platform);
    }
    await archiveBundle(
      bundle,
      platform,
      Directory(p.join(root.path, 'build/verified')),
    );
    stdout.writeln(
      'PASS: final $platform application, Flutter engine, Rust and trimmed media codec',
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
