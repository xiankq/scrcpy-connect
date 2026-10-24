import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/command_query.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

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

  for (final command in [
    'apps.list',
    'session.quality.options',
    'device.capabilities',
    'device.data.get',
    'device.diagnose',
    'files.list',
  ]) {
    test('$command 仅在所属连接变化后重新读取并恢复离线错误', () async {
      final events = StreamController<Json>.broadcast(sync: true);
      var reads = 0;
      final query = CommandQuery(
        request: (_, [params = const {}]) async {
          if (++reads == 1) throw StateError('设备离线');
          return {'connection': 'new'};
        },
        events: events.stream,
        command: command,
        params: {'deviceId': 'a'},
      );
      addTearDown(query.dispose);
      addTearDown(events.close);
      await flush();
      expect(query.error, isNotNull);
      events.add({'type': 'device.changed', 'deviceId': 'b'});
      await flush();
      expect(reads, 1);
      events.add({'type': 'device.changed', 'deviceId': 'a'});
      await flush();
      expect(reads, 2);
      expect(query.error, isNull);
      expect(query.data, {'connection': 'new'});
    });
  }

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

  test('传输详情接受批次子项变化并忽略其他任务', () async {
    final events = StreamController<Json>.broadcast(sync: true);
    var reads = 0;
    final query = CommandQuery(
      request: (command, [params = const {}]) async {
        reads++;
        return {
          'id': 'root',
          'items': [
            {'id': 'child'},
          ],
        };
      },
      events: events.stream,
      command: 'transfers.get',
      params: {'transferId': 'root'},
    );
    addTearDown(query.dispose);
    addTearDown(events.close);
    await flush();
    events.add({'type': 'transfers.progress', 'transferId': 'unrelated'});
    await flush();
    expect(reads, 1);
    events.add({'type': 'transfers.progress', 'transferId': 'child'});
    await flush();
    expect(reads, 2);
  });
}
