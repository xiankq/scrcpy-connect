/// 为桌面应用准备固定版本的 ADB 分发文件。
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
      allowed: ['linux', 'linux-arm64', 'windows', 'macos'],
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
    final lockContents = await lockFile.readAsString();
    final lock = jsonDecode(lockContents) as Map<String, dynamic>;
    final platform = args['platform'] as String;
    final config = (lock['platforms'] as Map)[platform] as Map<String, dynamic>;
    final cache = Directory(p.join(workspace.path, '.dart_tool/adb'));
    final output = Directory(
      args['output'] as String? ?? p.join(cache.path, platform),
    ).absolute;
    final source = await Directory(p.join(cache.path, 'source'))
        .create(recursive: true);
    final hashes = config['files'] as Map<String, dynamic>?;
    if (hashes != null && await output.exists()) {
      final entries = await output.list().toList();
      final receipt = File(p.join(output.path, p.basename(lockFile.path)));
      if (entries.length == hashes.length + 1 &&
          await receipt.exists() &&
          await receipt.readAsString() == lockContents &&
          (await Future.wait([
            for (final entry in hashes.entries)
              hasHash(
                File(p.join(output.path, entry.key)),
                entry.value as String,
              ),
          ])).every((matches) => matches)) {
        stdout.writeln(output.path);
        return;
      }
    }

    final staging = await Directory('${output.path}.staging.$pid')
        .create(recursive: true);
    try {
      if (platform == 'linux-arm64') {
        await prepareLinuxArm64(client, config, source, staging);
      } else {
        final suffix = platform == 'macos' ? 'darwin' : platform;
        final archive = await download(
          client,
          Uri.parse(config['url'] as String),
          File(
            p.join(
              source.path,
              'platform-tools_r${lock['version']}-$suffix-${config['sha256']}.zip',
            ),
          ),
          config['sha256'] as String,
          bytes: config['archiveBytes'] as int,
        );
        final zip = ZipDecoder().decodeBytes(
          await archive.readAsBytes(),
          verify: true,
        );
        // 只交付 ADB、必需的 DLL 和声明。
        for (final entry in hashes!.entries) {
          final item = zip.findFile('platform-tools/${entry.key}');
          if (item == null || !item.isFile || item.size > 64 * 1024 * 1024) {
            throw StateError('Platform-Tools archive lacks ${entry.key}');
          }
          final bytes = item.content;
          if (sha256.convert(bytes).toString() != entry.value) {
            throw StateError(
              'Platform-Tools file SHA-256 mismatch: ${entry.key}',
            );
          }
          await File(p.join(staging.path, entry.key)).writeAsBytes(bytes);
        }
        final properties = await File(p.join(staging.path, 'source.properties'))
            .readAsLines();
        if (!properties.contains('Pkg.Revision=${lock['version']}')) {
          throw StateError('Platform-Tools revision differs from lock');
        }
      }
      await lockFile.copy(p.join(staging.path, p.basename(lockFile.path)));
      if (!Platform.isWindows && platform != 'windows') {
        await run('chmod', ['755', p.join(staging.path, 'adb')]);
      }
      if (await output.exists()) await output.delete(recursive: true);
      await staging.rename(output.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
    stdout.writeln(output.path);
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}

Future<bool> hasHash(File file, String expected) async =>
    await file.exists() &&
    (await sha256.bind(file.openRead()).first).toString() == expected;

Future<File> download(
  HttpClient client,
  Uri url,
  File archive,
  String hash, {
  int? bytes,
}) async {
  if (await archive.exists()) {
    if (await hasHash(archive, hash)) return archive;
    throw StateError('Cached ADB input SHA-256 mismatch: ${archive.path}');
  }
  final pending = File('${archive.path}.download.$pid');
  try {
    final request = await client.getUrl(url);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('ADB download HTTP ${response.statusCode}', uri: url);
    }
    var received = 0;
    final sink = pending.openWrite();
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (bytes != null && received > bytes) {
          throw StateError('ADB archive exceeds pinned length');
        }
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (bytes != null && received != bytes) {
      throw StateError('Truncated ADB archive');
    }
    if (!await hasHash(pending, hash)) {
      throw StateError('ADB input SHA-256 mismatch: $url');
    }
    return await pending.rename(archive.path);
  } finally {
    if (await pending.exists()) await pending.delete();
  }
}

Future<void> prepareLinuxArm64(
  HttpClient client,
  Map<String, dynamic> config,
  Directory source,
  Directory staging,
) async {
  final unpacked = Directory(p.join(staging.path, 'unpacked'));
  for (final entry in (config['packages'] as Map<String, dynamic>).entries) {
    final url = Uri.parse(config['baseUrl'] as String).resolve(entry.key);
    final archive = await download(
      client,
      url,
      File(p.join(source.path, p.basename(entry.key))),
      entry.value as String,
    );
    await run('dpkg-deb', ['--extract', archive.path, unpacked.path]);
  }
  final adb = p.join(staging.path, 'adb');
  await File(p.join(unpacked.path, 'usr/lib/android-sdk/platform-tools/adb'))
      .copy(adb);
  final privateLibs = await Directory(p.join(staging.path, 'lib')).create();
  for (final library in (config['libraries'] as List).cast<String>()) {
    await File(p.join(unpacked.path, 'usr/lib/aarch64-linux-gnu', library))
        .copy(p.join(privateLibs.path, p.basename(library)));
  }
  // Ubuntu 的 ADB 安装到系统 SDK 目录。改为随应用迁移的私有依赖路径。
  await run('patchelf', ['--force-rpath', '--set-rpath', r'$ORIGIN/lib', adb]);
  final docs = Directory(p.join(unpacked.path, 'usr/share/doc'));
  await File(p.join(docs.path, 'adb/copyright'))
      .copy(p.join(staging.path, 'NOTICE.txt'));
  final notices = await Directory(p.join(staging.path, 'licenses')).create();
  for (final path in [
    'android-libboringssl',
    'libbrotli1',
    'liblz4-1',
    'libprotobuf32t64',
    'libzstd1',
  ]) {
    await File(p.join(docs.path, path, 'copyright'))
        .copy(p.join(notices.path, '$path.txt'));
  }
  await unpacked.delete(recursive: true);
}

Future<void> run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr as String,
      result.exitCode,
    );
  }
}
