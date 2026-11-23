/// 为桌面应用准备固定版本的官方 ADB 分发文件。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'platform',
      allowed: ['linux', 'windows', 'macos'],
      mandatory: true,
    )
    ..addOption('output');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final args = parser.parse(arguments);
    final package = File.fromUri(Platform.script).parent.parent;
    final workspace = package.parent.parent;
    final lockFile = File(
      p.join(package.path, 'third_party/platform-tools.lock.json'),
    );
    final lock =
        jsonDecode(await lockFile.readAsString()) as Map<String, dynamic>;
    final platform = args['platform'] as String;
    final config = (lock['platforms'] as Map)[platform] as Map<String, dynamic>;
    final hashes = Map<String, String>.from(config['files'] as Map);
    final cache = Directory(p.join(workspace.path, '.dart_tool/adb'));
    final output = Directory(
      args['output'] as String? ?? p.join(cache.path, platform),
    );
    final expectedFiles = {...hashes.keys, 'platform-tools.lock.json'};

    Future<bool> valid() async {
      if (!await output.exists()) return false;
      final entries = await output.list().toList();
      if (entries.length != expectedFiles.length ||
          entries.any(
            (entry) => !expectedFiles.contains(p.basename(entry.path)),
          )) {
        return false;
      }
      for (final entry in hashes.entries) {
        final file = File(p.join(output.path, entry.key));
        if (!await file.exists() ||
            (await sha256.bind(file.openRead()).first).toString() !=
                entry.value) {
          return false;
        }
      }
      return await File(p.join(output.path, 'platform-tools.lock.json'))
              .readAsString() ==
          await lockFile.readAsString();
    }

    if (await valid()) {
      stdout.writeln(output.absolute.path);
      return;
    }
    final source = Directory(p.join(cache.path, 'source'));
    await source.create(recursive: true);
    final suffix = platform == 'macos' ? 'darwin' : platform;
    final archive = File(
      p.join(
        source.path,
        'platform-tools_r${lock['version']}-$suffix-${config['sha256']}.zip',
      ),
    );
    if (!await archive.exists()) {
      final pending = File('${archive.path}.download.$pid');
      try {
        final request = await client.getUrl(Uri.parse(config['url'] as String));
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('ADB download HTTP ${response.statusCode}');
        }
        var received = 0;
        final sink = pending.openWrite();
        try {
          await for (final chunk in response.timeout(
            const Duration(seconds: 30),
          )) {
            received += chunk.length;
            if (received > (config['archiveBytes'] as int)) {
              throw StateError('ADB archive exceeds pinned length');
            }
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (received != config['archiveBytes']) {
          throw StateError('Truncated ADB archive');
        }
        if ((await sha256.bind(pending.openRead()).first).toString() !=
            config['sha256']) {
          throw StateError('Official ADB archive SHA-256 mismatch');
        }
        await pending.rename(archive.path);
      } finally {
        if (await pending.exists()) await pending.delete();
      }
    }
    if ((await sha256.bind(archive.openRead()).first).toString() !=
        config['sha256']) {
      throw StateError('Cached official ADB archive SHA-256 mismatch');
    }
    final zip = ZipDecoder().decodeBytes(
      await archive.readAsBytes(),
      verify: true,
    );
    final staging = Directory('${output.path}.staging.$pid');
    await staging.create(recursive: true);
    try {
      // 仅提取锁定的文件名；fastboot、文件系统工具和 sqlite 不属于 ADB 依赖，不随应用打包。
      for (final entry in hashes.entries) {
        if (p.basename(entry.key) != entry.key) {
          throw StateError('Invalid lock file name');
        }
        final item = zip.findFile('platform-tools/${entry.key}');
        if (item == null || !item.isFile || item.size > 64 * 1024 * 1024) {
          throw StateError('Official ADB archive lacks ${entry.key}');
        }
        final bytes = item.content;
        if (sha256.convert(bytes).toString() != entry.value) {
          throw StateError('Official ADB file SHA-256 mismatch: ${entry.key}');
        }
        await File(p.join(staging.path, entry.key)).writeAsBytes(bytes);
      }
      final properties = await File(p.join(staging.path, 'source.properties'))
          .readAsString();
      if (!properties.split('\n').contains('Pkg.Revision=${lock['version']}')) {
        throw StateError('Official ADB revision differs from lock');
      }
      await lockFile.copy(p.join(staging.path, 'platform-tools.lock.json'));
      if (!Platform.isWindows && platform != 'windows') {
        final result = await Process.run('chmod', [
          '755',
          p.join(staging.path, 'adb'),
        ]);
        if (result.exitCode != 0) {
          throw StateError('Cannot mark ADB executable');
        }
      }
      if (await output.exists()) await output.delete(recursive: true);
      await staging.rename(output.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
    stdout.writeln(output.absolute.path);
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}
