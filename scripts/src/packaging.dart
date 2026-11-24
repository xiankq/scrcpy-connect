import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Emits stage timings and a single actionable failure at the package entrypoint.
class PackagingLog {
  PackagingLog(this.package);

  final String package;
  String _stage = 'arguments';
  final _time = Stopwatch();

  void begin(String stage) {
    done();
    _stage = stage;
    _time
      ..reset()
      ..start();
    stdout.writeln('INFO [$package/$_stage] Started');
  }

  void done() {
    if (!_time.isRunning) return;
    _time.stop();
    stdout.writeln('INFO [$package/$_stage] Completed in ${_seconds}s');
  }

  String get _seconds => (_time.elapsedMilliseconds / 1000).toStringAsFixed(2);

  void fail(Object error) {
    _time.stop();
    final detail = switch (error) {
      ProcessException(:final executable, :final message, :final errorCode) =>
        '${p.basename(executable)}: $message (exit $errorCode)',
      TimeoutException(:final message, :final duration) =>
        message ?? 'Timed out after $duration',
      ArgumentError(:final message) => message.toString(),
      FormatException(:final message) => message,
      StateError(:final message) => message,
      _ => error.toString(),
    };
    final message = '[$package/$_stage] Failed after ${_seconds}s. $detail';
    stderr.writeln('ERROR $message');
    if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
      final escaped = message
          .replaceAll('%', '%25')
          .replaceAll('\r', '%0D')
          .replaceAll('\n', '%0A');
      stdout.writeln('::error::$escaped');
    }
  }
}

String? updateFeedDefine(String? address) {
  if (address == null || address.isEmpty) return null;
  final uri = Uri.tryParse(address);
  if (uri == null ||
      !uri.isScheme('https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw ArgumentError('The update feed must be a public HTTPS URL.');
  }
  return '--dart-define=APP_UPDATE_FEED=$address';
}
