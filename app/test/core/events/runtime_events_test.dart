import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

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
        if (event['type'] == 'first') {
          events.publish({'type': 'session.frame'});
          events.publish({'type': 'second'});
        }
      },
      onLocalStateChanged: () => revisions++,
      beforePublish: (event) => delivered.add(event['type'] as String),
      afterState: (_) {},
      handlePlatform: (_) async {},
      isDisposed: () => false,
    );
    addTearDown(events.close);
    final received = <RuntimeEvent>[];
    final subscription = events.stream.listen(received.add);
    addTearDown(subscription.cancel);
    events.publish({'type': 'first'});
    final recovery = <RecoveryEvent>[
      const RecoveryStarted(),
      const RecoveryFailed('unverified'),
      const RecoveryStarted(),
      RecoveryCompleted(RuntimeSnapshot(sequence: 3, settings: Preferences())),
    ];
    for (final event in recovery) {
      events.emitRecovery(event);
    }
    await Future<void>.delayed(Duration.zero);
    expect(accepted, [
      (sequence: 1, telemetry: false),
      (sequence: 2, telemetry: true),
      (sequence: 3, telemetry: false),
    ]);
    expect(delivered, ['first', 'session.frame', 'second']);
    expect(received.take(3).map((event) => event['sequence']), [1, 2, 3]);
    expect(received.skip(3).map((event) => event['data']), recovery);
    expect(received.skip(3).map((event) => event['type']), [
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
    await events.attach(files: []);
    final source = StreamController<RuntimeEvent>.broadcast(sync: true);
    events.attachFileEvents(source.stream);
    final received = events.stream.first;
    source.add({'type': 'files.changed', 'path': '/sdcard'});
    expect(await received, {
      'type': 'files.changed',
      'path': '/sdcard',
      'data': {'path': '/sdcard'},
      'sequence': 1,
    });
    expect(events.cursor, (sequence: 1, revision: 1));
    await events.detach();
    expect(source.hasListener, isFalse);
    expect(() => events.attachFileEvents(source.stream), throwsStateError);
    await source.close();
    await events.close();
  });
}
