import 'dart:io';

import 'src/architecture.dart';
import 'src/repository_tooling.dart';
import 'src/native_architecture.dart';

Future<void> main() async {
  final root = repositoryRoot();
  final problems = [
    ...checkArchitecture(root),
    ...await checkNativeArchitecture(root),
  ];
  if (problems.isEmpty) {
    stdout.writeln('PASS: Dart/Rust 模块依赖、通用能力分层及私有接口');
    return;
  }
  stderr.writeln(problems.join('\n'));
  exitCode = 1;
}
