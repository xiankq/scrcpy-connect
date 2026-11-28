import 'dart:async';

import 'package:scrcpy_connect/core/settings/models/settings_changed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/media/models/recovered_video_session.dart';
import 'package:scrcpy_connect/core/recovery/runtime_snapshot_reader.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

import '../../support/video_events.dart';

void main() {
  late RuntimeEvents events;
  setUp(() {
    events = RuntimeEvents(
      acceptState: ({required sequence, required telemetry}) => true,
      onState: (_) {},
      beforePublish: (_) {},
      afterState: (_) {},
      handlePlatform: (_) async {},
      isDisposed: () => false,
    );
    addTearDown(events.close);
  });

  test('业务变化作废跨等待读取，媒体帧只推进序列且不会使快照饥饿', () async {
    final first = Completer<List<RecoveredVideoSession>>();
    var reads = 0;
    var settings = Preferences(appearance: .light);
    final reader = RuntimeSnapshotReader(
      readCursor: () => events.cursor,
      readDevices: () => [],
      readSessions: () {
        reads++;
        return reads == 1 ? first.future : Future.value([]);
      },
      readAudio: () => [],
      readShares: () async {
        events.publishEvent(videoChange());
        return [];
      },
      readObservations: () => [],
      readSettings: () => settings,
    );
    final reading = reader.readSnapshot();
    settings = Preferences(appearance: .dark);
    events.publishEvent(SettingsChanged(settings));
    first.complete([]);
    final snapshot = await reading;
    expect(reads, 2);
    expect(snapshot.settings.appearance, Appearance.dark);
    expect(snapshot.sequence, events.cursor.sequence);
    expect(events.cursor.revision, 1);
    expect(snapshot.sequence, 3);
  });

  test('持续业务变化有界失败，不交付混合版本', () async {
    var reads = 0;
    final reader = RuntimeSnapshotReader(
      readCursor: () => events.cursor,
      readDevices: () => [],
      readSessions: () async => [],
      readAudio: () => [],
      readShares: () async {
        reads++;
        events.publishEvent(SettingsChanged(Preferences()));
        return [];
      },
      readObservations: () => [],
      readSettings: Preferences.new,
    );
    await expectLater(
      reader.readSnapshot(),
      throwsA(
        isA<RequestFailure>().having((e) => e.code, 'code', 'state_busy'),
      ),
    );
    expect(reads, 4);
  });
}
