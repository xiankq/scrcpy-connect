import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';

import 'background_control.dart';

part 'background_status_provider.g.dart';

/// 只读取系统事实；权限申请只由页面的显式动作发起。
@Riverpod(retry: _noRetry)
Future<BackgroundStatus> backgroundStatus(Ref ref) {
  final session = ref.watch(applicationSessionProvider);
  final subscription = session.events.listen((event) {
    if (event['type'] == 'background.changed' ||
        event['type'] == 'background.failed') {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() => unawaited(subscription.cancel()));
  return session.dependencies.background.readBackgroundStatus();
}

Duration? _noRetry(int _, Object _) => null;
