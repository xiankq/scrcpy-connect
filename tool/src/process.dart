import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Captures both pipes concurrently and reaps the owned child before a timeout
/// reaches its caller, so fixture cleanup cannot race a still-running command.
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
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell:
        runInShell ??
        (Platform.isWindows &&
            (executable.toLowerCase().endsWith('.bat') ||
                executable.toLowerCase().endsWith('.cmd'))),
  );
  final output = _ProcessOutput(process.stdout);
  final errors = _ProcessOutput(process.stderr);
  final completion = Future.wait([
    process.exitCode,
    process.stdin.close().then((_) => 0),
    output.done.future.then((_) => 0),
    errors.done.future.then((_) => 0),
  ]).then((values) => values.first);
  try {
    final code = await completion.timeout(timeout);
    final out = output.bytes.takeBytes(), err = errors.bytes.takeBytes();
    return ProcessResult(
      process.pid,
      code,
      stdoutEncoding == null ? out : stdoutEncoding.decode(out),
      stderrEncoding == null ? err : stderrEncoding.decode(err),
    );
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    // Reaping is bounded separately: inability to confirm termination must not
    // be mistaken for an ordinary command timeout followed by safe cleanup.
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw ProcessException(
        executable,
        arguments,
        'Could not confirm child termination after command timeout',
      );
    }
    rethrow;
  } finally {
    await Future.wait([output.close(), errors.close()]);
  }
}

class _ProcessOutput {
  _ProcessOutput(Stream<List<int>> stream) {
    subscription = stream.listen(
      bytes.add,
      onDone: () => done.complete(),
      onError: (Object error, StackTrace stack) =>
          done.completeError(error, stack),
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
