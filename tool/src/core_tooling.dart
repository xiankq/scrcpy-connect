import 'dart:io';

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
      throw StateError('Cannot locate the repository from the script path');
    }
    directory = parent;
  }
}

String? executable(String name) {
  final extensions = Platform.isWindows
      ? [
          '',
          ...((Platform.environment['PATHEXT'] ?? '.EXE;.BAT;.CMD').split(';')),
        ]
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

ProcessResult runTool(
  List<String> command, {
  Directory? cwd,
  Map<String, String>? environment,
  bool quiet = false,
  bool secret = false,
}) {
  final result = Process.runSync(
    command.first,
    command.skip(1).toList(),
    workingDirectory: cwd?.path,
    environment: environment,
    runInShell:
        Platform.isWindows && command.first.toLowerCase().endsWith('.bat'),
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
      // The check tree owns its inputs even when a workspace input is a link.
      final resolved = entity.resolveSymbolicLinksSync();
      if (Directory(resolved).existsSync()) {
        copyDirectory(Directory(resolved), Directory(target), exclude: exclude);
      } else {
        File(resolved).copySync(target);
      }
    }
  }
}
