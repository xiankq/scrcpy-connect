import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/incoming_share/incoming_share_page.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = String.fromEnvironment('CONNECT_E2E_PORT');
  const secondAddress = String.fromEnvironment(
    'CONNECT_E2E_SECOND_ADDRESS',
    defaultValue: address,
  );
  const secondPort = String.fromEnvironment('CONNECT_E2E_SECOND_PORT');
  final runId = 'share-target-${DateTime.now().microsecondsSinceEpoch}';
  final directory = '/sdcard/Download/connect-$runId';
  final destination = '$directory/共享 图片.png';
  var stage = 'starting';
  var serialA = '', serialB = '';
  String? hostError;
  final acknowledgements = <String>{};
  developer.registerExtension('ext.connect.incomingShareTarget', (
    _,
    parameters,
  ) async {
    final action = parameters['action'];
    if (action != null) acknowledgements.add(action);
    if (action == 'failed') hostError = parameters['message'];
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'stage': stage,
        'runId': runId,
        'directory': directory,
        'destination': destination,
        'serialA': serialA,
        'serialB': serialB,
      }),
    );
  });
  testWidgets(
    'an external PNG stays bound to explicitly selected A after global focus moves to B',
    (tester) async {
      binding.reportData = {'runId': runId};
      expect(
        address,
        isNotEmpty,
        reason: 'Configure the real target A address.',
      );
      expect(port, isNotEmpty, reason: 'Configure the real target A TCP port.');
      expect(secondAddress, isNotEmpty);
      expect(
        secondPort,
        isNotEmpty,
        reason: 'Configure the real target B TCP port.',
      );
      await app.main();
      await waitFor(
        tester,
        () => find.byType(ConnectApp).evaluate().isNotEmpty,
        reason: 'The actual Flutter application must initialize.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appStoreProvider.notifier);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
        reason: 'Preserve state only after production bootstrap has settled.',
      );
      Future<Json> request(String command, [Json params = const {}]) async =>
          (await tester.runAsync(
            () => controller
                .request(command, params)
                .timeout(const Duration(seconds: 35)),
          ))!;
      await tester.runAsync(controller.loadSettings);
      final originalSettings = {...controller.snapshot().settings};
      final originalFocused = controller.snapshot().focusedDeviceId;
      final initialDevices = objects(
        (await request('devices.list'))['devices'],
      );
      final added = <String>{};
      String? shareId;

      Future<void> host(
        String next,
        String acknowledgement, {
        bool cleanup = false,
      }) async {
        stage = next;
        await waitFor(
          tester,
          () =>
              acknowledgements.contains(acknowledgement) ||
              (!cleanup && hostError != null),
          timeout: const Duration(seconds: 60),
          reason: 'Independent ADB host must finish $next.',
        );
        if (!cleanup && hostError != null) throw StateError(hostError!);
        expect(acknowledgements, contains(acknowledgement));
      }

      Future<List<Json>> ownTransfers() async =>
          objects((await request('transfers.list'))['transfers'])
              .where(
                (task) => value(task, 'destination').startsWith('$directory/'),
              )
              .toList();

      Future<String> connect(String targetAddress, String targetPort) async {
        final id = responseDeviceId(
          await request('devices.add', {
            'address': targetAddress,
            'port': int.parse(targetPort),
            'transport': 'tcp',
          }),
        );
        expect(id, isNotNull);
        added.add(id!);
        await request('devices.connect', {'deviceId': id});
        return id;
      }

      try {
        // 焦点具有真实剪贴板和音频副作用，下方恢复这些偏好。
        await tester.runAsync(
          () => controller.updateSetting('deviceSettings', <String, dynamic>{}),
        );
        expect(
          objects((await request('sharing.pending'))['shares']),
          isEmpty,
          reason: 'Use a controller with no pre-existing incoming shares.',
        );
        final a = await connect(address, port);
        final b = await connect(secondAddress, secondPort);
        expect(
          a,
          isNot(b),
          reason: 'A and B must be two distinct real targets.',
        );
        await tester.runAsync(controller.refreshDevices);
        final devices = controller.snapshot().devices;
        final deviceA = devices.singleWhere((device) => device['id'] == a);
        final deviceB = devices.singleWhere((device) => device['id'] == b);
        expect(deviceA['status'], 'connected');
        expect(deviceB['status'], 'connected');
        serialA = value(deviceA, 'serial');
        serialB = value(deviceB, 'serial');
        expect(serialA, isNotEmpty);
        expect(serialB, isNotEmpty);
        // 模拟器克隆可能共用 ro.serialno；宿主创建的唯一目录项将各公共连接绑定到独立 ADB 目标。
        await host('prepare', 'prepared');
        final entriesA = objects(
          (await request('files.list', {
            'deviceId': a,
            'path': directory,
          }))['entries'],
        );
        final entriesB = objects(
          (await request('files.list', {
            'deviceId': b,
            'path': directory,
          }))['entries'],
        );
        expect(entriesA.map((entry) => entry['name']), ['target-a.marker']);
        expect(entriesB.map((entry) => entry['name']), ['target-b.marker']);
        binding.reportData!['independentEndpointMarkersVerified'] = true;
        await tester.runAsync(() => controller.focusDevice(a));
        expect(controller.snapshot().focusedDeviceId, a);
        stage = 'send-image';
        Json received = {};
        final importDeadline = DateTime.now().add(const Duration(seconds: 40));
        while (DateTime.now().isBefore(importDeadline)) {
          if (hostError != null) throw StateError(hostError!);
          final pending = objects((await request('sharing.pending'))['shares']);
          if (pending.isNotEmpty) {
            expect(pending, hasLength(1));
            received = pending.single;
            shareId = value(received, 'shareId');
            if (['ready', 'error'].contains(received['status'])) break;
          }
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(
          received['status'],
          'ready',
          reason: 'The external granted PNG must import.',
        );
        expect(value(received, 'text'), isEmpty);
        final files = objects(received['files']);
        expect(files, hasLength(1));
        expect(files.single['name'], '共享 图片.png');
        final expected = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSb8AAAAASUVORK5CYII=',
        );
        expect(
          await File(value(files.single, 'localPath')).readAsBytes(),
          expected,
        );
        await tester.runAsync(controller.loadPendingShares);
        await waitFor(
          tester,
          () => find.byType(IncomingSharePage).evaluate().isNotEmpty,
          reason: 'The external Android share must open the live product page.',
        );
        final page = find.byType(IncomingSharePage);
        final choiceA = find.descendant(
          of: page,
          matching: find.byWidgetPredicate(
            (widget) => widget is ChoiceRow<String> && widget.value == a,
          ),
        );
        final scrollable = find
            .descendant(of: page, matching: find.byType(Scrollable))
            .first;
        Future<void> reveal(Finder finder, double delta) async {
          await tester.scrollUntilVisible(
            finder,
            delta,
            scrollable: scrollable,
            maxScrolls: 20,
          );
          await tester.ensureVisible(finder);
          await tester.pump(const Duration(milliseconds: 200));
        }

        await waitFor(
          tester,
          () =>
              ModalRoute.of(tester.element(page))?.animation?.status ==
              AnimationStatus.completed,
          reason:
              'The actual share route must finish entering before scrolling.',
        );
        final submit = find.widgetWithText(FilledButton, '确认提交');
        await reveal(submit, 250);
        expect(
          tester.widget<FilledButton>(submit).onPressed,
          isNull,
          reason:
              'Global focus alone must not preselect an incoming-share target.',
        );
        await reveal(choiceA, -250);
        await tester.tap(choiceA);
        await tester.pump(const Duration(milliseconds: 200));
        final pathField = find.descendant(
          of: page,
          matching: find.byType(TextField),
        );
        await reveal(pathField, 250);
        await tester.enterText(pathField, directory);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() => controller.focusDevice(b));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          controller.snapshot().focusedDeviceId,
          b,
          reason: 'Use the public controller to really move global focus to B.',
        );
        await reveal(choiceA, -250);
        expect(tester.widget<ChoiceRow<String>>(choiceA).groupValue, a);
        await reveal(submit, 250);
        expect(
          find.text('本次目标：${deviceName(deviceA)} · $directory'),
          findsOneWidget,
        );
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot(
          'incoming-share-a-selected-global-focus-b',
        );
        binding.reportData!.addAll({
          'pageTargetStayedA': true,
          'globalFocusMovedToB': true,
        });
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        await tester.tap(submit);
        await waitFor(
          tester,
          () => page.evaluate().isEmpty,
          reason: 'Submit must consume this share and leave its page.',
        );
        final transferDeadline = DateTime.now().add(
          const Duration(seconds: 60),
        );
        List<Json> transfers = [];
        while (DateTime.now().isBefore(transferDeadline)) {
          transfers = await ownTransfers();
          expect(
            transfers.length,
            lessThanOrEqualTo(1),
            reason: 'One PNG must queue one task.',
          );
          if (transfers.isNotEmpty) {
            expect(transfers.single['deviceId'], a);
            expect(transfers.single['destination'], destination);
            expect(transfers.single['direction'], 'push');
            expect(
              ['failed', 'conflict', 'cancelled', 'interrupted'],
              isNot(contains(transfers.single['status'])),
              reason: 'The real file push must succeed.',
            );
            if (transfers.single['status'] == 'completed') break;
          }
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(transfers, hasLength(1));
        expect(transfers.single['status'], 'completed');
        final transferId = value(transfers.single, 'id');
        for (var reload = 0; reload < 2; reload++) {
          await tester.runAsync(controller.loadPendingShares);
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            objects((await request('sharing.pending'))['shares'])
                .where((share) => share['shareId'] == shareId),
            isEmpty,
          );
          expect(page, findsNothing);
          final after = await ownTransfers();
          expect(
            after,
            hasLength(1),
            reason: 'A consumed share must not queue another upload.',
          );
          expect(after.single['id'], transferId);
        }
        expect(controller.snapshot().focusedDeviceId, b);
        binding.reportData!.addAll({
          'transferId': transferId,
          'consumedWithoutResubmit': true,
        });
        await host('verify', 'verified');
        expect(tester.takeException(), isNull);
      } finally {
        try {
          // 精确上传仍在活动时，不能删除宿主夹具。
          for (final task in await ownTransfers()) {
            if ([
              'queued',
              'running',
              'finalizing',
              'cancelling',
            ].contains(task['status'])) {
              await request('transfers.cancel', {'transferId': task['id']});
            }
          }
          final settleDeadline = DateTime.now().add(
            const Duration(seconds: 35),
          );
          while ((await ownTransfers()).any(
            (task) => [
              'queued',
              'running',
              'finalizing',
              'cancelling',
            ].contains(task['status']),
          )) {
            if (DateTime.now().isAfter(settleDeadline)) {
              throw StateError('Fixture upload did not settle before cleanup.');
            }
            await tester.pump(const Duration(milliseconds: 200));
          }
          if (shareId != null) {
            await tester.runAsync(() => controller.consumeShare(shareId!));
          }
        } finally {
          try {
            await host('cleanup', 'cleaned', cleanup: true);
            binding.reportData!['fixtureCleaned'] = true;
          } finally {
            Object? restoreFailure;
            Future<void> restore(Future<void> Function() operation) async {
              try {
                await operation();
              } catch (error) {
                restoreFailure ??= error;
              }
            }

            await restore(() async {
              await tester.runAsync(
                () => controller.focusDevice(originalFocused),
              );
            });
            for (final id in added) {
              final before = initialDevices
                  .where((device) => device['id'] == id)
                  .firstOrNull;
              await restore(() async {
                if (before == null) {
                  await request('devices.forget', {'deviceId': id});
                } else if (before['status'] != 'connected') {
                  await request('devices.disconnect', {'deviceId': id});
                }
              });
            }
            await restore(() async {
              await tester.runAsync(controller.refreshDevices);
            });
            await restore(() async {
              await tester.runAsync(
                () => controller.updateSetting(
                  'deviceSettings',
                  jsonObject(originalSettings['deviceSettings']),
                ),
              );
            });
            if (restoreFailure != null) {
              throw StateError(
                'Could not fully restore the original app state: $restoreFailure',
              );
            }
          }
        }
      }
      stage = 'complete';
      binding.reportData!['incomingShareTargetComplete'] = true;
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
