import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('取消等待中的读取仅取消所属观察者，不等待捕获停止', () async {
    final reading = Completer<ScrcpyEvent?>();
    final cancelled = <String>[];
    var reads = 0;
    final subscription = ScrcpyEventObserver(
      open: () async => 'observer',
      next: (_) {
        reads++;
        return reading.future;
      },
      cancel: (id) async {
        cancelled.add(id);
        reading.complete(null);
      },
    ).stream.listen((_) {});
    await tick();
    expect(reads, 1);
    await subscription.cancel();
    expect(cancelled, ['observer']);
  });

  test('登记期间取消精确释放迟到观察者且不开始读取', () async {
    final opening = Completer<String>();
    final cancelled = <String>[];
    var reads = 0;
    final subscription = ScrcpyEventObserver(
      open: () => opening.future,
      next: (_) async {
        reads++;
        return null;
      },
      cancel: (id) async => cancelled.add(id),
    ).stream.listen((_) {});
    final closing = subscription.cancel();
    opening.complete('late');
    await closing;
    expect(cancelled, ['late']);
    expect(reads, 0);
  });

  test('暂停时只持有一个迟到事件，恢复先交付该事件再读取终态', () async {
    final reading = Completer<ScrcpyEvent?>();
    final observed = <ScrcpyEvent>[];
    var reads = 0;
    var releases = 0;
    final subscription = ScrcpyEventObserver(
      open: () async => 'observer',
      next: (_) {
        reads++;
        return reads == 1
            ? reading.future
            : Future.value(const ScrcpyStopped());
      },
      cancel: (_) async {
        releases++;
      },
    ).stream.listen(observed.add);
    await tick();
    subscription.pause();
    reading.complete(const ScrcpyClipboardChanged('latest'));
    await tick();
    expect(reads, 1);
    expect(observed, isEmpty);
    subscription.resume();
    await tick();
    await tick();
    expect(observed.map((event) => event.runtimeType), [
      ScrcpyClipboardChanged,
      ScrcpyStopped,
    ]);
    expect(releases, 1);
    await subscription.cancel();
  });

  test('连续取消失败保留同一观察者，显式重试确认后才发布关闭', () async {
    final reading = Completer<ScrcpyEvent?>();
    final entered = Completer<void>();
    final cancelled = <String>[];
    var released = false;
    final owner = ScrcpyEventObserver(
      open: () async => 'exact-observer',
      next: (_) {
        entered.complete();
        return reading.future;
      },
      cancel: (id) async {
        cancelled.add(id);
        if (cancelled.length < 3) throw StateError('temporary');
        reading.complete(null);
      },
    );
    unawaited(owner.whenClosed.then((_) => released = true));
    final subscription = owner.stream.listen((_) {});
    await entered.future;
    await expectLater(subscription.cancel(), throwsStateError);
    await expectLater(owner.close(), throwsStateError);
    expect(released, isFalse);
    await owner.close();
    await owner.whenClosed;
    expect(cancelled, List.filled(3, 'exact-observer'));
    expect(released, isTrue);
  });

  test('登记迟到且首次取消失败，保留原 ID 重试而不开始读取', () async {
    final registration = Completer<String>();
    final opening = Completer<void>();
    final cancelled = <String>[];
    var reads = 0;
    final owner = ScrcpyEventObserver(
      open: () {
        opening.complete();
        return registration.future;
      },
      next: (_) async {
        reads++;
        return null;
      },
      cancel: (id) async {
        cancelled.add(id);
        if (cancelled.length == 1) throw StateError('cleanup');
      },
    );
    final subscription = owner.stream.listen((_) {});
    await opening.future;
    final rejected = expectLater(subscription.cancel(), throwsStateError);
    registration.complete('late-exact-id');
    await rejected;
    await owner.close();
    await owner.whenClosed;
    expect(cancelled, ['late-exact-id', 'late-exact-id']);
    expect(reads, 0);
  });

  test('未开始监听即关闭不会创建原生观察者', () async {
    var opened = 0;
    final owner = ScrcpyEventObserver(
      open: () async {
        opened++;
        return 'observer';
      },
      next: (_) async => null,
      cancel: (_) async {},
    );
    await owner.close();
    await owner.stream.drain<void>();
    expect(opened, 0);
  });

  test('缺少停止终态报告未知，取消失败后仍能精确重试', () async {
    var cancellations = 0;
    final errors = <Object>[];
    final owner = ScrcpyEventObserver(
      open: () async => 'observer',
      next: (_) async => null,
      cancel: (_) async {
        if (++cancellations == 1) throw StateError('cleanup');
      },
    );
    final done = Completer<void>();
    owner.stream.listen((_) {}, onError: errors.add, onDone: done.complete);
    await done.future;
    expect(errors.whereType<ScrcpyException>().single.code, 'result_unknown');
    expect(errors.whereType<StateError>(), hasLength(1));
    await owner.close();
    expect(cancellations, 2);
  });
}
