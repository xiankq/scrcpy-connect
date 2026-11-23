/// Check release metadata and assemble the verified packages for GitHub.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'src/repository_tooling.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('tag', mandatory: true)
    ..addOption('repository')
    ..addOption('packages')
    ..addFlag('macos', negatable: false)
    ..addOption('previous-feed')
    ..addOption('output')
    ..addOption('notes');
  try {
    final args = parser.parse(arguments);
    final root = repositoryRoot().path;
    final pubspec = loadYaml(
      File(p.join(root, 'app/pubspec.yaml')).readAsStringSync(),
    ) as YamlMap;
    final tag = args.option('tag')!;
    final version = RegExp(r'^(\d+\.\d+\.\d+)\+([1-9]\d*)$')
        .firstMatch(pubspec['version'] as String);
    if (version == null || tag != 'v${version[1]}') {
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
    if (output == null) return;

    final repository = args.option('repository');
    final packages = args.option('packages');
    if (repository == null || packages == null) {
      throw ArgumentError('Assembly requires --repository and --packages.');
    }
    final previousPath = args.option('previous-feed');
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
        if (args.flag('macos'))
          'package-macos-$arch/macos-$arch-release.dmg':
              'interconnect-$tag-macos-$arch.dmg',
      },
      'release-media-source.tar.gz': 'interconnect-$tag-media-source.tar.gz',
    };
    final missing = artifacts.keys.where((name) {
      final file = File(p.join(packages, name));
      return !file.existsSync() || file.lengthSync() == 0;
    }).toList();
    if (missing.isNotEmpty) {
      throw StateError(
        'Release package set is incomplete:\n${missing.join("\n")}',
      );
    }
    Directory(output).createSync(recursive: true);
    for (final artifact in artifacts.entries) {
      await File(p.join(packages, artifact.key))
          .copy(p.join(output, artifact.value));
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
          if (args.flag('macos')) ('macos', 'macOS', ['arm64', 'x64']),
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
      ];
      File(notePath).writeAsStringSync(
        '$notes\n\n## 下载\n\n${rows.join("\n")}\n\n'
        '[安装和校验说明](https://github.com/$repository/blob/$tag/docs/releasing.md) · '
        '[SHA256SUMS]($download/SHA256SUMS)\n',
      );
    }
    const feed = 'release-feed.json';
    File(p.join(output, feed)).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert([
        {'version': version[1]!, 'build': build, 'publishedAt': DateTime.now().toUtc().toIso8601String(), 'notes': summary, 'url': 'https://github.com/$repository/releases/tag/$tag'},
        ...previous,
      ])}\n',
    );
    final checksums = <String>[];
    for (final name in [...artifacts.values, feed]) {
      final digest = await sha256
          .bind(File(p.join(output, name)).openRead())
          .first;
      checksums.add('$digest  $name');
    }
    File(p.join(output, 'SHA256SUMS'))
        .writeAsStringSync('${checksums.join('\n')}\n');
    stdout.writeln('Assembled release $tag in $output.');
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
