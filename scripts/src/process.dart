import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 编译日志直接交给终端，不把完整构建输出留在内存或临时文件中。
Future<void> runStreamingProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  Duration timeout = const Duration(minutes: 30),
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
    runInShell: _needsShell(executable),
  );
  try {
    final code = await process.exitCode.timeout(timeout);
    if (code != 0) {
      throw ProcessException(executable, arguments, 'Command failed', code);
    }
  } on Object {
    await _terminate(process, executable, arguments);
    rethrow;
  }
}

bool _needsShell(String executable) =>
    Platform.isWindows &&
    (executable.toLowerCase().endsWith('.bat') ||
        executable.toLowerCase().endsWith('.cmd'));

Future<void> _terminate(
  Process process,
  String executable,
  List<String> arguments,
) async {
  process.kill(ProcessSignal.sigkill);
  try {
    await process.exitCode.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    throw ProcessException(
      executable,
      arguments,
      'Could not confirm child termination after command failure',
    );
  }
}

/// 并发捕获双向输出，并在向调用方报告超时前回收自有子进程，避免夹具清理与仍运行的命令竞争。
///
/// 每条输出管道有独立字节预算；超限后回收子进程并报错，不无限累积或返回截断的成功结果。
Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
  bool? runInShell,
  Duration timeout = const Duration(seconds: 120),
  int maxOutputBytes = 32 * 1024 * 1024,
}) async {
  if (maxOutputBytes < 1) {
    throw ArgumentError.value(
      maxOutputBytes,
      'maxOutputBytes',
      'Must be positive',
    );
  }
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell ?? _needsShell(executable),
  );
  final output = _ProcessOutput(process.stdout, 'stdout', maxOutputBytes);
  final errors = _ProcessOutput(process.stderr, 'stderr', maxOutputBytes);
  final completion = Future.wait([
    process.exitCode,
    process.stdin.close().then((_) => 0),
    output.done.future.then((_) => 0),
    errors.done.future.then((_) => 0),
  ], eagerError: true).then((values) => values.first);
  try {
    final code = await completion.timeout(timeout);
    final out = output.bytes.takeBytes(), err = errors.bytes.takeBytes();
    return ProcessResult(
      process.pid,
      code,
      stdoutEncoding == null ? out : stdoutEncoding.decode(out),
      stderrEncoding == null ? err : stderrEncoding.decode(err),
    );
  } on Object {
    // 单独限制回收期限；无法确认终止不能当成普通命令超时后已可安全清理。
    //
    await _terminate(process, executable, arguments);
    rethrow;
  } finally {
    await Future.wait([output.close(), errors.close()]);
  }
}

class _ProcessOutput {
  _ProcessOutput(Stream<List<int>> stream, String name, int limit) {
    subscription = stream.listen(
      (chunk) {
        if (done.isCompleted) return;
        if (chunk.length > limit - bytes.length) {
          done.completeError(ProcessOutputLimitException(name, limit));
          return;
        }
        bytes.add(chunk);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      cancelOnError: true,
    );
  }

  final bytes = BytesBuilder(copy: false);
  final done = Completer<void>();
  late final StreamSubscription<List<int>> subscription;

  Future<void> close() async {
    await subscription.cancel();
    if (!done.isCompleted) done.complete();
  }
}

class ProcessOutputLimitException implements Exception {
  const ProcessOutputLimitException(this.stream, this.limit);

  final String stream;
  final int limit;

  @override
  String toString() => 'Child $stream exceeded the $limit byte output budget';
}
