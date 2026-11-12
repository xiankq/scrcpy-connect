import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/platform/background_control.dart';
import 'package:scrcpy_connect/core/platform/background_policy.dart';
import 'package:scrcpy_connect/core/platform/models/background_event.dart';

void main() {
  test('后台请求先交付系统事实，再应用声音策略，保留自动恢复标记', () async {
    final platform = _Background();
    final events = <BackgroundEvent>[];
    final policy = BackgroundPolicy(
      platform: platform,
      audioPolicy: (enabled) async {
        expect(enabled, isTrue);
        expect(events.single, isA<BackgroundChanged>());
      },
      onEvent: events.add,
      isDisposed: () => false,
    );
    final pending = policy.apply(true, automatic: true);
    expect(platform.requests, [(enabled: true, automatic: true)]);
    expect(events, isEmpty);
    const receipt = BackgroundStatus(running: true, connectionRequested: true);
    platform.receipt.complete(receipt);
    expect(await pending, same(receipt));
    expect((events.single as BackgroundChanged).status, same(receipt));
  });

  test('平台拒绝以类型化原因交付，声音策略仍执行且不伪造成功状态', () async {
    final platform = _Background();
    final events = <BackgroundEvent>[];
    final audio = <bool>[];
    final policy = BackgroundPolicy(
      platform: platform,
      audioPolicy: (enabled) async => audio.add(enabled),
      onEvent: events.add,
      isDisposed: () => false,
    );
    final pending = policy.apply(false, automatic: false);
    platform.receipt.completeError(StateError('platform rejected'));
    expect(await pending, isNull);
    expect(
      (events.single as BackgroundFailed).reason,
      contains('platform rejected'),
    );
    expect(audio, [false]);
  });

  test('关闭后的迟到系统回执不再发布通知，也不开始声音策略', () async {
    for (final rejected in [false, true]) {
      final platform = _Background();
      final events = <BackgroundEvent>[];
      var disposed = false;
      final policy = BackgroundPolicy(
        platform: platform,
        audioPolicy: (_) async => fail('关闭后不能开始声音策略'),
        onEvent: events.add,
        isDisposed: () => disposed,
      );
      final pending = policy.apply(true, automatic: false);
      final result = expectLater(pending, _disposed);
      disposed = true;
      if (rejected) {
        platform.receipt.completeError(StateError('late rejection'));
      } else {
        platform.receipt.complete(const BackgroundStatus(running: true));
      }
      await result;
      expect(events, isEmpty);
      await expectLater(policy.apply(false, automatic: false), _disposed);
      expect(platform.requests, hasLength(1));
    }
  });

  test('事实交付期间关闭应用，不能继续声音策略', () async {
    final platform = _Background();
    var disposed = false;
    final policy = BackgroundPolicy(
      platform: platform,
      audioPolicy: (_) async => fail('关闭后不能开始声音策略'),
      onEvent: (_) => disposed = true,
      isDisposed: () => disposed,
    );
    final pending = policy.apply(true, automatic: false);
    platform.receipt.complete(const BackgroundStatus(running: true));
    await expectLater(pending, _disposed);
  });

  test('无平台后台能力时只应用声音策略，不构造系统成功状态', () async {
    final audio = <bool>[];
    final policy = BackgroundPolicy(
      platform: null,
      audioPolicy: (enabled) async => audio.add(enabled),
      onEvent: (_) => fail('未请求平台时不应发布系统事实'),
      isDisposed: () => false,
    );
    expect(await policy.apply(false, automatic: true), isNull);
    expect(audio, [false]);
  });
}

final _disposed = throwsA(
  isA<RequestFailure>().having((error) => error.code, 'code', 'disposed'),
);

final class _Background implements BackgroundControl {
  final receipt = Completer<BackgroundStatus>();
  final requests = <({bool enabled, bool automatic})>[];

  @override
  Future<BackgroundStatus> requestBackground({
    required bool enabled,
    bool automatic = false,
    bool askNotificationPermission = false,
  }) {
    expect(askNotificationPermission, isFalse);
    requests.add((enabled: enabled, automatic: automatic));
    return receipt.future;
  }

  @override
  Future<BackgroundStatus> readBackgroundStatus() =>
      throw StateError('策略不应重复读取系统状态');
}
