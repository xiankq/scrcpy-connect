import 'dart:async';

import 'package:test/test.dart';

import '../../src/driver_cleanup.dart';

void main() {
  test('恢复失败后仍按顺序等待其他设备和夹具的恢复', () async {
    final calls = <String>[];
    final release = Completer<void>();
    final operation = withDriverCleanup(
      () async {},
      () => {
        'foreground': () => throw StateError('foreground unavailable'),
        'first clipboard': () async {
          calls.add('first-start');
          await release.future;
          calls.add('first-end');
          throw StateError('first endpoint unavailable');
        },
        'second clipboard': () => calls.add('second-restored'),
        'fixture': () => calls.add('fixture-removed'),
      },
    );
    final failure = expectLater(
      operation,
      throwsA(
        isA<DriverCleanupException>().having(
          (error) => error.failures.map((failure) => failure.step),
          'failed steps',
          ['foreground', 'first clipboard'],
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['first-start']);
    release.complete();
    await failure;
    expect(calls, [
      'first-start',
      'first-end',
      'second-restored',
      'fixture-removed',
    ]);
  });

  test('收尾成功时原始故障和堆栈原样返回', () async {
    final primary = StateError('capture failed');
    final stack = StackTrace.fromString('original capture stack');
    try {
      await withDriverCleanup(
        () => Future<void>.error(primary, stack),
        () => {'fixture': () {}},
      );
      fail('Expected capture failure');
    } catch (error, actualStack) {
      expect(error, same(primary));
      expect(actualStack.toString(), stack.toString());
    }
  });

  test('收尾故障同时保留主错误、原堆栈及全部恢复失败', () async {
    final primary = StateError('capture failed');
    final stack = StackTrace.fromString('original capture stack');
    try {
      await withDriverCleanup(
        () => Future<void>.error(primary, stack),
        () => {
          'settings': () => throw StateError('setting failed'),
          'fixture': () => throw StateError('uninstall failed'),
        },
      );
      fail('Expected combined failure');
    } on DriverCleanupException catch (error, actualStack) {
      expect(error.primaryError, same(primary));
      expect(error.primaryStack, same(stack));
      expect(actualStack.toString(), stack.toString());
      expect(error.failures.map((failure) => failure.step), [
        'settings',
        'fixture',
      ]);
      expect(error.toString(), contains('capture failed'));
      expect(error.toString(), contains('setting failed'));
      expect(error.toString(), contains('uninstall failed'));
    }
  });

  test('无回执的 VM 读取有界结束，停止并排空后才恢复设备', () async {
    var stopped = false;
    var requestCount = 0;
    final order = <String>[];
    final neverReplies = Completer<void>();
    final inspection = () async {
      while (!stopped) {
        requestCount++;
        try {
          await driverRpc(
            neverReplies.future,
            timeout: const Duration(milliseconds: 20),
          );
        } on TimeoutException {
          if (!stopped) rethrow;
        }
      }
      order.add('inspection-drained');
    }();
    await withDriverCleanup(
      () async {},
      () => {
        'inspection': () async {
          stopped = true;
          await inspection;
        },
        'device settings': () => order.add('device-restored'),
      },
    );
    expect(requestCount, 1);
    expect(order, ['inspection-drained', 'device-restored']);
    neverReplies.complete();
    await Future<void>.delayed(Duration.zero);
    expect(requestCount, 1);
  });
}
