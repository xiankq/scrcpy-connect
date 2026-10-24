import 'dart:io';

import 'src/architecture.dart';
import 'src/repository_tooling.dart';
import 'src/native_architecture.dart';

void main() {
  final root = repositoryRoot();
  final problems = [
    ...checkArchitecture(root),
    ...checkNativeArchitecture(root),
  ];
  if (problems.isEmpty) {
    stdout.writeln('PASS: Dart/Rust 模块依赖、通用能力分层及私有接口');
    return;
  }
  stderr.writeln(problems.join('\n'));
  exitCode = 1;
}
