import 'dart:async';

import 'package:scrcpy/scrcpy.dart';

/// 让公开观察者消费测试事件；关闭只撤销本次订阅。
ScrcpyEventObserver observeFixtureEvents(Stream<ScrcpyEvent> events) {
  StreamIterator<ScrcpyEvent>? iterator;
  Future<bool>? reading;
  return ScrcpyEventObserver(
    open: () async {
      iterator = StreamIterator(events);
      // 原生观察者登记后会缓存事件；同步建立订阅以保持相同交付边界。
      reading = iterator!.moveNext();
      return 'fixture-observer';
    },
    next: (_) async {
      final available = await (reading ??= iterator!.moveNext());
      reading = null;
      return available ? iterator!.current : null;
    },
    cancel: (_) async => iterator?.cancel(),
  );
}

/// 无远端事件时保持读取在途；明确关闭后才结束，不把空流当作正常运行。
ScrcpyEventObserver idleFixtureObserver() {
  final event = Completer<ScrcpyEvent?>();
  return ScrcpyEventObserver(
    open: () async => 'fixture-observer',
    next: (_) => event.future,
    cancel: (_) async {
      if (!event.isCompleted) event.complete(null);
    },
  );
}
