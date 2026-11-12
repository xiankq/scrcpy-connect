import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_event.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';

import 'models/file_change.dart';

export 'models/file_change.dart';

final fileChangesProvider = Provider<Stream<FileChange>>((ref) {
  return ref
      .watch(runtimeEventsProvider)
      .map((event) {
        final type = event.type;
        final data = event.data;
        final kind = data is FileTransferEvent
            ? FileChangeKind.transfer
            : data is RecoveryEvent
            ? FileChangeKind.recovery
            : type.startsWith('device.') ||
                  type == 'devices.changed' ||
                  type == 'connections.stopped'
            ? FileChangeKind.connection
            : null;
        if (kind == null) return null;
        final deviceId = event.deviceId;
        return FileChange(kind, deviceId: deviceId);
      })
      .where((event) => event != null)
      .cast<FileChange>();
});
