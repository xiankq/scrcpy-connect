import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/application_events.dart';
import 'package:scrcpy_connect/services/state_recovery.dart';

ApplicationEvents eventsOwner({
  bool Function(ApplicationEvent)? accept,
  void Function(ApplicationEvent)? state,
  void Function(ApplicationEvent)? before,
  void Function(ApplicationEvent)? after,
  void Function()? changed,
  Future<void> Function(ApplicationEvent)? platform,
}) => ApplicationEvents(
  acceptState: accept ?? (_) => true,
  onState: state ?? (_) {},
  beforePublish: before ?? (_) {},
  afterState: after ?? (_) {},
  onLocalStateChanged: changed,
  handlePlatform: platform ?? (_) async {},
  isDisposed: () => false,
);

StateJson snapshot(int sequence, String shareStatus) => {
  'sequence': sequence,
  'settings': <String, dynamic>{},
  for (final key in [
    'devices',
    'sessions',
    'sources',
    'transfers',
    'activities',
    'companions',
  ])
    key: <StateJson>[],
  'shares': [
    {'shareId': 'share', 'status': shareStatus},
  ],
};

void main() {
  test('文件与分享共用业务序列，保留各自投影，分离后不再发布', () async {
    final files = StreamController<ApplicationEvent>(sync: true);
    final catalog = StreamController<ApplicationEvent>(sync: true);
    final sharing = StreamController<ApplicationEvent>(sync: true);
    final observed = <String>[];
    final owner = eventsOwner(
      state: (event) => observed.add(event['type'] as String),
    );
    final received = <ApplicationEvent>[];
    final subscription = owner.stream.listen(received.add);
    await owner.attach(
      files: [files.stream, catalog.stream],
      sharing: sharing.stream,
    );
    files.add({'type': 'transfers.changed', 'revision': 3});
    catalog.add({
      'type': 'files.search.changed',
      'deviceId': 'device',
      'searchId': 'scan',
    });
    expect(observed, ['transfers.changed', 'files.search.changed']);
    sharing.add({
      'type': 'share.received',
      'deviceId': 'device',
      'data': {'shareId': 'share', 'status': 'ready'},
    });
    sharing.add({
      'type': 'share.consumed',
      'data': {'shareId': 'share'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(received.map((event) => event['sequence']), [1, 2, 3, 4]);
    expect(received.first['data'], {'revision': 3});
    expect(received[2]['deviceId'], 'device');
    expect(received[2]['data'], {'shareId': 'share', 'status': 'ready'});
    expect(observed, [
      'transfers.changed',
      'files.search.changed',
      'share.received',
      'share.consumed',
    ]);
    expect(owner.cursor, (sequence: 4, revision: 4));
    await owner.detach();
    files.add({'type': 'transfers.changed'});
    sharing.add({'type': 'share.received'});
    catalog.add({'type': 'files.search.changed'});
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(4));
    await subscription.cancel();
    await owner.close();
    await files.close();
    await sharing.close();
    await catalog.close();
  });

  test('帧只推进事件序列，呈现回执不触发业务策略或业务版本', () async {
    var changes = 0;
    final policies = <String>[];
    final owner = eventsOwner(
      changed: () => changes++,
      before: (event) => policies.add(event['type'] as String),
    );
    final received = <ApplicationEvent>[];
    final subscription = owner.stream.listen(received.add);
    owner.publish({'type': 'settings.changed'});
    owner.publish({'type': 'session.frame'});
    expect(owner.cursor, (sequence: 2, revision: 1));
    owner.emit({'type': 'state.resynced', 'data': snapshot(2, 'ready')});
    owner.emit({'type': 'session.presentation', 'data': 'visible'});
    await Future<void>.delayed(Duration.zero);
    expect(changes, 1);
    expect(policies, ['settings.changed', 'session.frame']);
    expect(owner.cursor, (sequence: 2, revision: 1));
    expect(received.map((event) => event['sequence']), [1, 2, null, null]);
    await subscription.cancel();
    await owner.close();
  });

  test('同步发布后继事实时，所有策略和呈现保持同一顺序', () async {
    final order = <String>[];
    var entered = false;
    var localCalls = 0;
    late ApplicationEvents owner;
    void observe(String phase, ApplicationEvent event) {
      order.add('$phase:${event['type']}');
      if (phase == 'before' && !entered) {
        entered = true;
        owner.publish({'type': 'B'});
      }
    }

    owner = eventsOwner(
      changed: () {
        observe('local', {'type': ++localCalls == 1 ? 'A' : 'B'});
      },
      accept: (event) {
        observe('accept', event);
        return true;
      },
      state: (event) => observe('state', event),
      before: (event) => observe('before', event),
      after: (event) => observe('after', event),
    );
    final received = <ApplicationEvent>[];
    final subscription = owner.stream.listen(received.add);
    owner.publish({'type': 'A'});
    await Future<void>.delayed(Duration.zero);
    expect(order, [
      for (final type in ['A', 'B'])
        for (final phase in ['local', 'accept', 'state', 'before', 'after'])
          '$phase:$type',
    ]);
    expect(received.map((event) => event['type']), ['A', 'B']);
    expect(received.map((event) => event['sequence']), [1, 2]);
    await subscription.cancel();
    await owner.close();
  });

  for (final failing in ['local', 'accept', 'before']) {
    test('$failing 抛错仍登记其他资源，错误可见且后续事实可以继续', () async {
      final failure = StateError(failing);
      final order = <String>[];
      var shouldFail = true;
      void observe(String phase) {
        order.add(phase);
        if (shouldFail && phase == failing) throw failure;
      }

      final owner = eventsOwner(
        changed: () => observe('local'),
        accept: (_) {
          observe('accept');
          return true;
        },
        state: (_) => observe('state'),
        before: (_) => observe('before'),
        after: (_) => observe('after'),
      );
      final errors = <Object>[];
      final received = <ApplicationEvent>[];
      final subscription = owner.stream.listen(
        received.add,
        onError: (Object error, StackTrace _) => errors.add(error),
      );
      owner.publish({'type': 'first'});
      expect(order, ['local', 'accept', 'state', 'before', 'after']);
      shouldFail = false;
      owner.publish({'type': 'second'});
      await Future<void>.delayed(Duration.zero);
      expect(errors, [same(failure)]);
      expect(received.map((event) => event['type']), [
        if (failing != 'accept') 'first',
        'second',
      ]);
      expect(received.last['sequence'], 2);
      await subscription.cancel();
      await owner.close();
    });
  }

  test('恢复期间分享终态照常登记，旧快照重读，媒体帧不会使核验饥饿', () async {
    final firstRead = Completer<StateJson>();
    var status = 'importing';
    var reads = 0;
    late ApplicationEvents owner;
    final recovery = StateRecovery(
      read: (_) async {
        if (++reads == 1) return firstRead.future;
        final state = snapshot(owner.cursor.sequence, status);
        owner.publish({'type': 'session.frame'});
        return state;
      },
      emit: (event) => owner.emit(event),
      isDisposed: () => false,
    );
    owner = eventsOwner(
      accept: recovery.accept,
      changed: recovery.noteLocalStateChange,
      state: (event) {
        if (event['type'] == 'share.changed') {
          status = (event['data'] as Map<String, dynamic>)['status'] as String;
        }
      },
    );
    final received = <ApplicationEvent>[];
    final subscription = owner.stream.listen(received.add);
    owner.publish({
      'type': 'share.changed',
      'data': {'status': 'importing'},
    });
    final recovering = recovery.refresh();
    owner.publish({
      'type': 'share.changed',
      'data': {'status': 'ready'},
    });
    firstRead.complete(snapshot(1, 'importing'));
    final verified = await recovering;
    expect(reads, 2);
    expect((verified['shares'] as List).single['status'], 'ready');
    expect(verified['sequence'], 2);
    expect(owner.cursor, (sequence: 3, revision: 2));
    expect(recovery.pending, isFalse);
    expect(recovery.accept({'type': 'share.changed', 'sequence': 2}), isFalse);
    owner.publish({'type': 'session.frame'});
    await Future<void>.delayed(Duration.zero);
    expect(
      received.where((event) => event['type'] == 'share.changed'),
      hasLength(1),
    );
    expect(
      received.singleWhere(
        (event) => event['type'] == 'state.resynced',
      )['data'],
      same(verified),
    );
    expect(received.last['sequence'], 4);
    recovery.dispose();
    await subscription.cancel();
    await owner.close();
  });

  test('平台异步错误可观察，分离后停止路由，关闭后忽略迟到事实', () async {
    final files = StreamController<ApplicationEvent>(sync: true);
    final platform = StreamController<dynamic>(sync: true);
    final failure = StateError('platform');
    var calls = 0;
    final owner = eventsOwner(
      platform: (_) async {
        calls++;
        throw failure;
      },
    );
    final errors = <Object>[];
    final subscription = owner.stream.listen(
      (_) {},
      onError: (Object error, StackTrace _) => errors.add(error),
    );
    await owner.attach(files: [files.stream], platform: platform.stream);
    platform.add({'type': 'platform.changed'});
    await Future<void>.delayed(Duration.zero);
    expect(errors, [same(failure)]);
    expect(owner.cursor, (sequence: 0, revision: 0));
    await owner.detach();
    platform.add({'type': 'platform.changed'});
    expect(calls, 1);
    await subscription.cancel();
    await owner.close();
    owner.publish({'type': 'late'});
    owner.emit({'type': 'late.presentation'});
    expect(owner.cursor, (sequence: 0, revision: 0));
    await files.close();
    await platform.close();
  });
}
