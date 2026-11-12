import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/queries/coalesced_query.dart';

import 'video_quality.dart';
import 'control_capabilities_provider.dart';

export 'video_quality.dart';

part 'video_quality_provider.g.dart';

final _readProvider = Provider.autoDispose
    .family<CoalescedQuery<VideoQualityOptions>, String>((ref, deviceId) {
      final source = ref.watch(videoQualityControlProvider);
      ref.watch(deviceReadinessProvider(deviceId));
      final events = ref.watch(runtimeEventsProvider).where((event) {
        final type = event['type'];
        if (type is! String || type == 'session.frame') return false;
        if (type.startsWith('state.resync')) return true;
        final data = event['data'];
        final owner =
            event['deviceId'] ?? (data is Map ? data['deviceId'] : null);
        if (owner != null && owner != deviceId) {
          return false;
        }
        return type == 'devices.changed' ||
            type.startsWith('device.') ||
            type == 'connections.stopped' ||
            type == 'settings.changed' ||
            type == 'video.capabilities.changed';
      });
      final query = CoalescedQuery(
        () => source.readVideoQualityOptions(deviceId),
        invalidations: events,
      );
      ref.onDispose(() => unawaited(query.close()));
      return query;
    });

final _revisionProvider = StreamProvider.autoDispose.family(
  (ref, String deviceId) => ref.watch(_readProvider(deviceId)).changes,
);

@Riverpod(retry: _noRetry)
Future<VideoQualityOptions> videoQuality(Ref ref, {required String deviceId}) {
  final query = ref.watch(_readProvider(deviceId));
  ref.watch(_revisionProvider(deviceId));
  return query.read();
}

Duration? _noRetry(int _, Object _) => null;
