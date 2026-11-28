import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/files/file_operations.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';

void main() {
  test('只读传输和分享时不创建目录、搜索、相册或变更执行器', () async {
    final operations = FileOperations(
      search: () => throw StateError('不应创建搜索'),
      gallery: () => throw StateError('不应创建相册扫描'),
      directories: () => throw StateError('不应创建目录查询'),
      mutations: () => throw StateError('不应创建文件变更'),
      transfers: _Transfers(),
      isDisposed: () => false,
      isStateUnverified: () => false,
      diagnostics: DiagnosticReporter(null),
    );
    expect((await operations.readTransfers()).transfers, isEmpty);
    expect(await operations.readIncomingShares(), isEmpty);
  });
}

class _Transfers implements FileTransfers {
  @override
  Future<FileTransferCollection> readTransfers() async =>
      const FileTransferCollection();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
