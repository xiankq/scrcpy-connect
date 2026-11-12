import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';
import 'package:scrcpy_connect/widgets/file_transfer_labels.dart';

import 'models/transfer_history_entry.dart';

/// 每次选择在列表出现一次，批次子项放在详情中。
List<TransferHistoryEntry> transferHistoryRows(
  List<DeviceSnapshot> devices,
  FileTransferCollection data,
) {
  final groups = <String, List<FileTransferSnapshot>>{};
  for (final raw in data.transfers) {
    final task = transferView(devices, raw);
    final batch = task.batchId;
    groups
        .putIfAbsent(
          batch == null || batch.isEmpty ? 'task:${task.id}' : 'batch:$batch',
          () => [],
        )
        .add(task);
  }
  final summaries = {for (final batch in data.batches) batch.batchId: batch};
  return [
    for (final group in groups.entries)
      (() {
        final members = group.value;
        final roots = members
            .where((task) => task.parentId?.isNotEmpty != true)
            .toList();
        final first = roots.isEmpty ? members.first : roots.first;
        final batch = first.batchId;
        final summary = summaries[batch];
        final multiple = members.length > 1;
        var displayed = first;
        if (multiple && summary != null) {
          displayed = displayed.copyWith(
            deviceId: summary.deviceId,
            direction: summary.direction,
            destinationScope: summary.destinationScope,
            status: summary.status,
            itemCount: summary.itemCount,
            canCancel: summary.canCancel,
          );
        }
        displayed = displayed.copyWith(
          name:
              '${first.name}${roots.length > 1
                  ? ' 等 ${members.length} 项'
                  : multiple
                  ? ' · ${members.length} 项'
                  : ''}',
          completedBytes: multiple
              ? summary?.transferred ?? 0
              : first.completedBytes,
          totalBytes: multiple ? summary?.total : first.totalBytes,
        );
        return (
          id: group.key,
          task: displayed,
          members: members,
          batchId: batch?.isNotEmpty == true ? batch : null,
        );
      })(),
  ];
}
