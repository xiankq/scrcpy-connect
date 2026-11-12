import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/share_inbox_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';

void main() {
  late StreamController<Map<String, dynamic>> events;
  late _Shares source;
  late _Session dependencies;
  late ProviderContainer container;
  setUp(() {
    events = StreamController.broadcast(sync: true);
    source = _Shares();
    dependencies = _Session(events.stream);
    container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(dependencies),
        incomingSharesProvider.overrideWithValue(source),
      ],
    );
    container.listen(shareInboxProvider, (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await events.close();
  });

  test('分享能力独立换源后，旧读取和消费回执不能修改新队列', () async {
    final actions = container.read(shareInboxProvider.notifier);
    final reading = actions.load();
    final consuming = actions.consume('share');
    final replacement = _Shares();
    container.updateOverrides([
      appSessionProvider.overrideWithValue(dependencies),
      incomingSharesProvider.overrideWithValue(replacement),
    ]);
    await container.pump();
    expect(container.read(shareInboxProvider.notifier), same(actions));
    final refreshed = actions.load();
    replacement.reads.single.complete([
      const IncomingShare(shareId: 'share', status: .ready, text: 'new'),
    ]);
    await refreshed;
    source.reads.single.complete([
      const IncomingShare(shareId: 'old', status: .ready),
    ]);
    source.consumed.single.result.complete();
    await Future.wait([reading, consuming]);
    expect(container.read(shareInboxProvider).shares.single.text, 'new');
    expect(replacement.consumed, isEmpty);
  });

  test('迟到导入快照不覆盖终态，已消费记录也不会由读取或恢复重新加入', () async {
    final actions = container.read(shareInboxProvider.notifier);
    final loading = actions.load();
    events.add({
      'type': 'share.received',
      'data': {'shareId': 'share', 'status': 'ready', 'text': 'complete'},
    });
    source.reads.single.complete([
      const IncomingShare(shareId: 'share', status: .importing),
    ]);
    await loading;
    expect(container.read(shareInboxProvider).shares.single.text, 'complete');
    final late = actions.load();
    events.add({
      'type': 'share.consumed',
      'data': {'shareId': 'share'},
    });
    source.reads.last.complete([
      const IncomingShare(shareId: 'share', status: .ready),
    ]);
    await late;
    events.add({
      'type': 'state.resynced',
      'data': {
        'sequence': 1,
        'shares': [
          {'shareId': 'share', 'status': 'ready'},
        ],
      },
    });
    expect(container.read(shareInboxProvider).shares, isEmpty);
  });

  test('查找结果属于开始查询的能力代次，释放后也不再交付旧结果', () async {
    final actions = container.read(shareInboxProvider.notifier);
    final finding = actions.find('share');
    final replacement = _Shares();
    container.updateOverrides([
      appSessionProvider.overrideWithValue(dependencies),
      incomingSharesProvider.overrideWithValue(replacement),
    ]);
    await container.pump();
    source.reads.single.complete([
      const IncomingShare(shareId: 'share', status: .ready),
    ]);
    expect(await finding, isNull);
    final retired = actions.load();
    container.dispose();
    replacement.reads.single.complete([
      const IncomingShare(shareId: 'share', status: .ready),
    ]);
    await retired;
    expect(events.hasListener, isFalse);
  });
}

class _Shares implements IncomingShares {
  final reads = <Completer<List<IncomingShare>>>[];
  final consumed = <({String id, Completer<void> result})>[];
  @override
  Future<List<IncomingShare>> readIncomingShares() {
    final result = Completer<List<IncomingShare>>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<void> consumeShare(String id) {
    final result = Completer<void>();
    consumed.add((id: id, result: result));
    return result.future;
  }
}

class _Session implements AppSession {
  _Session(this.events);
  @override
  final Stream<Map<String, dynamic>> events;
  @override
  final initialState = AppState();
  @override
  bool get initialize => false;
  @override
  Future<void> Function()? get close => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
