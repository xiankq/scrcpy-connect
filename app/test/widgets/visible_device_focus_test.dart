import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/current_device_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/widgets/visible_device_focus.dart';

void main() {
  testWidgets('应用 scope 替换后重新声明焦点，瞬时恢复和前后台变化也会重新核验', (tester) async {
    final previous = StateSubscription(_Dependencies());
    final replacement = StateSubscription(_Dependencies());
    addTearDown(previous.dispose);
    addTearDown(replacement.dispose);
    final focusOverride = currentDeviceProvider.overrideWith(_Focus.new);
    final recoveryOverride = recoveryStateProvider.overrideWith(_Recovery.new);
    final container = ProviderContainer(
      overrides: [
        stateSubscriptionProvider.overrideWithValue(previous),
        focusOverride,
        recoveryOverride,
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: VisibleDeviceFocus(deviceId: 'device', child: SizedBox()),
        ),
      ),
    );
    final focus = container.read(currentDeviceProvider.notifier) as _Focus;
    expect(focus.calls, ['device']);
    container.updateOverrides([
      stateSubscriptionProvider.overrideWithValue(replacement),
      focusOverride,
      recoveryOverride,
    ]);
    await tester.pump();
    expect(focus.calls, ['device', 'device']);
    final recovery =
        container.read(recoveryStateProvider.notifier) as _Recovery;
    recovery.pending(true);
    recovery.pending(false);
    await tester.pump();
    expect(focus.calls, ['device', 'device', 'device']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(focus.calls, hasLength(3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(focus.calls, hasLength(4));
    await tester.pumpWidget(const SizedBox.shrink());
    recovery.pending(true);
    recovery.pending(false);
    await tester.pump();
    expect(focus.calls, hasLength(4));
    expect(tester.takeException(), isNull);
  });
}

class _Focus extends CurrentDeviceNotifier {
  final calls = <String?>[];
  @override
  String? build() => null;
  @override
  Future<void> focus(String? deviceId) async => calls.add(deviceId);
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
  void pending(bool value) =>
      state = state.copyWith(reconciliationPending: value);
}

class _Dependencies implements AppDependencies {
  @override
  AppState get initialState => AppState();
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<void> Function()? get close => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
