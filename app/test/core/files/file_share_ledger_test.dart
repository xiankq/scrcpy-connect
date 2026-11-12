import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_share_ledger.dart';
import 'package:scrcpy_connect/core/files/models/incoming_share.dart';
import 'package:scrcpy_connect/core/files/models/share_inbox_event.dart';

void main() {
  const shareId = '00000000-0000-4000-8000-000000000001';
  late Directory cache;
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('share-ledger-events-');
  });
  tearDown(() async => cache.delete(recursive: true));

  test('分享事实只在提交后交付，观察者失败不撤销来源，消费不改写旧投影', () async {
    final events = <ShareInboxEvent>[];
    final committed = <String>[];
    final store = await FileShareLedger.open(
      cacheDirectory: cache,
      onChanged: (event) {
        events.add(event);
        if (event is ShareReceived) {
          final raw = jsonDecode(
            File('${cache.path}/incoming/$shareId/.share').readAsStringSync(),
          ) as Map<String, dynamic>;
          committed.add(raw['status'] as String);
        }
        throw StateError('呈现观察者退出');
      },
    );
    await store.reserve(shareId, text: '内容');
    expect(events, isEmpty);
    await store.complete(shareId, []);
    expect(committed, ['ready']);
    final received = events.single as ShareReceived;
    expect(received.share.status, IncomingShareStatus.ready);
    expect(received.share.text, '内容');
    expect((await store.pending()).single, received.share);

    await store.consume(shareId);
    expect(
      events.last,
      isA<ShareConsumed>().having((e) => e.shareId, '来源', shareId),
    );
    expect(await store.pending(), isEmpty);
    expect(received.share.status, IncomingShareStatus.ready);
    expect(received.share.text, '内容');
    expect(() => received.share.errors.add('迟到错误'), throwsUnsupportedError);

    final reopened = await FileShareLedger.open(cacheDirectory: cache);
    expect(await reopened.pending(), isEmpty);
  });

  test('未确认持久提交不发布就绪事实，原账本封存并保留磁盘来源', () async {
    var rejectCommit = false;
    final events = <ShareInboxEvent>[];
    final store = await FileShareLedger.open(
      cacheDirectory: cache,
      onChanged: events.add,
      commitFile: (temporary, destination) async {
        if (rejectCommit) throw const FileSystemException('提交被中断');
        await temporary.rename(destination.path);
      },
    );
    await store.reserve(shareId, text: '保留');
    rejectCommit = true;
    await expectLater(
      store.complete(shareId, []),
      throwsA(
        isA<FileFailure>().having((e) => e.code, '状态', 'share_storage_unknown'),
      ),
    );
    expect(events, isEmpty);
    final raw = jsonDecode(
      await File('${cache.path}/incoming/$shareId/.share').readAsString(),
    ) as Map<String, dynamic>;
    expect(raw['status'], 'importing');
    expect(raw['text'], '保留');
    await expectLater(
      store.complete(shareId, []),
      throwsA(
        isA<FileFailure>().having((e) => e.code, '封存', 'share_storage_unknown'),
      ),
    );
    expect(events, isEmpty);
  });
}
