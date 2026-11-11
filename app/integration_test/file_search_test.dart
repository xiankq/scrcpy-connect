import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/files/details/devices_workspace_files_details_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/search/devices_workspace_files_search_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/models/connection_validation.dart';

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData = {'fileSearchComplete': false};
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  testWidgets(
    'actual nested file search filters, opens, and distinguishes duplicate names',
    (tester) async {
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      await app.main();
      await waitFor(
        tester,
        () => find.byType(Scaffold).evaluate().isNotEmpty,
        reason: 'Production app must initialize.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appStoreProvider.notifier);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
        reason: 'Production bootstrap must settle.',
      );
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 45));
      final devices = objects((await request('devices.list'))['devices']);
      final root =
          '/sdcard/Download/connect-search-${DateTime.now().microsecondsSinceEpoch}';
      final local = await (await getTemporaryDirectory()).createTemp(
        'search-fixture-',
      );
      String? deviceId;
      var created = false;
      var connectedBefore = false;
      var fixtureCreated = false;
      try {
        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'transport': 'tcp',
            'attemptId': root.split('/').last,
          }),
        );
        created = !devices.any((device) => device['id'] == deviceId);
        connectedBefore = devices.any(
          (device) =>
              device['id'] == deviceId && device['status'] == 'connected',
        );
        await request('devices.connect', {'deviceId': deviceId});
        await request('files.mkdir', {'deviceId': deviceId, 'path': root});
        fixtureCreated = true;
        binding.reportData!.addAll({
          'fixtureRoot': root,
          'fixtureCreated': true,
        });
        await request('files.mkdir', {
          'deviceId': deviceId,
          'path': '$root/工作',
        });
        await request('files.mkdir', {
          'deviceId': deviceId,
          'path': '$root/报告资料',
        });
        final original = await File('${local.path}/报告.txt')
            .writeAsString('真实搜索原件\n', flush: true);
        final pushed = await request('files.push', {
          'deviceId': deviceId,
          'items': [
            {'source': original.path, 'destination': '$root/报告.txt'},
            {'source': original.path, 'destination': '$root/工作/报告.txt'},
          ],
          'conflict': 'ask',
        });
        for (final id in pushed['transferIds'] as List) {
          final deadline = DateTime.now().add(const Duration(seconds: 40));
          Json task = {};
          do {
            task = await request('transfers.get', {'transferId': id});
            if (task['status'] == 'completed') break;
            if ([
              'failed',
              'conflict',
              'cancelled',
              'interrupted',
            ].contains(task['status'])) {
              throw StateError('Fixture upload did not complete: $task');
            }
            await tester.pump(const Duration(milliseconds: 100));
          } while (DateTime.now().isBefore(deadline));
          expect(task['status'], 'completed');
        }
        final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
        router.go(FilesRoute(deviceId: deviceId!, path: root).location);
        await waitFor(
          tester,
          () => find.byType(FilesPage).evaluate().isNotEmpty,
          reason: 'The chosen remote directory must open.',
        );
        await tester.tap(find.byTooltip('搜索子文件夹'));
        await waitFor(
          tester,
          () => find.byType(FileSearchPage).evaluate().isNotEmpty,
          reason: 'The file page must expose recursive search.',
        );
        await tester.pump(const Duration(milliseconds: 400));
        final searchPage = find.byType(FileSearchPage);
        await tester.enterText(
          find.descendant(of: searchPage, matching: find.byType(TextField)),
          '报告',
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, '搜索'));
        await waitFor(
          tester,
          () => find.textContaining('已完成搜索').evaluate().isNotEmpty,
          reason: 'Actual recursive search must finish with a complete result.',
        );
        expect(find.text('报告.txt'), findsNWidgets(2));
        expect(find.text('报告资料'), findsOneWidget);
        expect(find.textContaining('$root/工作'), findsOneWidget);
        binding.reportData!['actualNestedNames'] = true;
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot('file-search-results');
        await tester.ensureVisible(find.text('文档'));
        await tester.tap(find.text('文档'));
        await tester.pump();
        expect(find.textContaining('条件已修改'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, '搜索'));
        await waitFor(
          tester,
          () =>
              find.textContaining('已完成搜索').evaluate().isNotEmpty &&
              find.text('报告资料').evaluate().isEmpty,
          reason: 'An explicit new document query must replace the earlier all-types result.',
        );
        expect(find.text('报告.txt'), findsNWidgets(2));
        binding.reportData!['actualTypeFilter'] = true;
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(find.textContaining('已完成搜索'), findsOneWidget);
        await binding.takeScreenshot('file-search-documents');
        // 匹配向用户显示的权威路径，不依赖字节格式，再由真实路由重新查询文件。
        final row = find.ancestor(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip && widget.message == '$root/工作/报告.txt',
          ),
          matching: find.byType(ListTile),
        );
        expect(
          row,
          findsOneWidget,
          reason: 'Same-named files need distinct source directories.',
        );
        await tester.ensureVisible(row);
        await tester.tap(row);
        await waitFor(
          tester,
          () => find.byType(FileDetailsPage).evaluate().isNotEmpty,
          reason: 'The selected result must resolve its real file again.',
        );
        expect(
          tester
              .widget<FileDetailsPage>(find.byType(FileDetailsPage))
              .file['path'],
          '$root/工作/报告.txt',
        );
        binding.reportData!['actualDetailRevalidated'] = true;
        expect(tester.takeException(), isNull);
      } finally {
        try {
          if (deviceId != null && fixtureCreated) {
            await request('files.delete', {
              'deviceId': deviceId,
              'paths': [root],
            });
            final parent = await request('files.list', {
              'deviceId': deviceId,
              'path': '/sdcard/Download',
            });
            expect(
              objects(parent['entries']).any((entry) => entry['path'] == root),
              false,
            );
            binding.reportData!['fixtureRemoved'] = true;
          }
        } finally {
          try {
            await local.delete(recursive: true);
          } finally {
            if (deviceId != null && created) {
              await request('devices.forget', {'deviceId': deviceId});
            } else if (deviceId != null && !connectedBefore) {
              await request('devices.disconnect', {'deviceId': deviceId});
            }
          }
        }
      }
      binding.reportData!['fileSearchComplete'] = true;
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
