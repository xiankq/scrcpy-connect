import 'dart:io';

import 'package:path/path.dart' as p;

import 'process.dart';

Directory repositoryRoot([Uri? script]) {
  final entrypoint = script ?? Platform.script;
  // package:test 的入口可能位于系统临时目录；此时从调用者所在工作区定位。
  for (final start in [
    if (entrypoint.scheme == 'file') File.fromUri(entrypoint).absolute.parent,
    if (script == null) Directory.current.absolute,
  ]) {
    var directory = start;
    while (true) {
      if (File(p.join(directory.path, 'pubspec.yaml')).existsSync() &&
          File(p.join(directory.path, 'Cargo.toml')).existsSync()) {
        return directory;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
  }
  throw StateError(
    'Cannot locate the repository from the script or working directory',
  );
}

/// 唯一 Flutter 应用属于仓库工作区。
Directory applicationRoot([Directory? repository]) =>
    Directory(p.join((repository ?? repositoryRoot()).path, 'app'));

String? executable(String name) {
  final extensions = Platform.isWindows
      ? [...((Platform.environment['PATHEXT'] ?? '.EXE;.BAT;.CMD').split(';'))]
      : [''];
  for (final directory in (Platform.environment['PATH'] ?? '').split(
    p.separator == r'\' ? ';' : ':',
  )) {
    for (final extension in extensions) {
      final path = p.join(directory, '$name$extension');
      final file = File(path);
      if (file.existsSync() &&
          (Platform.isWindows || (file.statSync().mode & 0x49) != 0)) {
        return path;
      }
    }
  }
  return null;
}

String get dartExecutable =>
    {'dart', 'dart.exe'}.contains(p.basename(Platform.resolvedExecutable))
    ? Platform.resolvedExecutable
    : executable('dart') ?? 'dart';

String get userHome =>
    Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '';

Future<ProcessResult> runTool(
  List<String> command, {
  Directory? cwd,
  Map<String, String>? environment,
  bool quiet = false,
  bool secret = false,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final result = await runProcess(
    command.first,
    command.skip(1).toList(),
    workingDirectory: cwd?.path,
    environment: environment,
    timeout: timeout,
  );
  if (!quiet && !secret) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
  }
  if (result.exitCode != 0) {
    if (quiet && !secret) stderr.write(result.stderr);
    throw ProcessException(
      command.first,
      command.skip(1).toList(),
      'exited with status ${result.exitCode}',
      result.exitCode,
    );
  }
  return result;
}

Future<void> streamTool(
  List<String> command, {
  Directory? cwd,
  Map<String, String>? environment,
  Duration timeout = const Duration(minutes: 30),
}) => runStreamingProcess(
  command.first,
  command.skip(1).toList(),
  workingDirectory: cwd?.path,
  environment: environment,
  timeout: timeout,
);

void copyDirectory(
  Directory source,
  Directory destination, {
  bool Function(String name)? exclude,
}) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (exclude?.call(name) ?? false) continue;
    final target = p.join(destination.path, name);
    if (entity is Directory) {
      copyDirectory(entity, Directory(target), exclude: exclude);
    } else if (entity is File) {
      entity.copySync(target);
    } else if (entity is Link) {
      // 即使工作区输入是符号链接，检查树仍拥有独立输入。
      final resolved = entity.resolveSymbolicLinksSync();
      if (Directory(resolved).existsSync()) {
        copyDirectory(Directory(resolved), Directory(target), exclude: exclude);
      } else {
        File(resolved).copySync(target);
      }
    }
  }
}
