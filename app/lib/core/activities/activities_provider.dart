import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/queries/coalesced_query.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';

import 'activity_management.dart';
import 'activity_management_provider.dart';

export 'activity_management.dart';

part 'activities_provider.g.dart';

final _readProvider = Provider.autoDispose
    .family<CoalescedQuery<ActivityCollection>, String?>((ref, deviceId) {
      final source = ref.watch(activityManagementProvider);
      if (deviceId != null) ref.watch(deviceReadinessProvider(deviceId));
      final events = ref.watch(runtimeEventsProvider).where((event) {
        if (event['data'] is RecoveryEvent) return true;
        final type = event['type'];
        if (type is! String || type == 'session.frame') return false;
        final data = event['data'];
        final owner =
            event['deviceId'] ?? (data is Map ? data['deviceId'] : null);
        if (deviceId != null && owner != null && owner != deviceId) {
          return false;
        }
        return type == 'devices.changed' ||
            type.startsWith('device.') ||
            type == 'connections.stopped' ||
            type.startsWith('audio.') ||
            type.startsWith('session.') ||
            type.startsWith('observation.') ||
            type.startsWith('activities.') ||
            type.startsWith('transfers.') ||
            type.startsWith('calls.') ||
            type == 'companion.stopped' ||
            type == 'call.incoming';
      });
      final query = CoalescedQuery(
        () => source.readActivities(deviceId: deviceId),
        invalidations: events,
      );
      ref.onDispose(() => unawaited(query.close()));
      return query;
    });

final _revisionProvider = StreamProvider.autoDispose.family(
  (ref, String? deviceId) => ref.watch(_readProvider(deviceId)).changes,
);

@Riverpod(retry: _noRetry)
Future<ActivityCollection> activities(Ref ref, {String? deviceId}) {
  final query = ref.watch(_readProvider(deviceId));
  ref.watch(_revisionProvider(deviceId));
  return query.read();
}

Duration? _noRetry(int _, Object _) => null;
