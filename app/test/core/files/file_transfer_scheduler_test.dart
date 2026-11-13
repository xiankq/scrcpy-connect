import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/files/file_transfer_scheduler.dart';

void main() {
  test('按入队顺序分配两个名额，失败也释放名额', () async {
    final scheduler = FileTransferScheduler();
    final started = <int>[];
    final gates = List.generate(4, (_) => Completer<void>());
    final thirdStarted = Completer<void>();
    final fourthStarted = Completer<void>();
    final jobs = [
      for (var i = 0; i < gates.length; i++)
        scheduler.schedule('$i', () {
          started.add(i);
          if (i == 2) thirdStarted.complete();
          if (i == 3) fourthStarted.complete();
          return gates[i].future;
        }),
    ];
    final failed = expectLater(jobs.first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1]);
    gates[0].completeError(StateError('worker failed'));
    await failed;
    await thirdStarted.future;
    expect(started, [0, 1, 2]);
    gates[1].complete();
    await fourthStarted.future;
    expect(started, [0, 1, 2, 3]);
    gates[2].complete();
    gates[3].complete();
    await Future.wait(jobs.skip(1));
    scheduler.close();
  });

  test('排队取消立即结算，关闭排空排队但继续等待原运行回执', () async {
    final scheduler = FileTransferScheduler(concurrency: 1);
    final active = Completer<void>();
    var finished = false;
    final first = scheduler
        .schedule('running', () => active.future)
        .then((_) => finished = true);
    final cancel = scheduler.schedule(
      'cancel',
      () => throw StateError('cancelled queued worker ran'),
    );
    final close = scheduler.schedule(
      'close',
      () => throw StateError('closed queued worker ran'),
    );
    await Future<void>.delayed(Duration.zero);
    scheduler.cancelQueued('running');
    scheduler.cancelQueued('cancel');
    await cancel;
    expect(finished, isFalse);
    scheduler.close();
    await close;
    await scheduler.schedule('late', () => throw StateError('late worker ran'));
    expect(finished, isFalse);
    active.complete();
    await first;
    expect(finished, isTrue);
  });
}
