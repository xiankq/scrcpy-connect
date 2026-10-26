// Android 测试夹具共用的命令支持。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../../scripts/src/process.dart';

export '../../scripts/src/repository_tooling.dart' show repositoryRoot;

Future<void> cli(FutureOr<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

ArgResults parse(ArgParser parser, List<String> arguments) {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(parser.usage);
    exit(0);
  }
  return parser.parse(arguments);
}

Future<ProcessResult> checked(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final result = await runProcess(
    executable,
    arguments,
    timeout: timeout,
    stdoutEncoding: utf8,
    stderrEncoding: null,
  );
  final errors = result.stderr as List<int>;
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      utf8.decode(errors, allowMalformed: true),
      result.exitCode,
    );
  }
  return ProcessResult(
    result.pid,
    result.exitCode,
    result.stdout,
    utf8.decode(errors),
  );
}
