import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/document_export/document_export_page.dart';
import 'package:scrcpy_connect/pages/document_export/widgets/document_conflict_panel.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/services/file_actions.dart';

import 'product_flow_test.dart' show waitFor;

/// Run with test_driver/document_conflict.dart. The host controls only the real
/// Android picker and isolated public files; every product action uses app.main.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var stage = 'waiting-fixture';
  String? runId, hostError, operationId, conflictId, savedName;
  int? connectPort;
  final acknowledgements = <String>{};
  binding.reportData = {
    'documentConflictComplete': false,
    'realSubsequentApplyConflictVerified': false,
  };
  developer.registerExtension('ext.connect.documentConflict', (_, args) async {
    final candidate = args['runId'];
    if (candidate != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(candidate)) {
      if (args['action'] == 'fixture' && runId == null) {
        final port = int.tryParse(args['connectPort'] ?? '');
        if (port != null && port > 0 && port <= 65535) {
          runId = candidate;
          connectPort = port;
        }
      }
      if ((runId == null || runId == candidate) && args['error'] != null) {
        hostError = 'Independent Android fixture failed.';
      }
      if (runId == candidate) {
        if (args['action'] case final String action) {
          acknowledgements.add(action);
        }
      }
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'stage': stage,
        'runId': runId,
        'operationId': operationId,
        'conflictId': conflictId,
        'savedName': savedName,
      }),
    );
  });

  testWidgets('system directory conflicts use the actual shared export page', (
    tester,
  ) async {
    await app.main();
    await waitFor(
      tester,
      () => find.byType(Scaffold).evaluate().isNotEmpty,
      reason: 'The production app must initialize.',
    );
    final controller = ProviderScope.containerOf(
      tester.element(find.byType(ConnectApp)),
    ).read(appControllerProvider.notifier);
    await waitFor(
      tester,
      () =>
          !controller.snapshot().loading &&
          !controller.snapshot().reconciliationPending,
      reason: 'Production bootstrap must settle before the fixture.',
    );
    Future<Json> request(String command, [Json params = const {}]) => controller
        .request(command, params)
        .timeout(const Duration(seconds: 45));
    Future<void> checkpoint(
      String next,
      String acknowledgement, {
      bool cleanup = false,
    }) async {
      stage = next;
      final deadline = DateTime.now().add(const Duration(seconds: 85));
      // DocumentsUI may suspend Flutter frame scheduling. VM-service handshakes
      // therefore wait on wall time while the host operates the OS picker.
      while (!acknowledgements.contains(acknowledgement) &&
          (cleanup || hostError == null) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        acknowledgements.contains(acknowledgement),
        true,
        reason: 'Independent host must acknowledge $next: $hostError',
      );
      if (!cleanup && hostError != null) throw StateError(hostError!);
    }

    Future<void> tapProduct(Finder action) async {
      await waitFor(
        tester,
        () {
          final elements = action.evaluate().toList();
          if (elements.length != 1) return false;
          return switch (elements.single.widget) {
            ButtonStyleButton(:final onPressed) => onPressed != null,
            CheckboxListTile(:final onChanged) => onChanged != null,
            _ => true,
          };
        },
        reason: 'The actual product action must finish loading and be enabled.',
      );
      await tester.ensureVisible(action);
      await tester.pump(const Duration(milliseconds: 300));
      expect(action.hitTestable(), findsOneWidget);
      await tester.tap(action.hitTestable());
    }

    await waitFor(
      tester,
      () => runId != null || hostError != null,
      reason:
          'Host must prepare an isolated source and the public destination.',
    );
    if (hostError != null) throw StateError(hostError!);
    final run = runId!;
    final report = binding.reportData!;
    report['fixtureRunId'] = run;
    final initialDevices = objects((await request('devices.list'))['devices']);
    Directory? cacheOwner;
    String? deviceId, transferId, localPath;
    var deviceCreated = false, connectedBefore = false;
    final transferIds = <String>[];
    late GoRouter router;
    Json source() => {
      'sourceId': 'transfer:$transferId',
      'localPath': localPath,
      'kind': 'directory',
    };
    Future<Json> record() async =>
        jsonObject((await request('delivery.get', source()))['record']);
    Future<Json> waitReceipt(
      String expectedStatus, {
      bool cleanup = false,
    }) async {
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      Json current = {};
      while (DateTime.now().isBefore(deadline)) {
        current = await record();
        if (current['status'] == expectedStatus) {
          if (cleanup) return current;
          final result = jsonObject(current['result']);
          final counts = [
            result['files'],
            result['directories'],
            result['bytes'],
          ];
          final partialLabel = counts.any((count) => count is num && count > 0)
              ? '部分内容已保存，请核对'
              : result['partialDestinationPossible'] == false &&
                    counts.every((count) => count is num && count == 0)
              ? '本次未保存内容'
              : '保存未完成，请核对';
          final label = switch (expectedStatus) {
            'saved' => '已保存到系统位置',
            'partial' => partialLabel,
            'cancelled' => '本次系统保存已取消',
            _ => '',
          };
          await waitFor(
            tester,
            () =>
                find.byType(DocumentExportPage).evaluate().isEmpty ||
                (label.isNotEmpty && find.text(label).evaluate().isNotEmpty),
            reason: 'The real save page must render the durable receipt.',
          );
          return current;
        }
        if (!cleanup && hostError != null) throw StateError(hostError!);
        if (cleanup) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        } else {
          await tester.pump(const Duration(milliseconds: 150));
        }
      }
      throw StateError(
        'Save receipt did not reach $expectedStatus: ${current['status']}',
      );
    }

    Future<Json> waitConflict() async {
      await waitFor(
        tester,
        () =>
            find.byType(DocumentConflictPanel).evaluate().isNotEmpty &&
            find.text('存在同名项目').evaluate().isNotEmpty,
        reason: 'The actual shared Flutter conflict panel must be visible.',
      );
      final current = await record();
      operationId = value(current, 'operationId');
      expect(operationId, isNotEmpty);
      final pending = jsonObject(
        (await request('documents.conflict.get', {
          'operationId': operationId,
        }))['pending'],
      );
      expect(pending['operationId'], operationId);
      expect(pending['name'], 'bundle');
      expect(pending['choices'], ['keepBoth', 'skip', 'cancel']);
      expect(pending['replacementSupported'], false);
      conflictId = value(pending, 'conflictId');
      expect(conflictId, isNotEmpty);
      expect(find.text('此位置暂不支持替换同名内容；已有文件会保留。'), findsOneWidget);
      await tester.ensureVisible(find.byType(DocumentConflictPanel));
      await tester.pump(const Duration(milliseconds: 250));
      return pending;
    }

    Future<void> startSave(
      String mode, {
      bool additionalCopy = false,
      bool first = false,
    }) async {
      if (additionalCopy) {
        await tapProduct(find.widgetWithText(OutlinedButton, '再保存一份'));
        await waitFor(
          tester,
          () => find.text('再保存一份？').evaluate().isNotEmpty,
          reason:
              'An additional saved copy must require explicit confirmation.',
        );
        await tapProduct(find.widgetWithText(FilledButton, '选择新位置'));
      } else {
        await tapProduct(
          find.widgetWithText(FilledButton, first ? '选择系统位置并保存' : '重新选择系统位置'),
        );
      }
      await checkpoint('$mode-picker', '$mode-tree-selected');
      await waitConflict();
    }

    Future<void> openExport() async {
      DocumentExportRoute(taskId: transferId!)
          .push<void>(tester.element(find.byType(Scaffold).first));
      await waitFor(
        tester,
        () {
          final page = find.byType(DocumentExportPage);
          if (page.evaluate().length != 1) return false;
          final route = ModalRoute.of(tester.element(page));
          return route?.isCurrent == true &&
              route?.animation?.status == AnimationStatus.completed;
        },
        reason:
            'The formal export route must load the real completed transfer.',
      );
    }

    try {
      // The host's forward terminates at the existing target AVD adbd. This
      // fixture tests filesystem UI, not pairing or USB authorization.
      deviceId = responseDeviceId(
        await request('devices.add', {
          'address': '10.0.2.2',
          'port': connectPort,
          'transport': 'tcp',
          'attemptId': 'document-conflict-$run',
        }),
      );
      deviceCreated = !initialDevices.any((device) => device['id'] == deviceId);
      connectedBefore = initialDevices.any(
        (device) => device['id'] == deviceId && device['status'] == 'connected',
      );
      await request('devices.connect', {'deviceId': deviceId});
      cacheOwner = await receivedDirectory();
      final queued = await request('files.pull', {
        'deviceId': deviceId,
        'path': '/sdcard/Download/connect-doc-conflict-$run/bundle',
        'destination': '${cacheOwner.path}/bundle',
        'destinationScope': 'privateCache',
        'conflict': 'ask',
      });
      transferId = value(queued, 'transferId');
      transferIds.addAll(
        (queued['transferIds'] as List<Object?>).whereType<String>(),
      );
      expect(transferId, isNotEmpty);
      stage = 'pulling';
      Json transfer = {};
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(deadline)) {
        transfer = await request('transfers.get', {'transferId': transferId});
        if (transfer['canExport'] == true) break;
        if ([
          'failed',
          'cancelled',
          'interrupted',
          'conflict',
        ].contains(transfer['status'])) {
          throw StateError(
            'Actual directory pull failed: ${transfer['status']} ${transfer['error']}',
          );
        }
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(transfer['canExport'], true);
      expect(transfer['kind'], 'directory');
      localPath = value(transfer, 'localPath');
      expect(localPath, '${cacheOwner.path}/bundle');
      expect(
        await File('$localPath/one.txt').readAsBytes(),
        utf8.encode('document conflict one $run\n汉字\n'),
      );
      expect(await File('$localPath/nested/two.bin').readAsBytes(), [
        0,
        1,
        2,
        127,
        128,
        255,
      ]);
      expect(await Directory('$localPath/empty').exists(), true);
      report['realDirectoryPull'] = true;
      router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      await openExport();
      report['actualProductionExportRoute'] = true;

      await startSave('keepBoth', first: true);
      final apply = find.widgetWithText(CheckboxListTile, '应用于本次保存的后续同名项目');
      await tapProduct(apply);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<CheckboxListTile>(apply).value, true);
      report['applyRemainingSelected'] = true;
      await checkpoint('keepBoth-panel', 'keepBoth-panel-captured');
      await tapProduct(find.widgetWithText(FilledButton, '保留两份'));
      final saved = jsonObject((await waitReceipt('saved'))['result']);
      expect(saved['files'], 2);
      expect(saved['directories'], 3);
      savedName = value(saved, 'name');
      expect(savedName, matches(r'^bundle \([a-f0-9]{32}\)$'));
      // The durable delivery receipt intentionally projects only its public
      // fields. The host checks the exact new name and both directory trees.
      await waitFor(
        tester,
        () => find.text('已保存到系统位置').evaluate().isNotEmpty,
        reason: 'Only the provider copy and successful close may report saved.',
      );
      await checkpoint('keepBoth-saved', 'keepBoth-verified');
      report['keepBothOriginalPreserved'] = true;

      await startSave('skip', additionalCopy: true);
      await checkpoint('skip-panel', 'skip-panel-captured');
      final panel = find.byType(DocumentConflictPanel);
      await tapProduct(
        find.descendant(
          of: panel,
          matching: find.widgetWithText(OutlinedButton, '跳过此项'),
        ),
      );
      final skipped = jsonObject((await waitReceipt('partial'))['result']);
      expect(skipped['skipped'], 1);
      expect(skipped['files'], 0);
      expect(skipped['directories'], 0);
      expect(skipped['bytes'], 0);
      expect(skipped['partialDestinationPossible'], false);
      expect(find.text('本次未保存内容'), findsOneWidget);
      expect(find.text('部分内容已保存，请核对'), findsNothing);
      report['emptyPartialReceiptRendered'] = true;
      await checkpoint('skip-finished', 'skip-verified');
      report['skipExistingFilePreserved'] = true;

      await startSave('cancel');
      await checkpoint('cancel-panel', 'cancel-panel-captured');
      await tapProduct(
        find.descendant(
          of: find.byType(DocumentConflictPanel),
          matching: find.widgetWithText(TextButton, '取消本次保存'),
        ),
      );
      final cancelled = jsonObject((await waitReceipt('cancelled'))['result']);
      expect(cancelled['files'], 0);
      expect(cancelled['directories'], 0);
      expect(cancelled['bytes'], 0);
      expect(cancelled['partialDestinationPossible'], false);
      await checkpoint('cancel-finished', 'cancel-verified');
      report['cancelNoWrite'] = true;

      await startSave('leave');
      final abandoned = await waitConflict();
      await checkpoint('leave-panel', 'leave-panel-captured');
      router.pop();
      await tester.pump(const Duration(milliseconds: 350));
      await waitReceipt('cancelled');
      await checkpoint('leave-finished', 'leave-verified');
      report['leaveCancelled'] = true;
      await openExport();
      await startSave('fresh');
      final fresh = await waitConflict();
      expect(fresh['operationId'], isNot(abandoned['operationId']));
      expect(
        await request('documents.conflict.resolve', {
          'operationId': abandoned['operationId'],
          'conflictId': abandoned['conflictId'],
          'choice': 'cancel',
        }),
        {'resolved': false},
      );
      final current = (await request('documents.conflict.get', {
        'operationId': fresh['operationId'],
        'conflictId': fresh['conflictId'],
      }))['pending'];
      expect(current, fresh);
      report['staleDecisionRejected'] = true;
      await checkpoint('fresh-panel', 'fresh-panel-captured');
      await tapProduct(
        find.descendant(
          of: find.byType(DocumentConflictPanel),
          matching: find.widgetWithText(OutlinedButton, '跳过此项'),
        ),
      );
      await waitReceipt('partial');
      await checkpoint('fresh-finished', 'fresh-verified');
      report['freshOperationUnaffected'] = true;
      report['hostFilesystemVerified'] = true;
      expect(tester.takeException(), isNull);
    } finally {
      var writesStopped = false;
      try {
        if (transferId != null && localPath != null) {
          // A failure may happen while a new picker is still waiting, before
          // waitConflict learns its operation ID. Read this source's real owner.
          final current = await record();
          final currentId = value(current, 'operationId');
          if (currentId.isNotEmpty) {
            await request('documents.cancel', {'operationId': currentId});
            if (current['status'] == 'pending') {
              await waitReceipt('cancelled', cleanup: true);
            }
          }
        }
        for (final id in transferIds) {
          final task = await request('transfers.get', {'transferId': id});
          if (![
            'completed',
            'failed',
            'cancelled',
            'skipped',
          ].contains(task['status'])) {
            await request('transfers.cancel', {'transferId': id});
            final deadline = DateTime.now().add(const Duration(seconds: 15));
            Json stopped = {};
            while (DateTime.now().isBefore(deadline)) {
              stopped = await request('transfers.get', {'transferId': id});
              if ([
                'completed',
                'failed',
                'cancelled',
                'skipped',
              ].contains(stopped['status'])) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(
              ['completed', 'failed', 'cancelled', 'skipped'],
              contains(stopped['status']),
              reason:
                  'An owned transfer must stop before its cache is removed.',
            );
          }
        }
        writesStopped = cacheOwner == null || transferId != null;
      } finally {
        try {
          await checkpoint('cleanup', 'cleanup-confirmed', cleanup: true);
          report['fixtureCleanupAcknowledged'] = true;
        } finally {
          if (deviceId != null && deviceCreated) {
            await request('devices.forget', {'deviceId': deviceId});
          } else if (deviceId != null && !connectedBefore) {
            await request('devices.disconnect', {'deviceId': deviceId});
          }
          if (writesStopped &&
              cacheOwner != null &&
              await cacheOwner.exists()) {
            // Only the dedicated receivedDirectory created above is owned here.
            // Production transfer/save history is retained; no state files or
            // unrelated cache entries are removed by this fixture.
            await cacheOwner.delete(recursive: true);
            report['scopedCacheRemoved'] = true;
          } else if (cacheOwner != null) {
            report['cacheRetainedReason'] =
                'Transfer admission or stop outcome was not confirmed.';
          }
        }
      }
    }
    stage = 'complete';
    report['documentConflictComplete'] = true;
  }, timeout: const Timeout(Duration(minutes: 10)));
}
