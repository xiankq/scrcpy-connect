import 'dart:async';

import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';

/// 应用作用域的事件与启停连接；功能能力分别注入自己的 provider。
class AppSession {
  AppSession({
    this.events = const Stream<RuntimeEvent>.empty(),
    this.close,
    this.setVisible,
    this.diagnostics,
    AppState? initialState,
    this.initialize = true,
  }) : initialState = initialState ?? AppState();

  final Stream<RuntimeEvent> events;
  final Future<void> Function()? close;
  final Future<void> Function(bool)? setVisible;
  final DiagnosticLog? diagnostics;
  final AppState initialState;
  final bool initialize;
}
