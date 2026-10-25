import 'process.dart';

export 'repository_tooling.dart'
    show repositoryRoot, applicationRoot, executable;

Future<void> runChecked(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Duration timeout = const Duration(minutes: 10),
}) => runStreamingProcess(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  timeout: timeout,
);
