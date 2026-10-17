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
import 'package:scrcpy_connect/pages/file_details/file_details_page.dart';
import 'package:scrcpy_connect/pages/receive_content/receive_content_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  var stage = 'waiting-fixture';
  String? runId;
  String? hostError;
  final acknowledgements = <String>{};
  binding.reportData = {'contentDeliveryComplete': false};
  developer.registerExtension('ext.connect.contentDelivery', (_, args) async {
    if (args['action'] == 'fixture' && runId == null) {
      final candidate = args['runId'];
      if (candidate != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(candidate)) {
        runId = candidate;
      }
    }
    if (runId != null && args['runId'] == runId) {
      if (args['error'] != null) {
        hostError = 'Independent Android check failed.';
      }
      if (args['action'] case final String action) acknowledgements.add(action);
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'stage': stage, 'runId': runId}),
    );
  });
  testWidgets('remote originals reach system storage and an external app', (
    tester,
  ) async {
    expect(address, isNotEmpty);
    expect(port, inInclusiveRange(1, 65535));
    await app.main();
    await waitFor(
      tester,
      () => find.byType(Scaffold).evaluate().isNotEmpty,
      reason: 'Production app must initialize.',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConnectApp)),
    );
    final controller = container.read(appControllerProvider.notifier);
    await waitFor(
      tester,
      () =>
          !controller.snapshot().loading &&
          !controller.snapshot().reconciliationPending,
      reason: 'Production bootstrap must settle.',
    );
    Future<Json> request(String command, [Json params = const {}]) => controller
        .request(command, params)
        .timeout(const Duration(seconds: 45));
    Future<void> checkpoint(
      String next,
      String action, {
      bool cleanup = false,
    }) async {
      stage = next;
      final deadline = DateTime.now().add(const Duration(seconds: 75));
      // A system picker can suspend Flutter frame scheduling.
      while (!acknowledgements.contains(action) &&
          (cleanup || hostError == null) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        acknowledgements.contains(action),
        isTrue,
        reason: 'Independent host must acknowledge $next: $hostError',
      );
      if (!cleanup && hostError != null) throw StateError(hostError!);
    }

    await waitFor(
      tester,
      () => runId != null,
      reason: 'Host must prepare this isolated original.',
    );
    final name = 'connect-delivery-$runId.txt';
    final path = '/sdcard/Download/$name';
    final expected = utf8.encode('Connect delivery $runId\n字节核验\n');
    binding.reportData!['fixtureRunId'] = runId;
    final initialDevices = objects((await request('devices.list'))['devices']);
    String? deviceId;
    var created = false;
    var connectedBefore = false;
    try {
      deviceId = responseDeviceId(
        await request('devices.add', {
          'address': address,
          'port': port,
          'transport': 'tcp',
          'attemptId': 'content-delivery-$runId',
        }),
      );
      created = !initialDevices.any((device) => device['id'] == deviceId);
      connectedBefore = initialDevices.any(
        (device) => device['id'] == deviceId && device['status'] == 'connected',
      );
      await request('devices.connect', {'deviceId': deviceId});
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go(FileDetailsRoute(deviceId: deviceId!, path: path).location);
      await waitFor(
        tester,
        () => find.byType(FileDetailsPage).evaluate().isNotEmpty,
        reason: 'Actual route must re-read remote file metadata.',
      );
      await tester.tap(find.text('取回原文件'));
      await waitFor(
        tester,
        () => find.byType(ReceiveContentPage).evaluate().isNotEmpty,
        reason: 'A queued original must open its exact task.',
      );
      final task = tester
          .widget<ReceiveContentPage>(find.byType(ReceiveContentPage))
          .task;
      final transferId = value(task, 'id', value(task, 'transferId'));
      final downloadDeadline = DateTime.now().add(const Duration(seconds: 30));
      Json transfer = {};
      while (DateTime.now().isBefore(downloadDeadline)) {
        transfer = await request('transfers.get', {'transferId': transferId});
        if (transfer['canExport'] == true) break;
        if ([
          'failed',
          'cancelled',
          'interrupted',
          'conflict',
        ].contains(transfer['status'])) {
          throw StateError(
            'Original pull did not publish: ${transfer['status']} ${transfer['error']}',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        transfer['canExport'],
        true,
        reason: 'A complete original must publish safely.',
      );
      await waitFor(
        tester,
        () =>
            find.byType(ReceiveContentPage).evaluate().isNotEmpty &&
            find.text('选择系统位置并保存').evaluate().isNotEmpty,
        reason: 'Real queued pull must finish in its own save page.',
      );
      binding.reportData!['actualSavePage'] = true;
      final cache = File(value(transfer, 'localPath'));
      expect(await cache.readAsBytes(), expected);
      await tester.ensureVisible(find.text('选择系统位置并保存'));
      await tester.tap(find.text('选择系统位置并保存'));
      await checkpoint('cancel-picker', 'picker-cancelled');
      await waitFor(
        tester,
        () => find.text('本次系统保存已取消').evaluate().isNotEmpty,
        reason: 'Cancelling the system picker must not report saved.',
      );
      expect(await cache.readAsBytes(), expected);
      expect(find.text('已保存到系统位置'), findsNothing);
      binding.reportData!['pickerCancellationPreservedCache'] = true;
      await tester.ensureVisible(find.text('重新选择系统位置'));
      await tester.tap(find.text('重新选择系统位置'));
      await checkpoint('save-picker', 'saved');
      await waitFor(
        tester,
        () => find.text('已保存到系统位置').evaluate().isNotEmpty,
        reason: 'Real provider copy and close must confirm saved.',
      );
      expect(await cache.readAsBytes(), expected);
      binding.reportData!['exportedBytes'] = expected.length;
      await tester.pump(const Duration(milliseconds: 300));
      await checkpoint('saved-product-page', 'saved-product-captured');
      binding.reportData!['savedProductPageCaptured'] = true;
      router.pop();
      await waitFor(
        tester,
        () => find.byType(FileDetailsPage).evaluate().isNotEmpty,
        reason: 'Return to the same original.',
      );
      await tester.tap(find.text('交给系统分享'));
      await waitFor(
        tester,
        () =>
            find.byType(ReceiveContentPage).evaluate().isNotEmpty &&
            find.text('原文件已准备好').evaluate().isNotEmpty,
        reason: 'A separate real pull must prepare the original for share.',
      );
      binding.reportData!['actualSharePage'] = true;
      await tester.pump(const Duration(milliseconds: 300));
      await checkpoint('share-product-page', 'share-product-captured');
      binding.reportData!['shareProductPageCaptured'] = true;
      final shareButton = find.widgetWithText(FilledButton, '交给系统分享');
      await tester.ensureVisible(shareButton);
      await tester.tap(shareButton);
      await checkpoint('share-picker', 'shared');
      await waitFor(
        tester,
        () => find.text('已交给系统选择的应用，请在接收应用核对。').evaluate().isNotEmpty,
        reason:
            'The actual share result must keep its bounded handoff meaning.',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await checkpoint('shared-product-page', 'shared-product-captured');
      binding.reportData!['sharedProductPageCaptured'] = true;
      // Host reads the actual receiving app's bytes before returning us.
      expect(tester.takeException(), isNull);
    } finally {
      try {
        await checkpoint('awaiting-cleanup', 'cleanup', cleanup: true);
        binding.reportData!['fixtureCleanupAcknowledged'] = true;
      } finally {
        if (deviceId != null && created) {
          await request('devices.forget', {'deviceId': deviceId});
        } else if (deviceId != null && !connectedBefore) {
          await request('devices.disconnect', {'deviceId': deviceId});
        }
      }
    }
    stage = 'complete';
    binding.reportData!['contentDeliveryComplete'] = true;
  }, timeout: const Timeout(Duration(minutes: 7)));
}
