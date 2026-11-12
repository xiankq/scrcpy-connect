import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_operations.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';

void main() {
  test('独立装配传输和分享查询，不创建目录、搜索或变更执行器', () async {
    final transfers = _Transfers();
    final operations = FileOperations(
      search: () => throw StateError('不应创建搜索'),
      gallery: () => throw StateError('不应创建相册扫描'),
      directories: () => throw StateError('不应创建目录查询'),
      mutations: () => throw StateError('不应创建文件变更'),
      transfers: transfers,
      isDisposed: () => false,
      isStateUnverified: () => false,
      diagnostics: DiagnosticReporter(null),
    );
    final container = ProviderContainer(
      overrides: [
        fileTransfersProvider.overrideWithValue(operations),
        incomingSharesProvider.overrideWithValue(operations),
      ],
    );
    addTearDown(container.dispose);
    expect(
      (await container.read(fileTransfersProvider).readTransfers()).transfers,
      isEmpty,
    );
    expect(
      await container.read(incomingSharesProvider).readIncomingShares(),
      isEmpty,
    );
    expect(transfers.reads, 1);
  });

  test('准入拒绝先于按需创建变更执行器', () async {
    final operations = FileOperations(
      search: () => throw StateError('不应创建搜索'),
      gallery: () => throw StateError('不应创建相册扫描'),
      directories: () => throw StateError('不应创建目录查询'),
      mutations: () => throw StateError('不应创建文件变更'),
      transfers: _Transfers(),
      isDisposed: () => false,
      isStateUnverified: () => true,
      diagnostics: DiagnosticReporter(null),
    );
    await expectLater(
      operations.createDirectory('device', '/new'),
      throwsA(
        isA<RequestFailure>().having(
          (error) => error.code,
          'code',
          'state_unverified',
        ),
      ),
    );
  });
}

class _Transfers implements FileTransfers {
  int reads = 0;
  @override
  Future<FileTransferCollection> readTransfers() async {
    reads++;
    return const FileTransferCollection();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
