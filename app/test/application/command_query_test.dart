import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/widgets/command_query.dart';
import 'package:scrcpy_connect/models/application_request.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('查询只响应自身主题和设备的事件', () async {
    final events = StreamController<Json>.broadcast(sync: true);
    var reads = 0;
    final query = CommandQuery(
      request: (command, [params = const {}]) async => {'read': ++reads},
      events: events.stream,
      command: 'calls.list',
      params: {'deviceId': 'a'},
    );
    addTearDown(query.dispose);
    addTearDown(events.close);
    await flush();
    for (final event in <Json>[
      {'type': 'calls.changed', 'deviceId': 'b'},
      {'type': 'transfers.progress', 'deviceId': 'a'},
      {'type': 'clipboard.changed', 'deviceId': 'a'},
      {'type': 'session.frame', 'deviceId': 'a'},
    ]) {
      events.add(event);
    }
    await flush();
    expect(reads, 1);
    events.add({'type': 'calls.changed', 'deviceId': 'a'});
    await flush();
    expect(reads, 2);
    events.add({'type': 'state.resynced'});
    await flush();
    expect(reads, 3);
  });

  test('在途突发失效合并一次后续读取，旧查询释放后不通知', () async {
    final events = StreamController<Json>.broadcast(sync: true);
    final pending = Completer<Json>();
    final finishing = Completer<Json>();
    var reads = 0;
    var changes = 0;
    final query = CommandQuery(
      request: (command, [params = const {}]) =>
          ++reads == 1 ? pending.future : finishing.future,
      events: events.stream,
      command: 'transfers.list',
      params: const {},
    )..addListener(() => changes++);
    addTearDown(events.close);
    await flush();
    for (var i = 0; i < 100; i++) {
      events.add({'type': 'transfers.progress', 'transferId': 'a'});
    }
    await flush();
    expect(reads, 1);
    pending.complete({'read': 1});
    await flush();
    expect(reads, 2);
    query.dispose();
    final before = changes;
    finishing.complete({'read': 2});
    await flush();
    expect(changes, before);
  });
}
