import 'dart:async';

import 'package:device_runtime/device_runtime.dart' show DiagnosticLog;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/app_state.dart';

part 'app_dependencies.g.dart';

/// The provider scope supplies one transport. The state notifier owns its
/// subscription and calls close exactly once when that scope is disposed.
class AppDependencies {
  AppDependencies({
    required this.request,
    this.events = const Stream<Json>.empty(),
    this.close,
    this.diagnostics,
    AppState? initialState,
    this.initialize = true,
  }) : initialState = initialState ?? AppState();
  final DiagnosticLog? diagnostics;
  final BridgeRequest request;
  final Stream<Json> events;
  final Future<void> Function()? close;
  final AppState initialState;
  final bool initialize;
}

@Riverpod(keepAlive: true)
AppDependencies appDependencies(Ref ref) => throw StateError(
  'The application transport must be supplied at bootstrap.',
);
