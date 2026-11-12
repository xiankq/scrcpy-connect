import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/platform/models/background_event.dart';

import 'platform_capabilities_provider.dart';

import 'package:scrcpy_connect/core/platform/background_control.dart';

part 'background_status_provider.g.dart';

/// 只读取系统事实；权限申请只由页面的显式动作发起。
@Riverpod(retry: _noRetry)
Future<BackgroundStatus> backgroundStatus(Ref ref) {
  final source = ref.watch(backgroundControlProvider);
  final subscription = ref.watch(runtimeEventsProvider).listen((event) {
    if (event['data'] is BackgroundEvent) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() => unawaited(subscription.cancel()));
  return source.readBackgroundStatus();
}

Duration? _noRetry(int _, Object _) => null;
