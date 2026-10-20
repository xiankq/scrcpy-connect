import 'dart:convert';
import 'dart:developer' as developer;

import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/services/system_notifications.dart';

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  var stage = 'waiting-fixture';
  String? runId;
  String? hostError;
  final acknowledgements = <String>{};
  binding.reportData = {'notificationRequirementsComplete': false};
  developer.registerExtension('ext.connect.notificationRequirements', (
    _,
    args,
  ) async {
    if (args['action'] == 'fixture' && runId == null) runId = args['runId'];
    if (args['runId'] == runId && runId != null) {
      if (args['error'] != null) hostError = args['error'];
      if (args['action'] case final String action) acknowledgements.add(action);
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'stage': stage, 'runId': runId}),
    );
  });
  testWidgets(
    'Android notification requirements use original app and both actual notification centers',
    (tester) async {
      final originalHitTestPolicy =
          WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(
        () => WidgetController.hitTestWarningShouldBeFatal =
            originalHitTestPolicy,
      );
      await app.main();
      await waitFor(
        tester,
        () => find.byType(ConnectApp).evaluate().isNotEmpty,
        reason: 'Production app initializes.',
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
        reason: 'Bootstrap completes.',
      );
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 45));
      Future<void> checkpoint(
        String next,
        String ack, {
        bool cleanup = false,
      }) async {
        stage = next;
        binding.reportData!['stage'] = next;
        final deadline = DateTime.now().add(const Duration(seconds: 50));
        while (!acknowledgements.contains(ack) &&
            (cleanup || hostError == null) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          acknowledgements.contains(ack),
          isTrue,
          reason: 'Host must verify $next: $hostError',
        );
        if (!cleanup && hostError != null) throw StateError(hostError!);
      }

      await waitFor(
        tester,
        () => runId != null,
        reason: 'Owned fixture identity supplied.',
      );
      final initialDevices = objects(
        (await request('devices.list'))['devices'],
      );
      final initialSettings = await request('settings.get');
      String? deviceId;
      var created = false;
      var initiallyConnected = false;
      var converted = false;
      Future<Json> current() => request('notifications.list', {
        'deviceId': deviceId,
        'allowStart': false,
      });
      Future<void> capture(String name) async {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
        }
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot(name);
      }

      final page = find.byType(NotificationsPage);
      Future<Finder> card(int id) async {
        final title = '$runId-$id';
        await tester.scrollUntilVisible(
          find.text(title),
          240,
          scrollable: find
              .descendant(of: page, matching: find.byType(Scrollable))
              .first,
          maxScrolls: 40,
        );
        await Scrollable.ensureVisible(
          tester.element(find.text(title)),
          alignment: .5,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(title).hitTestable(), findsOneWidget);
        return find.ancestor(
          of: find.text(title),
          matching: find.byType(ContentPanel),
        );
      }

      try {
        await coordinator.initialize();
        if ((await coordinator.refreshStatus()).permissionGranted != true) {
          stage = 'requesting-permission';
          await coordinator.requestPermission();
        }
        expect((await coordinator.refreshStatus()).permissionGranted, isTrue);
        if (initialSettings['notificationAlerts'] != true) {
          await controller.updateSetting('notificationAlerts', true);
        }
        stage = 'connecting';
        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'transport': 'tcp',
            'attemptId': 'notification-requirements-$runId',
          }),
        );
        created = !initialDevices.any((d) => d['id'] == deviceId);
        initiallyConnected = initialDevices.any(
          (d) => d['id'] == deviceId && d['status'] == 'connected',
        );
        await request('devices.connect', {'deviceId': deviceId});
        await waitFor(
          tester,
          () => controller.snapshot().devices.any(
            (d) => d['id'] == deviceId && d['status'] == 'connected',
          ),
          reason: 'Target connection accepted.',
        );
        var source = await current();
        for (var i = 0; source['live'] != true && i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          source = await current();
        }
        expect(source['live'], isTrue);
        final sources = objects(source['notifications'])
            .where(
              (n) =>
                  n['packageName'] == 'dev.scrcpyconnect.notificationfixture' &&
                  n['groupSummary'] != true,
            )
            .toList();
        expect(sources.length, 3);
        expect(
          sources.every(
            (n) => n['appName'] == 'Connect notification test fixture',
          ),
          isTrue,
        );
        expect(
          sources.singleWhere((n) => n['title'] == '$runId-4')['canDismiss'],
          isFalse,
        );
        final icon = await request('apps.icon', {
          'deviceId': deviceId,
          'packageName': 'dev.scrcpyconnect.notificationfixture',
        });
        final Uint8List originalIcon = base64Decode(value(icon, 'dataBase64'));
        expect(originalIcon.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        NotificationsRoute(deviceId: deviceId!)
            .go(tester.element(find.byType(Scaffold).first));
        await waitFor(
          tester,
          () => find.text('$runId-0').evaluate().isNotEmpty,
          reason: 'Real notification card renders.',
        );
        await waitFor(
          tester,
          () => find
              .descendant(of: page, matching: find.byType(Image))
              .evaluate()
              .any((element) {
                final provider = (element.widget as Image).image;
                return provider is MemoryImage &&
                    listEquals(provider.bytes, originalIcon);
              }),
          reason: 'Actual target PNG is rendered by notification source icon.',
        );
        binding.reportData!.addAll({
          'realAppName': true,
          'originalAppIconRendered': true,
          'fixtureRunId': runId,
        });
        await coordinator.drain();
        await checkpoint('baseline', 'baseline');
        await capture('notification-requirements-cards');
        final opened = await card(0);
        await tester.tap(
          find.descendant(of: opened, matching: find.text('$runId-0')),
        );
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isNotEmpty,
          reason: 'Card opens actual phone view.',
        );
        await checkpoint('opened', 'opened');
        binding.reportData!['originalOpenConfirmed'] = true;
        await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
        await waitFor(
          tester,
          () =>
              find.byType(RemotePage).evaluate().isEmpty &&
              page.evaluate().isNotEmpty,
          reason: 'Return to source notification page.',
        );
        await checkpoint('lock-target', 'target-locked');
        final lockedCard = await card(0);
        await tester.tap(
          find.descendant(of: lockedCard, matching: find.text('$runId-0')),
        );
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isNotEmpty,
          reason: 'Locked notification opens real phone authentication view.',
        );
        await checkpoint('locked-opened', 'locked-opened');
        await capture('notification-requirements-locked-phone');
        binding.reportData!['lockedPhoneFallbackConfirmed'] = true;
        await checkpoint('unlock-target', 'target-unlocked');
        await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
        await waitFor(
          tester,
          () =>
              find.byType(RemotePage).evaluate().isEmpty &&
              page.evaluate().isNotEmpty,
          reason: 'Return from authentication view.',
        );
        final clearing = await card(0);
        await tester.tap(
          find.descendant(of: clearing, matching: find.byTooltip('已读（清除）')),
        );
        await waitFor(
          tester,
          () => find.text('$runId-0').evaluate().isEmpty,
          reason: 'Single clear syncs to current snapshot.',
        );
        await checkpoint('single-cleared', 'single-cleared');
        await tester.tap(find.byTooltip('全部已读'));
        await tester.pump(const Duration(seconds: 1));
        source = await current();
        for (
          var i = 0;
          i < 40 &&
              objects(source['notifications']).any(
                (n) =>
                    n['packageName'] ==
                        'dev.scrcpyconnect.notificationfixture' &&
                    n['canDismiss'] == true,
              );
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 250));
          source = await current();
        }
        final remaining = objects(source['notifications'])
            .where(
              (n) =>
                  n['packageName'] == 'dev.scrcpyconnect.notificationfixture' &&
                  n['groupSummary'] != true,
            )
            .toList();
        expect(remaining.map((n) => n['title']), ['$runId-4']);
        final ongoingCard = await card(4);
        expect(
          find.descendant(
            of: ongoingCard,
            matching: find.text('手机系统将此项标为不可清除，请在原应用中处理。'),
          ),
          findsOneWidget,
        );
        await checkpoint('all-cleared', 'all-cleared');
        binding.reportData!['singleAndAllClearConfirmed'] = true;
        await checkpoint('post-foreground', 'posted-foreground');
        await waitFor(
          tester,
          () => find.text('$runId-5').evaluate().isNotEmpty,
          reason: 'Foreground receives actual new source.',
        );
        await capture('notification-requirements-foreground');
        await checkpoint('foreground-mirrored', 'foreground-mirrored');
        binding.reportData!['foregroundOsMirrorConfirmed'] = true;
        await checkpoint('withdraw-target', 'target-withdrawn');
        source = await current();
        for (
          var i = 0;
          objects(source['notifications'])
                  .any((n) => n['title'] == '$runId-5') &&
              i < 40;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 250));
          source = await current();
        }
        expect(
          objects(source['notifications']).any((n) => n['title'] == '$runId-5'),
          isFalse,
        );
        await coordinator.drain();
        await checkpoint('withdrawn', 'withdrawn');
        binding.reportData!['targetWithdrawalConfirmed'] = true;
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await checkpoint('cleanup', 'cleanup', cleanup: true);
        } finally {
          if (deviceId != null && created) {
            await request('devices.forget', {'deviceId': deviceId});
          } else if (deviceId != null && !initiallyConnected) {
            await request('devices.disconnect', {'deviceId': deviceId});
          }
          if (initialSettings['notificationAlerts'] != true) {
            await controller.updateSetting(
              'notificationAlerts',
              initialSettings['notificationAlerts'],
            );
          }
        }
      }
      stage = 'complete';
      binding.reportData!['notificationRequirementsComplete'] = true;
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
