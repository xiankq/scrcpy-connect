import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';
import 'package:scrcpy_connect/core/files/transfer_query_provider.dart';
import 'package:scrcpy_connect/pages/transfers/transfer_history_provider.dart';

import '../../support/fixed_state.dart';

void main() {
  test('页面按批次合并展示，设备改名只更新投影而不重查传输', () async {
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        deviceListProvider.overrideWith(_Devices.new),
        transferHistoryProvider.overrideWith((ref) async {
          reads++;
          return const FileTransferCollection(
            transfers: [
              FileTransferSnapshot(
                id: 'first',
                deviceId: 'device',
                batchId: 'batch',
              ),
              FileTransferSnapshot(
                id: 'second',
                deviceId: 'device',
                batchId: 'batch',
              ),
              FileTransferSnapshot(id: 'single', deviceId: 'device'),
            ],
            batches: [
              FileTransferBatch(batchId: 'batch', transferred: 4, total: 10),
            ],
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(transferHistoryRowsProvider, (_, _) {});
    await flushProviders(container);
    var rows = container.read(transferHistoryRowsProvider).requireValue;
    expect(rows, hasLength(2));
    expect(rows.first.members, hasLength(2));
    expect(rows.first.task.completedBytes, 4);
    expect(rows.first.task.sourceLabel, '旧名称');
    (container.read(deviceListProvider.notifier) as _Devices).rename('新名称');
    await container.pump();
    rows = container.read(transferHistoryRowsProvider).requireValue;
    expect(rows.first.task.sourceLabel, '新名称');
    expect(reads, 1);
  });
}

class _Devices extends DeviceListNotifier {
  @override
  DeviceListState build() => DeviceListState(
    devices: [const DeviceSnapshot(id: 'device', name: '旧名称')],
    loading: false,
  );

  void rename(String name) => state = state.copyWith(
    devices: [DeviceSnapshot(id: 'device', name: name)],
  );
}
