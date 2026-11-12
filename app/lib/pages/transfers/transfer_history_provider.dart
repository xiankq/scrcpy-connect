import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/files/transfer_query_provider.dart';

import 'models/transfer_history_entry.dart';
import 'transfer_history.dart';

/// 页面展示按选择分组，并随设备名称变化更新；执行状态仍归文件能力所有。
final transferHistoryRowsProvider =
    Provider.autoDispose<AsyncValue<List<TransferHistoryEntry>>>((ref) {
      final query = ref.watch(transferHistoryProvider);
      final devices = ref.watch(
        deviceListProvider.select((state) => state.devices),
      );
      return query.whenData((data) => transferHistoryRows(devices, data));
    });
