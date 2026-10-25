import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:scrcpy_connect/platform/diagnostics/diagnostic_log.dart'
    show DiagnosticLog;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/application/app_state.dart';

part 'app_dependencies.g.dart';

/// 每个 provider scope 只供应一个传输；状态所有者订阅事件，并在释放时调用一次 close。
class AppDependencies {
  AppDependencies({
    required this.request,
    ApplicationCommandExecutor? execute,
    this.events = const Stream<Json>.empty(),
    this.close,
    this.diagnostics,
    AppState? initialState,
    this.initialize = true,
  }) : execute =
           execute ?? ((command, params) => request(command.wire, params)),
       initialState = initialState ?? AppState();
  final DiagnosticLog? diagnostics;
  final ApplicationRequest request;
  final ApplicationCommandExecutor execute;
  final Stream<Json> events;
  final Future<void> Function()? close;
  final AppState initialState;
  final bool initialize;
}

@Riverpod(keepAlive: true)
AppDependencies appDependencies(Ref ref) => throw StateError(
  'The application transport must be supplied at bootstrap.',
);
