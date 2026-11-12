import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';

import 'models/file_change.dart';

export 'models/file_change.dart';

final fileChangesProvider = Provider<Stream<FileChange>>((ref) {
  return ref
      .watch(runtimeEventsProvider)
      .map((event) {
        final type = event['type'];
        if (type is! String) return null;
        final kind = type.startsWith('transfers.')
            ? FileChangeKind.transfer
            : type.startsWith('state.resync')
            ? FileChangeKind.recovery
            : type.startsWith('device.') ||
                  type == 'devices.changed' ||
                  type == 'connections.stopped'
            ? FileChangeKind.connection
            : type == 'files.directory.changed'
            ? FileChangeKind.directory
            : null;
        if (kind == null) return null;
        final data = event['data'];
        final deviceId =
            event['deviceId'] ?? (data is Map ? data['deviceId'] : null);
        final path = data is Map ? data['path'] : null;
        return FileChange(
          kind,
          deviceId: deviceId is String ? deviceId : null,
          path: path is String ? path : null,
        );
      })
      .where((event) => event != null)
      .cast<FileChange>();
});
