import 'package:scrcpy_connect/core/diagnostics/diagnostic_record.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// 进程级写入器由重试和 provider 替换共享。
Future<DiagnosticLog>? _opening;

Future<DiagnosticLog> applicationDiagnostics() =>
    _opening ??= _open().catchError((Object error, StackTrace stack) {
      _opening = null;
      Error.throwWithStackTrace(error, stack);
    });

Future<DiagnosticLog> _open() async {
  final directory = await getApplicationSupportDirectory();
  final log = await DiagnosticLog.open(
    Directory(p.join(directory.path, 'diagnostics')),
  );
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    log.record(
      DiagnosticArea.app,
      'flutter.error',
      level: LogLevel.error,
      fields: {'errorType': details.exception.runtimeType.toString()},
    );
    unawaited(log.flush());
    previousFlutter?.call(details);
  };
  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    log.record(
      DiagnosticArea.app,
      'async.error',
      level: LogLevel.error,
      fields: {'errorType': error.runtimeType.toString()},
    );
    unawaited(log.flush());
    return previousPlatform?.call(error, stack) ?? false;
  };
  log.record(
    DiagnosticArea.app,
    'app.started',
    fields: {
      'platform': defaultTargetPlatform.name,
      'version': const String.fromEnvironment(
        'FLUTTER_BUILD_NAME',
        defaultValue: 'unknown',
      ),
      'buildMode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
    },
  );
  return log;
}
