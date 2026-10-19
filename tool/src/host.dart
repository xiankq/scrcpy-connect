import 'dart:io';

export 'core_tooling.dart' show repositoryRoot, executable;

Future<void> runChecked(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Duration? timeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
    runInShell:
        Platform.isWindows &&
        (executable.endsWith('.bat') || executable.endsWith('.cmd')),
  );
  final completion = process.exitCode;
  final code = timeout == null
      ? await completion
      : await completion.timeout(
          timeout,
          onTimeout: () async {
            process.kill(ProcessSignal.sigkill);
            await completion;
            throw ProcessException(
              executable,
              arguments,
              'Timed out after $timeout',
            );
          },
        );
  if (code != 0) {
    throw ProcessException(executable, arguments, 'Command failed', code);
  }
}
