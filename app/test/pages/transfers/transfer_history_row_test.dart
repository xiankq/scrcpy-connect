import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_history_row.dart';
import 'package:scrcpy_connect/styles/theme.dart';

import '../../support/fixed_state.dart';

void main() {
  testWidgets('停止期间替换传输能力，旧轮询不再移除记录或刷新新页面', (tester) async {
    final previous = _Transfers();
    final replacement = _Transfers();
    var refreshes = 0;
    final devices = deviceListProvider.overrideWith(FixedDeviceList.new);
    final container = ProviderContainer(
      overrides: [fileTransfersProvider.overrideWithValue(previous), devices],
    );
    addTearDown(container.dispose);
    const task = FileTransferSnapshot(
      id: 'task',
      name: 'Photo',
      status: FileTransferStatus.running,
      canCancel: true,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: TransferHistoryRow(
              row: (
                id: 'task',
                task: task,
                members: const [task],
                batchId: null,
              ),
              refresh: () => refreshes++,
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('传输操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('停止并移除…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('停止并移除'));
    await tester.pump();
    expect(previous.cancelled, [const FileTransferTarget.task('task')]);
    expect(previous.reads, hasLength(1));
    container.updateOverrides([
      fileTransfersProvider.overrideWithValue(replacement),
      devices,
    ]);
    await tester.pump();
    previous.reads.single.complete(const FileTransferCollection());
    await tester.pump();
    expect(previous.removed, isEmpty);
    expect(replacement.cancelled, isEmpty);
    expect(replacement.removed, isEmpty);
    expect(refreshes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Transfers implements FileTransfers {
  final cancelled = <FileTransferTarget>[];
  final removed = <FileTransferTarget>[];
  final reads = <Completer<FileTransferCollection>>[];
  @override
  Future<void> cancelTransfer(FileTransferTarget target) async {
    cancelled.add(target);
  }

  @override
  Future<FileTransferCollection> readTransfers() {
    final result = Completer<FileTransferCollection>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<List<String>> removeTransfer(FileTransferTarget target) async {
    removed.add(target);
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
