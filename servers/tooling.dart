import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

Directory repositoryRoot([Uri? script]) {
  var directory = File.fromUri(script ?? Platform.script).absolute.parent;
  while (true) {
    if (File(p.join(directory.path, 'pubspec.yaml')).existsSync() &&
        File(p.join(directory.path, 'Cargo.toml')).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Cannot locate repository root from the script path');
    }
    directory = parent;
  }
}

String get userHome =>
    Platform.environment['HOME'] ??
    Platform.environment['USERPROFILE'] ??
    (throw StateError('HOME or USERPROFILE must be set'));

Directory androidSdk([String? override]) => Directory(
  override ??
      Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'] ??
      p.join(userHome, 'Android', 'Sdk'),
).absolute;

void require(bool condition, Object message) {
  if (!condition) throw StateError(message.toString());
}

String sha256(List<int> bytes) => crypto.sha256.convert(bytes).toString();
String digest(File file) => sha256(file.readAsBytesSync());

String relative(String path, String root) =>
    p.relative(path, from: root).split(p.separator).join('/');

List<File> files(Directory root, String suffix) =>
    root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith(suffix))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

Object? sortedJson(Object? value) {
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final key in value.keys.toList()..sort())
        key: sortedJson(value[key]),
    };
  }
  if (value is List<Object?>) return value.map(sortedJson).toList();
  return value;
}

bool sameJson(Object? first, Object? second) =>
    jsonEncode(sortedJson(first)) == jsonEncode(sortedJson(second));

Map<String, Object?> readJson(File file) =>
    (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
        .cast<String, Object?>();

void writeJson(File file, Object? value) => file.writeAsStringSync(
  '${const JsonEncoder.withIndent('  ').convert(sortedJson(value))}\n',
);

Future<T> withTemporary<T>(
  String prefix,
  Future<T> Function(Directory) action,
) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  try {
    return await action(directory);
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<ProcessResult> run(
  String executable,
  List<String> arguments, {
  Directory? cwd,
  Map<String, String>? environment,
  bool echo = false,
  bool check = true,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: cwd?.path,
    environment: environment,
    runInShell: Platform.isWindows && executable.endsWith('.bat'),
  );
  if (echo || (check && result.exitCode != 0)) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
  }
  if (check && result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Command failed',
      result.exitCode,
    );
  }
  return result;
}

String javaTool(String name) {
  final javaHome = Platform.environment['JAVA_HOME'];
  final suffix = Platform.isWindows ? '.exe' : '';
  return javaHome == null
      ? '$name$suffix'
      : p.join(javaHome, 'bin', '$name$suffix');
}

Future<Uint8List> download(String url, String expected) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 120);
  client.findProxy = (uri) {
    final proxy = Platform
        .environment[uri.scheme == 'https' ? 'https_proxy' : 'http_proxy'];
    if (proxy == null || proxy.isEmpty) return 'DIRECT';
    final address = Uri.parse(proxy);
    return 'PROXY ${address.host}:${address.port}';
  };
  try {
    final request = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 120));
    final response = await request.close().timeout(
      const Duration(seconds: 120),
    );
    require(
      response.statusCode == 200,
      'Download failed (${response.statusCode}): $url',
    );
    final bytes = await response
        .fold<BytesBuilder>(BytesBuilder(), (sink, data) => sink..add(data))
        .timeout(const Duration(seconds: 120));
    final result = bytes.takeBytes();
    require(sha256(result) == expected, 'Download SHA-256 mismatch: $url');
    return result;
  } finally {
    client.close(force: true);
  }
}

/// ZIP_STORED headers match the historical producer, including its platform
/// attributes. This keeps pinned JAR bytes independent of archive library defaults.
Uint8List storedZip(
  Map<String, List<int>> entries, {
  required DateTime date,
  int system = 3,
  int Function(String)? attributes,
}) {
  final output = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var offset = 0;
  final dosTime = (date.hour << 11) | (date.minute << 5) | (date.second ~/ 2);
  final dosDate = ((date.year - 1980) << 9) | (date.month << 5) | date.day;
  for (final entry in entries.entries) {
    final name = utf8.encode(entry.key);
    final content = entry.value;
    final crc = getCrc32(content);
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(10, dosTime, Endian.little)
      ..setUint16(12, dosDate, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, content.length, Endian.little)
      ..setUint32(22, content.length, Endian.little)
      ..setUint16(26, name.length, Endian.little);
    output
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(content);
    final header = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, (system << 8) | 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(12, dosTime, Endian.little)
      ..setUint16(14, dosDate, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, content.length, Endian.little)
      ..setUint32(24, content.length, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(
        38,
        attributes?.call(entry.key) ?? (0x81a4 << 16),
        Endian.little,
      )
      ..setUint32(42, offset, Endian.little);
    central
      ..add(header.buffer.asUint8List())
      ..add(name);
    offset += 30 + name.length + content.length;
  }
  final directory = central.takeBytes();
  output.add(directory);
  final footer = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, directory.length, Endian.little)
    ..setUint32(16, offset, Endian.little);
  output.add(footer.buffer.asUint8List());
  return output.takeBytes();
}

List<int> archiveBytes(ArchiveFile file) => file.content;

Future<void> extractArchive(Archive archive, Directory destination) async {
  for (final entry in archive) {
    final parts = p.posix.split(entry.name);
    require(
      entry.symbolicLink == null,
      'Unexpected archive link: ${entry.name}',
    );
    require(
      !p.posix.isAbsolute(entry.name) &&
          !parts.contains('..') &&
          !entry.name.contains('\\') &&
          !RegExp(r'^[A-Za-z]:').hasMatch(entry.name),
      'Unsafe archive path: ${entry.name}',
    );
    final target = p.joinAll([destination.path, ...parts]);
    if (entry.isFile) {
      final file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(archiveBytes(entry));
      if (!Platform.isWindows && entry.mode & 0x49 != 0) {
        await run('chmod', ['755', file.path]);
      }
    } else {
      await Directory(target).create(recursive: true);
    }
  }
}

Future<void> cli(Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
