import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/connection/connection_validation.dart';
import 'package:scrcpy_connect/platform/system_notification_coordinator.dart';

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  var stage = 'waiting-fixture';
  String? runId;
  String? hostError;
  final acknowledgements = <String>{};
  binding.reportData = {'systemNotificationsComplete': false};
  developer.registerExtension('ext.connect.systemNotifications', (
    _,
    args,
  ) async {
    if (args['action'] == 'fixture' && runId == null) {
      final candidate = args['runId'];
      if (candidate != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(candidate)) {
        runId = candidate;
      }
    }
    if (args['runId'] == runId && runId != null) {
      if (args['error'] != null) hostError = 'Android host check failed.';
      if (args['action'] case final String action) {
        acknowledgements.add(action);
      }
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'stage': stage, 'runId': runId}),
    );
  });

  testWidgets(
    'real remote notices reach Android and open only their task page',
    (tester) async {
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      await app.main();
      await waitFor(
        tester,
        () =>
            find.byType(ConnectApp).evaluate().isNotEmpty &&
            find.byType(Scaffold).evaluate().isNotEmpty,
        reason:
            'The production app must initialize its actual bridge and sink.',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      );
      final controller = container.read(appControllerProvider.notifier);
      final coordinator = container.read(systemNotificationCoordinatorProvider);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
        reason: 'Production bootstrap must finish its initial state snapshot.',
      );
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 45));
      Future<void> checkpoint(
        String next,
        String acknowledgement, {
        bool cleanup = false,
      }) async {
        stage = next;
        binding.reportData!['stage'] = stage;
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        // HOME 可能暂停帧调度；宿主确认和 Rust 事件仍须继续，不能等待 Flutter 绘制帧。
        while (!acknowledgements.contains(acknowledgement) &&
            (cleanup || hostError == null) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          acknowledgements.contains(acknowledgement) ||
              (!cleanup && hostError != null),
          isTrue,
          reason: 'Independent Android evidence must acknowledge $next.',
        );
        if (!cleanup && hostError != null) throw StateError(hostError!);
      }

      await waitFor(
        tester,
        () => runId != null,
        reason: 'The host must provide an isolated notification run identity.',
      );
      binding.reportData!['fixtureRunId'] = runId;
      final titles = [
        for (final suffix in ['withdraw', 'click'])
          'connect-system-$runId-$suffix',
      ];
      final initialDevices = objects(
        (await request('devices.list'))['devices'],
      );
      final initialSettings = await request('settings.get');
      String? deviceId;
      var createdDevice = false;
      var initiallyConnected = false;
      final sourceIds = <String>[];
      final incoming = <Json>[];
      final subscription = controller
          .eventStream()
          .where(
            (event) =>
                event['type'] == 'notifications.changed' ||
                event['type'] == 'observation.changed',
          )
          .listen(incoming.add);

      Future<Json> currentNotifications() => request('notifications.list', {
        'deviceId': deviceId,
        'allowStart': false,
      });
      bool owned(Json item) =>
          item['packageName'] == 'com.android.shell' &&
          titles.contains(item['title']);
      Future<void> removeOwnedSources() async {
        if (deviceId == null) return;
        final snapshot = await currentNotifications();
        for (final item in objects(snapshot['notifications']).where(owned)) {
          await request('notifications.dismiss', {
            'deviceId': deviceId,
            'notificationId': item['id'],
          });
        }
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        var clean = false;
        while (DateTime.now().isBefore(deadline)) {
          clean = !objects((await currentNotifications())['notifications'])
              .any(owned);
          if (clean) break;
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          clean,
          isTrue,
          reason: 'Only this run’s source notices must clear.',
        );
        await coordinator.drain();
      }

      try {
        await coordinator.initialize();
        await coordinator.refreshStatus();
        if (coordinator.status.permissionGranted != true) {
          stage = 'requesting-permission';
          await coordinator.requestPermission();
        }
        final permission = await coordinator.refreshStatus();
        expect(
          permission.supported &&
              permission.permissionGranted == true &&
              permission.notificationChannelEnabled != false,
          isTrue,
          reason: 'Actual Android posting permission and channel are required.',
        );
        binding.reportData!['permissionGranted'] = true;
        for (final key in ['notificationAlerts', 'backgroundKeepAlive']) {
          if (initialSettings[key] != true) {
            await controller.updateSetting(key, true);
          }
        }
        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'transport': 'tcp',
            'attemptId': 'system-notifications-$runId',
          }),
        );
        createdDevice = !initialDevices.any(
          (device) => device['id'] == deviceId,
        );
        initiallyConnected = initialDevices.any(
          (device) =>
              device['id'] == deviceId && device['status'] == 'connected',
        );
        await request('devices.connect', {'deviceId': deviceId});
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        var live = false;
        while (DateTime.now().isBefore(deadline)) {
          final observation = await request('observation.status', {
            'deviceId': deviceId,
          });
          live =
              jsonObject(observation['notifications'])['live'] == true &&
              observation['wanted'] == true;
          if (live) break;
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          live,
          isTrue,
          reason: 'Connection must automatically start real observation.',
        );
        await tester.pump(const Duration(seconds: 1));
        await coordinator.drain();
        binding.reportData!['automaticObservationLive'] = true;
        await checkpoint('ready-background', 'posted');

        // 实际 HOME 之后宿主分别发布 A 和 B，发布下一来源前记录新建的系统键。
        final sourceDeadline = DateTime.now().add(const Duration(seconds: 20));
        List<Json> sources = [];
        while (DateTime.now().isBefore(sourceDeadline)) {
          sources = objects((await currentNotifications())['notifications'])
              .where(owned)
              .toList();
          if (sources.length == 2) break;
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(sources.length, 2);
        final withdraw = sources.singleWhere(
          (item) => item['title'] == titles[0],
        );
        final click = sources.singleWhere((item) => item['title'] == titles[1]);
        sourceIds.addAll([value(withdraw, 'id'), value(click, 'id')]);
        expect(sourceIds.every((id) => id.isNotEmpty), isTrue);
        expect(sourceIds.toSet().length, 2);
        expect(
          incoming.any(
            (event) =>
                event['deviceId'] == deviceId &&
                event['type'] == 'notifications.changed' &&
                objects(jsonObject(event['data'])['notifications']).any(owned),
          ),
          isTrue,
          reason: 'Production Rust observation events must carry the sources.',
        );
        binding.reportData!.addAll({
          'sourceNotificationIds': sourceIds,
          'realNotificationEventObserved': true,
        });
        await request('notifications.dismiss', {
          'deviceId': deviceId,
          'notificationId': sourceIds[0],
        });
        await checkpoint('awaiting-withdrawal', 'withdrawal');
        final afterWithdrawal = objects(
          (await currentNotifications())['notifications'],
        );
        expect(
          !afterWithdrawal.any((item) => item['id'] == sourceIds[0]) &&
              afterWithdrawal.any((item) => item['id'] == sourceIds[1]),
          isTrue,
        );
        binding.reportData!['exactSourceWithdrawalVerified'] = true;

        final sessionsBefore = jsonEncode(
          (await request('session.list'))['sessions'],
        );
        await checkpoint('awaiting-system-click', 'clicked');
        await waitFor(
          tester,
          () => find.byType(NotificationsPage).evaluate().isNotEmpty,
          reason: 'The real Android PendingIntent must open NotificationsPage.',
        );
        final page = tester.widget<NotificationsPage>(
          find.byType(NotificationsPage),
        );
        expect(page.device['id'] == deviceId, isTrue);
        await waitFor(
          tester,
          () =>
              find.text(titles[1]).evaluate().isNotEmpty &&
              find
                  .descendant(
                    of: find.byType(NotificationsPage),
                    matching: find.byType(CircularProgressIndicator),
                  )
                  .evaluate()
                  .isEmpty,
          reason: 'The OS destination must render the current source, not just a route or loading frame.',
        );
        expect(find.text(titles[0]), findsNothing);
        final afterClick = objects(
          (await currentNotifications())['notifications'],
        );
        expect(
          afterClick.any(
            (item) =>
                item['id'] == sourceIds[1] &&
                item['revision'] == click['revision'],
          ),
          isTrue,
          reason:
              'Opening the OS notice must retain the current remote source.',
        );
        expect(
          jsonEncode((await request('session.list'))['sessions']) ==
              sessionsBefore,
          isTrue,
          reason: 'The OS click must not start a remote control session.',
        );
        binding.reportData!.addAll({
          'notificationsPageOpened': true,
          'clickedSourceStillLive': true,
          'remoteSessionUnchanged': true,
        });
        await checkpoint('awaiting-page-capture', 'page-captured');
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await removeOwnedSources();
          await checkpoint('awaiting-cleanup', 'cleanup', cleanup: true);
          binding.reportData!['fixtureCleanupAcknowledged'] = true;
        } finally {
          await subscription.cancel();
          for (final key in ['notificationAlerts', 'backgroundKeepAlive']) {
            if (initialSettings.containsKey(key) &&
                initialSettings[key] != true) {
              await controller.updateSetting(key, initialSettings[key]);
            }
          }
          if (deviceId != null && createdDevice) {
            await request('devices.forget', {'deviceId': deviceId});
          } else if (deviceId != null && !initiallyConnected) {
            await request('devices.disconnect', {'deviceId': deviceId});
          }
        }
      }
      stage = 'complete';
      binding.reportData!.addAll({
        'stage': stage,
        'systemNotificationsComplete': true,
      });
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
