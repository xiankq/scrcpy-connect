import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/queries/coalesced_query.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';

import 'remote_audio.dart';
import 'media_capabilities_provider.dart';

export 'remote_audio.dart';

part 'audio_sources_provider.g.dart';

final _readProvider = Provider.autoDispose
    .family<CoalescedQuery<List<DeviceAudioSnapshot>>, String?>((
      ref,
      deviceId,
    ) {
      final source = ref.watch(remoteAudioProvider);
      if (deviceId != null) ref.watch(deviceReadinessProvider(deviceId));
      final events = ref.watch(runtimeEventsProvider).where((event) {
        if (event.data is RecoveryEvent) return true;
        final type = event.type;
        if (event.telemetry) return false;
        final owner = event.deviceId;
        if (deviceId != null && owner != null && owner != deviceId) {
          return false;
        }
        return type == 'devices.changed' ||
            type.startsWith('device.') ||
            type == 'connections.stopped' ||
            type.startsWith('audio.') ||
            type.startsWith('session.');
      });
      final query = CoalescedQuery(
        () => source.readAudioSources(deviceId: deviceId),
        invalidations: events,
      );
      ref.onDispose(() => unawaited(query.close()));
      return query;
    });

final _revisionProvider = StreamProvider.autoDispose.family(
  (ref, String? deviceId) => ref.watch(_readProvider(deviceId)).changes,
);

@Riverpod(retry: _noRetry)
Future<List<DeviceAudioSnapshot>> audioSources(Ref ref, {String? deviceId}) {
  final query = ref.watch(_readProvider(deviceId));
  ref.watch(_revisionProvider(deviceId));
  return query.read();
}

Duration? _noRetry(int _, Object _) => null;
