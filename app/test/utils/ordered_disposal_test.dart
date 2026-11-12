import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';

void main() {
  test('并发关闭共用执行；失败后只重试未完成步骤，继续清理独立资源', () async {
    final first = Completer<void>();
    final calls = <String>[];
    var failures = 1;
    final disposal = OrderedDisposal([
      () {
        calls.add('first');
        return first.future;
      },
      () async {
        calls.add('second');
        if (failures-- > 0) throw StateError('close failed');
      },
      () async {
        calls.add('third');
      },
    ]);
    final pending = disposal.run();
    expect(disposal.run(), same(pending));
    expect(calls, ['first']);
    final checked = expectLater(pending, throwsStateError);
    first.complete();
    await checked;
    expect(calls, ['first', 'second', 'third']);
    await disposal.run();
    expect(calls, ['first', 'second', 'third', 'second']);
    await disposal.run();
    expect(calls, ['first', 'second', 'third', 'second']);
  });
}
