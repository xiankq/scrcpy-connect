import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/stores/app_store.dart';

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrcpy_connect/main.dart' as app;

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData = {'documentsAcceptanceComplete': false};
  final runId = 'interop-documents-${DateTime.now().millisecondsSinceEpoch}';
  var stage = 'starting';
  var prepared = false;
  var fileVerified = false;
  var directoryVerified = false;
  String? exportedFileName;
  String? exportedDirectoryName;
  developer.registerExtension('ext.connect.documents', (_, parameters) async {
    switch (parameters['action']) {
      case 'prepared':
        prepared = true;
      case 'fileVerified':
        fileVerified = true;
      case 'directoryVerified':
        directoryVerified = true;
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'stage': stage,
        'runId': runId,
        'exportedFileName': exportedFileName,
        'exportedDirectoryName': exportedDirectoryName,
      }),
    );
  });
  testWidgets(
    'real DocumentsUI file export and directory import/export preserve bytes and empty directories',
    (tester) async {
      await app.main();
      await tester.pump(const Duration(milliseconds: 300));
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appStoreProvider.notifier);
      String? activeOperation;
      String? managedSourceId;
      String? importedPath;
      Directory? local;
      Future<Json> request(String command, Json params) async {
        final id = '$runId-${DateTime.now().microsecondsSinceEpoch}';
        activeOperation = id;
        var completed = false;
        try {
          final result = await controller
              .request(command, {...params, 'operationId': id})
              .timeout(const Duration(minutes: 4));
          completed = true;
          return result;
        } finally {
          if (!completed) {
            await controller
                .request('documents.cancel', {'operationId': id})
                .timeout(const Duration(seconds: 10));
          }
          if (activeOperation == id) activeOperation = null;
        }
      }

      try {
        stage = 'prepare';
        await waitFor(
          tester,
          () => prepared,
          timeout: const Duration(seconds: 45),
          reason: 'Enable CONNECT_E2E_DOCUMENTS=1 on the host driver to prepare actual DocumentsUI files.',
        );
        final temporary = await getTemporaryDirectory();
        binding.reportData!['cachePaths'] = {
          'provided': temporary.path,
          'resolved': await temporary.resolveSymbolicLinks(),
        };
        local = await temporary.createTemp('$runId-');
        final source = File('${local.path}/export-$runId.txt');
        await source.writeAsString('native SAF export $runId\n', flush: true);
        stage = 'export-file';
        final file = await request('documents.export', {
          'localPath': source.path,
          'name': 'export-$runId.txt',
          'kind': 'file',
          'mime': 'text/plain',
          'conflict': 'ask',
        });
        binding.reportData!['fileExportResult'] = file;
        expect(file['status'], 'saved', reason: '${file['errors']}');
        expect(file['files'], 1);
        expect(file['bytes'], await source.length());
        exportedFileName = value(file, 'name');
        expect(exportedFileName, isNotEmpty);
        stage = 'file-saved';
        await waitFor(
          tester,
          () => fileVerified,
          timeout: const Duration(seconds: 35),
          reason: 'The host must read the actual exported system file and verify its bytes.',
        );
        stage = 'import-directory';
        final imported = await request('documents.importDirectory', {});
        managedSourceId = imported['managedSourceId'] as String?;
        binding.reportData!['importResult'] = {
          for (final key in [
            'status',
            'files',
            'directories',
            'bytes',
            'errors',
          ])
            key: imported[key],
        };
        expect(imported['status'], 'imported', reason: '${imported['errors']}');
        expect(managedSourceId, startsWith('document:'));
        expect(imported['files'], 1);
        expect(imported['directories'], greaterThanOrEqualTo(2));
        final cache = value(imported, 'localPath');
        importedPath = cache;
        expect(cache, isNotEmpty);
        expect(
          await File('$cache/sub/one.txt').readAsString(),
          'native SAF directory $runId\n',
        );
        expect(await Directory('$cache/empty').exists(), isTrue);
        stage = 'export-directory';
        final directory = await request('documents.export', {
          'localPath': cache,
          'name': 'restored-$runId',
          'kind': 'directory',
          'conflict': 'ask',
        });
        binding.reportData!['directoryExportResult'] = directory;
        expect(directory['status'], 'saved', reason: '${directory['errors']}');
        expect(directory['files'], 1);
        expect(directory['directories'], greaterThanOrEqualTo(2));
        exportedDirectoryName = value(directory, 'name');
        expect(exportedDirectoryName, isNotEmpty);
        stage = 'directory-saved';
        await waitFor(
          tester,
          () => directoryVerified,
          timeout: const Duration(seconds: 35),
          reason: 'The host must verify actual exported directory bytes and its empty subdirectory.',
        );
        stage = 'complete';
        expect(tester.takeException(), isNull);
      } finally {
        try {
          final id = activeOperation;
          if (id != null) {
            await controller
                .request('documents.cancel', {'operationId': id})
                .timeout(const Duration(seconds: 10));
          }
        } finally {
          try {
            if (managedSourceId != null) {
              await controller
                  .request('documents.cancel', {
                    'operationId': '$runId-release',
                    'managedSourceId': managedSourceId,
                  })
                  .timeout(const Duration(seconds: 10));
              if (importedPath != null) {
                expect(await Directory(importedPath).exists(), isFalse);
                binding.reportData!['managedSourceReleased'] = true;
              }
            }
          } finally {
            await local?.delete(recursive: true);
          }
        }
      }
      binding.reportData!['documentsAcceptanceComplete'] = true;
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}
