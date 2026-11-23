/// 构建并核验最终宿主应用包中的原生库。
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'src/packaging.dart';
import 'src/repository_tooling.dart';

final root = repositoryRoot();
const macApplication = 'Interconnect.app';
const windowsExecutable = 'Interconnect.exe';
const linuxExecutable = 'interconnect';
const linuxApplicationId = 'dev.scrcpyconnect.scrcpy_connect';

int peMachine(File path) {
  final file = path.openSync();
  try {
    final dosHeader = file.readSync(64);
    if (dosHeader.length < 64 || dosHeader[0] != 0x4d || dosHeader[1] != 0x5a) {
      throw FormatException('Invalid PE file: ${path.path}');
    }
    final offset = ByteData.sublistView(dosHeader)
        .getUint32(0x3c, Endian.little);
    file.setPositionSync(offset);
    final header = file.readSync(6);
    if (header.length < 6 ||
        header[0] != 0x50 ||
        header[1] != 0x45 ||
        header[2] != 0 ||
        header[3] != 0) {
      throw FormatException('Invalid PE signature: ${path.path}');
    }
    return ByteData.sublistView(header).getUint16(4, Endian.little);
  } finally {
    file.closeSync();
  }
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

void verifyWindows(Directory bundle, String arch) {
  final files = bundleFiles(bundle).toList();
  _rejectApplicationBridge(files);
  const adbFiles = {'adb.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll'};
  int? adbMachine;
  for (final name in [
    windowsExecutable,
    'flutter_windows.dll',
    'msvcp140.dll',
    'vcruntime140.dll',
    if (arch == 'x64') 'vcruntime140_1.dll',
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
      throw StateError('Final Windows bundle lacks one $name');
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
    } else if (machine != (arch == 'arm64' ? 0xaa64 : 0x8664)) {
      throw StateError('Unexpected PE architecture for $name in $arch bundle');
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

Future<void> verifyLinux(Directory bundle, String arch) async {
  final files = bundleFiles(bundle).toList();
  _rejectApplicationBridge(files);
  for (final name in [
    linuxExecutable,
    'libflutter_linux_gtk.so',
    'libinterop_scrcpy_bridge.so',
    'libmedia_codec_plugin.so',
    if (arch == 'x64') 'adb',
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
          ByteData.sublistView(header).getUint16(18, Endian.little) !=
              (arch == 'arm64' ? 183 : 62)) {
        throw StateError('Linux bundle has an unexpected ELF for $arch: $name');
      }
    } finally {
      bytes.closeSync();
    }
  }
  if (arch == 'arm64') await runTool(['/usr/bin/adb', 'version'], quiet: true);
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

void installMediaNotices(Directory bundle, String platform, String arch) {
  if (platform == 'macos' || platform == 'ios') {
    // runner 最终资源阶段采用实际 CocoaPods SDK 与架构前缀，并在 macOS 为嵌套的官方 adb 签名。
    //
    return;
  }
  final prefix = Directory(
    p.join(root.path, '.dart_tool/media_codec/ffmpeg/$platform-$arch'),
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

Future<void> verifyApple(Directory bundle, String platform, String arch) async {
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
  final slices = arch == 'universal'
      ? ['arm64', 'x86_64']
      : [arch == 'x64' ? 'x86_64' : arch];
  final actual = await runTool([
    'xcrun',
    'lipo',
    '-archs',
    binary,
  ], quiet: true);
  final actualSlices = (actual.stdout as String).trim().split(RegExp(r'\s+'));
  if (actualSlices.length != slices.length ||
      !slices.every(actualSlices.contains)) {
    throw StateError(
      'Expected $arch for $binary, found ${actualSlices.join(", ")}',
    );
  }
  final files = bundleFiles(contents).toList();
  _rejectApplicationBridge(files);
  final engine = files
      .where(
        (file) =>
            p.basename(file.path) ==
            (platform == 'macos' ? 'FlutterMacOS' : 'Flutter'),
      )
      .firstOrNull;
  if (engine == null) {
    throw StateError('Apple bundle lacks its Flutter engine');
  }
  await runTool(['xcrun', 'lipo', '-verify_arch', ...slices, engine.path]);
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
      await runTool(['xcrun', 'lipo', '-verify_arch', ...slices, library.path]);
    }
  }
  if (platform == 'macos') {
    await runTool([
      'xcrun',
      'lipo',
      '-verify_arch',
      ...slices,
      p.join(contents.path, 'Resources', 'adb', 'adb'),
    ]);
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
  String target,
  Directory artifacts,
) async {
  artifacts.createSync(recursive: true);
  if (target.startsWith('windows-')) {
    final formerLauncher = p.join(bundle.path, 'scrcpy_connect.exe');
    await ZipFileEncoder().zipDirectory(
      bundle,
      filename: p.join(artifacts.path, '$target-release.zip'),
      // A previous incremental build can leave the former launcher behind.
      filter: (entry, _) => entry.path == formerLauncher
          ? ZipFileOperation.skip
          : ZipFileOperation.include,
    );
  } else {
    // 原生 tar 保留执行权限与 framework 符号链接；不遍历 framework 链接，也不用普通文件字节重建归档。
    //
    await streamTool([
      'tar',
      '-czf',
      p.join(artifacts.absolute.path, '$target-release.tar.gz'),
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
      ..addFlag('installers', negatable: false)
      ..addOption('arch', allowed: ['x64', 'arm64', 'universal'])
      ..addOption(
        'update-feed',
        help: 'Public HTTPS update feed for this package.',
      )
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
    final feed = updateFeedDefine(args.option('update-feed'));
    final nativeArch =
        const {
          Abi.linuxArm64,
          Abi.windowsArm64,
          Abi.macosArm64,
        }.contains(Abi.current())
        ? 'arm64'
        : 'x64';
    final arch =
        args.option('arch') ??
        switch (platform) {
          'macos' => 'universal',
          'ios' => 'arm64',
          _ => nativeArch,
        };
    if ((platform == 'ios' && arch != 'arm64') ||
        (const {'linux', 'windows'}.contains(platform) && arch != nativeArch)) {
      throw ArgumentError(
        '$platform $arch requires its matching native build host.',
      );
    }
    final verifyOnly = args.flag('verify-only');
    if (!verifyOnly) {
      final macConfig = platform == 'macos'
          ? Directory.systemTemp.createTempSync('interconnect-arch-')
          : null;
      try {
        final config = macConfig == null
            ? null
            : File(p.join(macConfig.path, 'Release.xcconfig'));
        if (config != null) {
          final architectures = switch (arch) {
            'universal' => 'arm64 x86_64',
            'x64' => 'x86_64',
            _ => 'arm64',
          };
          config.writeAsStringSync(
            'ARCHS = $architectures\nONLY_ACTIVE_ARCH = NO\n',
          );
        }
        await streamTool(
          [
            executable('flutter') ?? 'flutter',
            'build',
            platform,
            '--release',
            '--no-pub',
            ?feed,
            if (platform == 'ios') '--no-codesign',
          ],
          cwd: application,
          environment: {if (config != null) 'XCODE_XCCONFIG_FILE': config.path},
        );
      } finally {
        macConfig?.deleteSync(recursive: true);
      }
    }
    final bundle = Directory(
      p.join(application.path, switch (platform) {
        'windows' => 'build/windows/$arch/runner/Release',
        'linux' => 'build/linux/$arch/release/bundle',
        'ios' => 'build/ios/iphoneos/Runner.app',
        _ => 'build/macos/Build/Products/Release/$macApplication',
      }),
    );
    if (!bundle.existsSync()) {
      throw StateError('Missing final application at ${bundle.path}');
    }
    if (!verifyOnly) installMediaNotices(bundle, platform, arch);
    switch (platform) {
      case 'windows':
        verifyWindows(bundle, arch);
      case 'linux':
        await verifyLinux(bundle, arch);
      default:
        await verifyApple(bundle, platform, arch);
    }
    final artifacts = Directory(p.join(root.path, 'build/verified'));
    final target = '$platform-$arch';
    if (platform != 'macos' || !args.flag('installers')) {
      await archiveBundle(bundle, target, artifacts);
    }
    if (args.flag('installers')) {
      final pubspec = loadYaml(
        File(p.join(application.path, 'pubspec.yaml')).readAsStringSync(),
      );
      final version = (pubspec['version'] as String).split('+').first;
      final prefix = p.join(artifacts.absolute.path, '$target-release');
      switch (platform) {
        case 'linux':
          await streamTool([
            'python3',
            p.join(root.path, 'scripts/package_linux.py'),
            bundle.absolute.path,
            prefix,
            arch,
            version,
          ]);
        case 'windows':
          final iscc = executable('ISCC');
          if (iscc == null) {
            throw StateError('Install Inno Setup and add ISCC.exe to PATH.');
          }
          await streamTool([
            iscc,
            '/O${artifacts.absolute.path}',
            '/F$target-release-setup',
            '/DBundle=${bundle.absolute.path}',
            '/DAppVersion=$version',
            '/DTargetArch=${arch == 'x64' ? 'x64os' : 'arm64'}',
            p.join(root.path, 'scripts/installer_windows.iss'),
          ]);
        case 'macos':
          artifacts.createSync(recursive: true);
          await streamTool([
            'bash',
            p.join(root.path, 'scripts/package_macos.sh'),
            bundle.absolute.path,
            '$prefix.dmg',
          ]);
        default:
          throw ArgumentError('Use Apple distribution tooling for iOS.');
      }
    }
    stdout.writeln(
      'PASS: final $platform application, Flutter engine, Rust and trimmed media codec',
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
