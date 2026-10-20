import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/reply/devices_workspace_notifications_reply_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'product_flow_test.dart' show tapPageAction, waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  var stage = 'waiting-fixture';
  String? runId;
  String? fixtureTag;
  String? replyText;
  String? hostError;
  var receiverVerified = false;
  var dismissalVerified = false;
  var fixtureCleaned = false;
  binding.reportData = {'notificationReplyComplete': false};
  developer.registerExtension('ext.connect.notificationReply', (_, args) async {
    if (args['error'] case final String error) {
      hostError = error;
    }
    switch (args['action']) {
      case 'fixture':
        if (runId == null) {
          runId = args['runId'];
          fixtureTag = args['tag'];
          replyText = args['text'];
        }
      case 'receiver':
        receiverVerified = args['runId'] == runId && args['count'] == '1';
      case 'dismissal':
        dismissalVerified = args['runId'] == runId;
      case 'cleanup':
        fixtureCleaned = args['runId'] == runId;
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'stage': stage, 'runId': runId}),
    );
  });

  testWidgets(
    'real notification reply stays guarded across navigation and exact dismissal',
    (tester) async {
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      await app.main();
      await waitFor(
        tester,
        () => find.byTooltip('添加设备').evaluate().isNotEmpty,
        reason: 'The production app must finish initialization.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 45));
      void checkHost() {
        if (hostError != null) {
          throw StateError(hostError!);
        }
      }

      Future<void> hostCheckpoint(String next, bool Function() ready) async {
        stage = next;
        binding.reportData!['stage'] = stage;
        await waitFor(
          tester,
          () => ready() || hostError != null,
          timeout: const Duration(seconds: 45),
          reason: 'Independent Android fixture must acknowledge $next.',
        );
        checkHost();
      }

      await hostCheckpoint('waiting-fixture', () => runId != null);
      expect(runId, matches(RegExp(r'^[a-zA-Z0-9_-]{1,80}$')));
      expect(fixtureTag, 'notification-fixture-$runId');
      expect(replyText, isNotEmpty);
      final title = '$runId-0';
      binding.reportData!.addAll({
        'fixtureRunId': runId,
        'fixtureTag': fixtureTag,
        'replyText': replyText,
      });
      final initialDevices = objects(
        (await request('devices.list'))['devices'],
      );
      String? deviceId;
      var initiallyConnected = false;
      var createdDevice = false;
      var convertedSurface = false;
      final replyPage = find.byType(NotificationReplyPage);
      final notificationsPage = find.byType(NotificationsPage);
      final originalClipboard = await Clipboard.getData(Clipboard.kTextPlain);
      // Shared Flutter has no clear-clipboard API. Require a text baseline
      // before this scoped test writes so cleanup can restore the exact text.
      expect(
        originalClipboard?.text,
        isNotNull,
        reason: 'Prepare an isolated controller text clipboard baseline before running this copy acceptance.',
      );
      binding.reportData!['clipboardBaselinePresent'] = true;

      Future<void> capture(String name) async {
        if (!convertedSurface) {
          await binding.convertFlutterSurfaceToImage();
          convertedSurface = true;
        }
        await tester.pump(const Duration(milliseconds: 250));
        await binding.takeScreenshot(name);
      }

      Future<void> leaveReply() async {
        await tester.binding.handlePopRoute();
        await waitFor(
          tester,
          () => replyPage.evaluate().isEmpty,
          reason: 'Leave the real reply route without losing its guard.',
        );
      }

      Future<Finder> fixtureCard() async {
        final current = await request('notifications.list', {
          'deviceId': deviceId,
        });
        final original = objects(current['notifications'])
            .singleWhere((item) => item['title'] == title);
        expect(
          original['packageName'],
          'dev.scrcpyconnect.notificationfixture',
        );
        expect(original['appName'], 'Connect notification test fixture');
        binding.reportData!['fixtureAppNameVerified'] = true;
        await tester.scrollUntilVisible(
          find.text(title),
          300,
          scrollable: find
              .descendant(
                of: notificationsPage,
                matching: find.byType(Scrollable),
              )
              .first,
          maxScrolls: 30,
        );
        return find.ancestor(
          of: find.text(title),
          matching: find.byType(ContentPanel),
        );
      }

      void expectGuardedReply() {
        final field = tester.widget<TextField>(
          find.descendant(of: replyPage, matching: find.byType(TextField)),
        );
        expect(field.controller!.text, replyText);
        expect(field.readOnly, isTrue);
        expect(find.text('发送回复'), findsNothing);
        expect(find.text('复制保留内容'), findsOneWidget);
      }

      try {
        // Core prepares the connection and reads current snapshots. Reply and
        // dismissal are exercised through the actual Flutter notification UI.
        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'transport': 'tcp',
            'attemptId':
                'notification-reply-${DateTime.now().microsecondsSinceEpoch}',
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
        WorkspaceRoute(deviceId: deviceId!)
            .go(tester.element(find.byType(Scaffold).first));
        await waitFor(
          tester,
          () => find.byType(DeviceWorkspacePage).evaluate().isNotEmpty,
          reason: 'Open the production workspace for the prepared endpoint.',
        );
        await tapPageAction(
          tester,
          find.byType(DeviceWorkspacePage),
          find.text('实时通知'),
        );
        await waitFor(
          tester,
          () => notificationsPage.evaluate().isNotEmpty,
          reason: 'Open the actual current notification page.',
        );
        await waitFor(
          tester,
          () =>
              find.byType(RefreshIndicator).evaluate().isNotEmpty ||
              find.text('启用通知与来电观察').evaluate().isNotEmpty ||
              find.text('重新核验通知').evaluate().isNotEmpty,
          reason: 'Notification access must resolve through the product UI.',
        );
        for (final label in ['启用通知与来电观察', '重新核验通知']) {
          if (find.text(label).evaluate().isNotEmpty) {
            await tapPageAction(tester, notificationsPage, find.text(label));
            break;
          }
        }
        await waitFor(
          tester,
          () => find.byType(RefreshIndicator).evaluate().isNotEmpty,
          reason: 'The real fixture notifications must become available.',
        );
        var card = await fixtureCard();
        expect(card, findsOneWidget);
        await tapPageAction(
          tester,
          notificationsPage,
          find.descendant(of: card, matching: find.text('快捷回复')),
        );
        await waitFor(
          tester,
          () => replyPage.evaluate().isNotEmpty,
          reason:
              'The mutable original RemoteInput action must open a reply page.',
        );
        final notificationId = GoRouterState.of(tester.element(replyPage))
            .pathParameters['notificationId'];
        expect(notificationId, isNotEmpty);
        binding.reportData!['notificationId'] = notificationId;
        await tester.enterText(find.byType(TextField), replyText!);
        await tapPageAction(tester, replyPage, find.text('发送回复'));
        await waitFor(
          tester,
          () => find.textContaining('原应用动作已交给系统').evaluate().isNotEmpty,
          timeout: const Duration(seconds: 45),
          reason: 'The original Android action must be accepted by the system.',
        );
        expect(find.textContaining('未确认应用或消息服务送达'), findsOneWidget);
        expectGuardedReply();
        binding.reportData!.addAll({
          'systemAcceptanceVisible': true,
          'deliveryUnconfirmedVisible': true,
        });
        await hostCheckpoint('awaiting-receiver', () => receiverVerified);
        await capture('notification-reply-system-accepted');
        await leaveReply();
        card = await fixtureCard();
        await tapPageAction(
          tester,
          notificationsPage,
          find.descendant(of: card, matching: find.text('快捷回复')),
        );
        await waitFor(
          tester,
          () => replyPage.evaluate().isNotEmpty,
          reason: 'Reopen the same original notification route.',
        );
        expectGuardedReply();
        expect(find.textContaining('未确认应用或消息服务送达'), findsOneWidget);
        binding.reportData!['reopenedReplyGuarded'] = true;
        await leaveReply();
        card = await fixtureCard();
        await tapPageAction(
          tester,
          notificationsPage,
          find.descendant(of: card, matching: find.byTooltip('已读（清除）')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final dismissDeadline = DateTime.now().add(const Duration(seconds: 30));
        var dismissed = false;
        while (!dismissed && DateTime.now().isBefore(dismissDeadline)) {
          final snapshot = await request('notifications.list', {
            'deviceId': deviceId,
          });
          dismissed =
              snapshot['live'] == true &&
              !objects(snapshot['notifications'])
                  .any((item) => item['id'] == notificationId);
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(
          dismissed,
          isTrue,
          reason: 'The exact original notification must disappear remotely.',
        );
        binding.reportData!['notificationDismissed'] = true;
        await hostCheckpoint(
          'awaiting-dismissal-check',
          () => dismissalVerified,
        );
        unawaited(
          NotificationReplyRoute(
            deviceId: deviceId,
            notificationId: notificationId!,
          ).push<void>(tester.element(notificationsPage)),
        );
        await waitFor(
          tester,
          () =>
              replyPage.evaluate().isNotEmpty &&
              find.text('本机保留的回复').evaluate().isNotEmpty,
          reason: 'The old route must preserve text after the original action expires.',
        );
        expectGuardedReply();
        expect(find.text('这条通知已更新或结束，旧回复动作不能再使用。已保留草稿。'), findsOneWidget);
        await tapPageAction(tester, replyPage, find.text('复制保留内容'));
        final copied = await Clipboard.getData(Clipboard.kTextPlain);
        expect(copied?.text, replyText);
        binding.reportData!['dismissedReplyCopyMatches'] = true;
        await capture('notification-reply-expired-copy');
        await hostCheckpoint('awaiting-cleanup', () => fixtureCleaned);
        binding.reportData!['fixtureCleanupAcknowledged'] = true;
        expect(tester.takeException(), isNull);
      } finally {
        if (originalClipboard != null) {
          await Clipboard.setData(originalClipboard);
          binding.reportData!['clipboardRestored'] = true;
        }
        if (deviceId != null && createdDevice) {
          await request('devices.forget', {'deviceId': deviceId});
        } else if (deviceId != null && !initiallyConnected) {
          await request('devices.disconnect', {'deviceId': deviceId});
        }
      }
      stage = 'complete';
      binding.reportData!.addAll({
        'stage': stage,
        'notificationReplyComplete': true,
      });
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
