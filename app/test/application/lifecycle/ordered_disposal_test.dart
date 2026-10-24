import 'dart:async';

import 'package:scrcpy_connect/application/lifecycle/ordered_disposal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('一个模块释放失败后仍释放其余资源，重试只处理未确认的模块', () async {
    final calls = <String>[];
    var fail = true;
    final disposal = OrderedDisposal([
      () async {
        calls.add('files');
        if (fail) throw StateError('journal flush failed');
      },
      () async => calls.add('media'),
      () async => calls.add('events'),
    ]);

    await expectLater(disposal.run(), throwsStateError);
    expect(calls, ['files', 'media', 'events']);
    fail = false;
    await disposal.run();
    expect(calls, ['files', 'media', 'events', 'files']);
    await disposal.run();
    expect(calls, hasLength(4));
  });

  test('并发释放共享同一次资源回收', () async {
    final gate = Completer<void>();
    var calls = 0;
    final disposal = OrderedDisposal([
      () async {
        calls++;
        await gate.future;
      },
    ]);
    final first = disposal.run();
    expect(disposal.run(), same(first));
    expect(calls, 1);
    gate.complete();
    await first;
  });
}
