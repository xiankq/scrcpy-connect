/// Check release metadata and assemble the verified packages for GitHub.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'src/packaging.dart';
import 'src/repository_tooling.dart';

Future<void> main(List<String> arguments) async {
  final log = PackagingLog('Release');
  final parser = ArgParser()
    ..addOption('tag', mandatory: true)
    ..addOption('repository')
    ..addOption('packages')
    ..addFlag('macos', negatable: false)
    ..addOption('previous-feed')
    ..addOption('output')
    ..addOption('notes');
  try {
    log.begin('validate tag and release notes');
    final args = parser.parse(arguments);
    final root = repositoryRoot().path;
    final pubspec = loadYaml(
      File(p.join(root, 'app/pubspec.yaml')).readAsStringSync(),
    ) as YamlMap;
    final tag = args.option('tag')!;
    final version = RegExp(r'^(\d+\.\d+\.\d+)\+([1-9]\d*)$')
        .firstMatch(pubspec['version'] as String);
    final preview = RegExp(r'-preview\.[1-9]\d*$').hasMatch(tag);
    if (version == null ||
        tag.replaceFirst(RegExp(r'-preview\.[1-9]\d*$'), '') !=
            'v${version[1]}') {
      throw FormatException('Tag $tag must match app/pubspec.yaml version.');
    }
    final license = File(p.join(root, 'LICENSE'));
    if (!license.existsSync() || license.readAsStringSync().trim().isEmpty) {
      throw StateError('Add the approved project LICENSE before releasing.');
    }
    final changelog = File(p.join(root, 'CHANGELOG.md')).readAsStringSync();
    final heading = RegExp(
      r'^## ' + RegExp.escape(version[1]!) + r'[ \t]*$',
      multiLine: true,
    );
    final section = heading.firstMatch(changelog);
    if (section == null) {
      throw StateError('Add a ## ${version[1]} section to CHANGELOG.md.');
    }
    final body = changelog.substring(section.end).trim();
    final nextSection = RegExp(r'^## ', multiLine: true).firstMatch(body);
    final notes = body.substring(0, nextSection?.start).trim();
    final summary = [
      for (final line in LineSplitter.split(notes))
        if (line.startsWith('- ') && line.length > 2) line.substring(2),
    ];
    if (summary.isEmpty) throw StateError('Add at least one release note.');
    final notePath = args.option('notes');
    if (notePath != null) File(notePath).writeAsStringSync('$notes\n');
    final output = args.option('output');
    if (output == null) {
      log.done();
      return;
    }

    final repository = args.option('repository');
    final packages = args.option('packages');
    if (repository == null || packages == null) {
      throw ArgumentError('Assembly requires --repository and --packages.');
    }
    final previousPath = args.option('previous-feed');
    if (preview && previousPath != null) {
      throw ArgumentError('Previews do not take a stable update feed.');
    }
    final previous = previousPath == null
        ? <Map<String, Object?>>[]
        : (jsonDecode(File(previousPath).readAsStringSync()) as List)
              .cast<Map<String, Object?>>();
    final build = int.parse(version[2]!);
    final versionParts = version[1]!.split('.').map(int.parse).toList();
    for (final record in previous) {
      final old = (record['version'] as String)
          .split('.')
          .map(int.parse)
          .toList();
      var order = 0;
      for (var index = 0; index < versionParts.length; index++) {
        order = versionParts[index].compareTo(old[index]);
        if (order != 0) break;
      }
      if (order <= 0 || build <= (record['build'] as int)) {
        throw StateError(
          'Increase both version and build after each public release.',
        );
      }
    }

    final artifacts = {
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal'])
        'package-android/android-$abi-release.apk':
            'interconnect-$tag-android-$abi.apk',
      for (final arch in ['x64', 'arm64']) ...{
        for (final extension in ['tar.gz', 'deb', 'rpm', 'AppImage'])
          'package-linux-$arch/linux-$arch-release.$extension':
              'interconnect-$tag-linux-$arch.$extension',
        'package-windows-$arch/windows-$arch-release.zip':
            'interconnect-$tag-windows-$arch-portable.zip',
        'package-windows-$arch/windows-$arch-release-setup.exe':
            'interconnect-$tag-windows-$arch-setup.exe',
        if (preview || args.flag('macos'))
          'package-macos-$arch/macos-$arch-release.dmg':
              'interconnect-$tag-macos-$arch.dmg',
      },
      if (preview) ...{
        'package-ios-simulator-arm64/ios-simulator-arm64-debug.tar.gz':
            'interconnect-$tag-ios-simulator-arm64.tar.gz',
        'package-ios-arm64/ios-arm64-release.tar.gz':
            'interconnect-$tag-iphoneos-arm64-unsigned.tar.gz',
      },
      'release-media-source.tar.gz': 'interconnect-$tag-media-source.tar.gz',
    };
    log.begin('check artifact set');
    final missing = artifacts.keys.where((name) {
      final file = File(p.join(packages, name));
      return !file.existsSync() || file.lengthSync() == 0;
    }).toList();
    if (missing.isNotEmpty) {
      throw StateError(
        'Release package set is incomplete:\n${missing.join("\n")}',
      );
    }
    log.begin('stage artifacts and checksums');
    Directory(output).createSync(recursive: true);
    final checksums = <String>[];
    for (final artifact in artifacts.entries) {
      final digest = await copyWithDigest(
        File(p.join(packages, artifact.key)),
        File(p.join(output, artifact.value)),
      );
      checksums.add('$digest  ${artifact.value}');
    }
    if (notePath != null) {
      final download = 'https://github.com/$repository/releases/download/$tag';
      final rows = [
        '| 系统 | 架构 | 下载 |',
        '| --- | --- | --- |',
        for (final (platform, title, arches) in [
          (
            'android',
            'Android',
            ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal'],
          ),
          ('linux', 'Linux', ['x64', 'arm64']),
          ('windows', 'Windows', ['x64', 'arm64']),
          if (preview || args.flag('macos'))
            ('macos', 'macOS', ['arm64', 'x64']),
        ])
          for (final arch in arches)
            '| $title | $arch | ${artifacts.values.where((name) => name.startsWith('interconnect-$tag-$platform-$arch.') || name.startsWith('interconnect-$tag-$platform-$arch-')).map((name) {
              final label = name.endsWith('-setup.exe')
                  ? '安装器'
                  : name.endsWith('-portable.zip')
                  ? '便携 ZIP'
                  : name.endsWith('.tar.gz')
                  ? 'tar.gz'
                  : name.split('.').last;
              return '[$label]($download/$name)';
            }).join(' · ')} |',
        if (preview) ...[
          '| iOS / iPadOS | 模拟器 · Apple 芯片 | [模拟器应用]($download/interconnect-$tag-ios-simulator-arm64.tar.gz) |',
          '| iOS / iPadOS | 真机 · arm64 | [未签名编译归档]($download/interconnect-$tag-iphoneos-arm64-unsigned.tar.gz) |',
        ],
      ];
      File(notePath).writeAsStringSync(
        '${preview ? '这是公开预览版。macOS 安装包未经 Apple 公证。'
                  'iPhoneOS 归档需要 Apple 签名才能安装到真机。\n\n' : ''}'
        '$notes\n\n## 下载\n\n${rows.join("\n")}\n\n'
        '[安装和校验说明](https://github.com/$repository/blob/$tag/docs/releasing.md) · '
        '[SHA256SUMS]($download/SHA256SUMS)\n\n'
        '邻接使用 LGPL 2.1 许可的 FFmpeg。'
        '[对应媒体源码]($download/interconnect-$tag-media-source.tar.gz) · '
        '[重新构建说明](https://github.com/$repository/blob/$tag/docs/releasing.md#替换-ffmpeg-后重新构建)\n',
      );
    }
    const feed = 'release-feed.json';
    if (!preview) {
      final content = utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert([
          {'version': version[1]!, 'build': build, 'publishedAt': DateTime.now().toUtc().toIso8601String(), 'notes': summary, 'url': 'https://github.com/$repository/releases/tag/$tag'},
          ...previous,
        ])}\n',
      );
      File(p.join(output, feed)).writeAsBytesSync(content);
      checksums.add('${sha256.convert(content)}  $feed');
    }
    File(p.join(output, 'SHA256SUMS'))
        .writeAsStringSync('${checksums.join('\n')}\n');
    log.done();
    stdout.writeln('Assembled release $tag in $output.');
  } on Object catch (error) {
    log.fail(error);
    exitCode = 1;
  }
}

Future<Digest> copyWithDigest(File source, File destination) async {
  final result = _DigestResult();
  final digest = sha256.startChunkedConversion(result);
  final file = await destination.open(mode: FileMode.write);
  try {
    await for (final chunk in source.openRead()) {
      await file.writeFrom(chunk);
      digest.add(chunk);
    }
  } finally {
    await file.close();
  }
  digest.close();
  return result.value;
}

class _DigestResult implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
