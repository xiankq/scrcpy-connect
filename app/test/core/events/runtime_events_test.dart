import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/files/models/file_search_changed.dart';
import 'package:scrcpy_connect/core/files/models/share_inbox_event.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

import '../../fixtures/video_events.dart';

void main() {
  test('重入发布保持业务与帧序列，类型化恢复回执不改变业务水位或重入策略', () async {
    final accepted = <({int sequence, bool telemetry})>[];
    final delivered = <String>[];
    var revisions = 0;
    late RuntimeEvents events;
    events = RuntimeEvents(
      acceptState: ({required sequence, required telemetry}) {
        accepted.add((sequence: sequence, telemetry: telemetry));
        return true;
      },
      onState: (event) {
        if (event.type == 'first') {
          events.publishEvent(videoChange());
          events.publishEvent(const _Event('second'));
        }
      },
      onLocalStateChanged: () => revisions++,
      beforePublish: (event) => delivered.add(event.type),
      afterState: (_) {},
      handlePlatform: (_) async {},
      isDisposed: () => false,
    );
    addTearDown(events.close);
    final received = <RuntimeEvent>[];
    final subscription = events.stream.listen(received.add);
    addTearDown(subscription.cancel);
    events.publishEvent(const _Event('first'));
    final recovery = <RecoveryEvent>[
      const RecoveryStarted(),
      const RecoveryFailed('unverified'),
      const RecoveryStarted(),
      RecoveryCompleted(RuntimeSnapshot(sequence: 3, settings: Preferences())),
    ];
    for (final event in recovery) {
      events.emitEvent(event);
    }
    await Future<void>.delayed(Duration.zero);
    expect(accepted, [
      (sequence: 1, telemetry: false),
      (sequence: 2, telemetry: true),
      (sequence: 3, telemetry: false),
    ]);
    expect(delivered, ['first', 'session.frame', 'second']);
    expect(received.take(3).map((event) => event.sequence), [1, 2, 3]);
    expect(received.skip(3).map((event) => event.data), recovery);
    expect(received.skip(3).map((event) => event.type), [
      'state.resync',
      'state.resync.failed',
      'state.resync',
      'state.resynced',
    ]);
    expect(events.cursor, (sequence: 3, revision: 2));
    expect(revisions, 2);
  });

  test('按需附着文件查询仍使用唯一事件序列，退休后拒绝新增订阅', () async {
    final events = RuntimeEvents(
      acceptState: ({required sequence, required telemetry}) => true,
      onState: (_) {},
      beforePublish: (_) {},
      afterState: (_) {},
      handlePlatform: (_) async {},
      isDisposed: () => false,
    );
    final sharing = StreamController<ShareInboxEvent>.broadcast(sync: true);
    await events.attach(files: [], sharing: sharing.stream);
    final source = StreamController<AppEvent>.broadcast(sync: true);
    events.attachFileEvents(source.stream);
    final received = events.stream.first;
    const change = FileSearchChanged((
      deviceId: 'device',
      searchId: 'search',
      path: '/sdcard',
    ));
    source.add(change);
    final delivery = await received;
    expect(delivery.data, same(change));
    expect(delivery.deviceId, 'device');
    expect(delivery.sequence, 1);
    expect(events.cursor, (sequence: 1, revision: 1));
    final consumed = events.stream.first;
    const consumption = ShareConsumed('share');
    sharing.add(consumption);
    final consumptionDelivery = await consumed;
    expect(consumptionDelivery.data, same(consumption));
    expect(consumptionDelivery.sequence, 2);
    expect(events.cursor, (sequence: 2, revision: 2));
    await events.detach();
    expect(source.hasListener, isFalse);
    expect(sharing.hasListener, isFalse);
    expect(() => events.attachFileEvents(source.stream), throwsStateError);
    await source.close();
    await sharing.close();
    await events.close();
  });
}

final class _Event extends AppEvent {
  const _Event(this.type);
  @override
  final String type;
}
