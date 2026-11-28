import 'dart:async';

import 'package:scrcpy_connect/core/devices/models/device_disconnect_requested.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override, ProviderBase;
import 'package:scrcpy_connect/core/activities/activities_provider.dart';
import 'package:scrcpy_connect/core/activities/activity_management_provider.dart';
import 'package:scrcpy_connect/core/control/control_capabilities_provider.dart';
import 'package:scrcpy_connect/core/control/video_quality_provider.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/core/media/audio_sources_provider.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';

import '../../support/fixed_state.dart';

import '../../support/video_events.dart';

void main() {
  for (final kind in _Kind.values) {
    group(kind.name, () {
      late _Source source;
      late StreamController<RuntimeEvent> events;
      late ProviderContainer container;
      setUp(() {
        source = _Source();
        events = StreamController<RuntimeEvent>.broadcast(sync: true);
        container = ProviderContainer(overrides: _overrides(source, events));
      });
      tearDown(() async {
        container.dispose();
        await events.close();
      });

      test('查询独立装配，共享读取，合并事件且丢弃在途过期回执', () async {
        final provider = kind.provider;
        final first = container.listen(provider, (_, _) {});
        final second = container.listen(provider, (_, _) {});
        await flushProviders(container);
        expect(source.reads, hasLength(1));
        events.add(
          const DeviceDisconnectRequested('other').toApplicationEvent(),
        );
        events.add(videoChange().toApplicationEvent());
        await flushProviders(container);
        expect(source.reads, hasLength(1));
        for (var index = 0; index < 10; index++) {
          events.add(
            const DeviceDisconnectRequested('device').toApplicationEvent(),
          );
          await flushProviders(container);
        }
        expect(source.reads, hasLength(1));
        source.reads[0].complete(kind.value(1));
        await flushProviders(container);
        expect(source.reads, hasLength(2));
        expect(container.read(provider).isLoading, isTrue);
        expect(container.read(provider).hasValue, isFalse);
        final latest = kind.value(2);
        source.reads[1].complete(latest);
        await flushProviders(container);
        expect(container.read(provider).requireValue, latest);
        events.add(RuntimeEvent(const RecoveryStarted()));
        expect(container.read(provider).isLoading, isTrue);
        expect(container.read(provider).value, latest);
        await flushProviders(container);
        source.reads[2].complete(kind.value(3));
        await flushProviders(container);
        first.close();
        await flushProviders(container);
        expect(events.hasListener, isTrue);
        second.close();
        await flushProviders(container);
        expect(events.hasListener, isFalse);
      });

      test('能力换源、连接换代和恢复准入均撤销旧读取', () async {
        final provider = kind.provider;
        container.listen(provider, (_, _) {});
        await flushProviders(container);
        final replacement = _Source();
        container.updateOverrides(_overrides(replacement, events));
        await flushProviders(container);
        final latest = kind.value(2);
        replacement.reads.single.complete(latest);
        await flushProviders(container);
        source.reads.single.complete(kind.value(1));
        await flushProviders(container);
        expect(container.read(provider).requireValue, latest);
        container.updateOverrides(
          _overrides(replacement, events, connectionId: 'next'),
        );
        await flushProviders(container);
        expect(replacement.reads, hasLength(2));
        container.updateOverrides(
          _overrides(
            replacement,
            events,
            connectionId: 'next',
            recovering: true,
          ),
        );
        await flushProviders(container);
        expect(replacement.reads, hasLength(3));
        replacement.reads[1].complete(kind.value(3));
        await flushProviders(container);
        expect(container.read(provider).isLoading, isTrue);
        final recovered = kind.value(4);
        replacement.reads[2].complete(recovered);
        await flushProviders(container);
        expect(container.read(provider).requireValue, recovered);
      });

      test('失败保留错误与原展示数据，只有明确刷新才重试', () async {
        final provider = kind.provider;
        container.listen(provider, (_, _) {});
        await flushProviders(container);
        final previous = kind.value(1);
        source.reads.single.complete(previous);
        await flushProviders(container);
        events.add(
          const DeviceDisconnectRequested('device').toApplicationEvent(),
        );
        await flushProviders(container);
        final failure = StateError('unavailable');
        source.reads[1].completeError(failure);
        await flushProviders(container);
        expect(container.read(provider).error, same(failure));
        expect(container.read(provider).value, previous);
        await flushProviders(container);
        expect(source.reads, hasLength(2));
        container.invalidate(provider);
        await flushProviders(container);
        expect(source.reads, hasLength(3));
        source.reads[2].complete(kind.value(2));
        await flushProviders(container);
        expect(container.read(provider).hasError, isFalse);
      });
    });
  }
}

enum _Kind {
  audio,
  quality,
  activities;

  ProviderBase<AsyncValue<Object>> get provider => switch (this) {
    audio => audioSourcesProvider(deviceId: 'device'),
    quality => videoQualityProvider(deviceId: 'device'),
    activities => activitiesProvider(deviceId: 'device'),
  };

  Object value(int version) => switch (this) {
    audio => <DeviceAudioSnapshot>[
      DeviceAudioSnapshot(
        sourceId: 'audio-$version',
        deviceId: 'device',
        generation: version,
        name: 'Audio',
        status: DeviceAudioStatus.playing,
        createdAt: version,
      ),
    ],
    quality => VideoQualityOptions(
      current: VideoQuality(
        maxSize: version,
        maxFps: 60,
        bitRate: 4000000,
        codec: VideoCodec.h264,
      ),
      codecs: const [],
      activeSessions: const [],
    ),
    activities => ActivityCollection(
      activities: [
        ActivitySnapshot(
          target: ActivityTarget.session('session-$version'),
          deviceId: 'device',
          deviceName: 'Device',
          name: 'Activity $version',
          status: 'running',
          stopImpact: '',
        ),
      ],
      pendingApplications: const [],
    ),
  };
}

List<Override> _overrides(
  _Source source,
  StreamController<RuntimeEvent> events, {
  String connectionId = 'connection',
  bool recovering = false,
}) => [
  remoteAudioProvider.overrideWithValue(source),
  videoQualityControlProvider.overrideWithValue(source),
  activityManagementProvider.overrideWithValue(source),
  runtimeEventsProvider.overrideWithValue(events.stream),
  deviceReadinessProvider('device').overrideWithValue(
    DeviceReadiness(connectionId: connectionId, recovering: recovering),
  ),
];

class _Source implements RemoteAudio, VideoQualityControl, ActivityManagement {
  final reads = <Completer<Object>>[];
  Future<T> _read<T>() {
    final result = Completer<Object>();
    reads.add(result);
    return result.future.then((value) => value as T);
  }

  @override
  Future<List<DeviceAudioSnapshot>> readAudioSources({String? deviceId}) =>
      _read();
  @override
  Future<VideoQualityOptions> readVideoQualityOptions(String deviceId) =>
      _read();
  @override
  Future<ActivityCollection> readActivities({String? deviceId}) => _read();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
