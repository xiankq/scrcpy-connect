import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/apps/devices_workspace_apps_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/sessions/tools/devices_workspace_sessions_tools_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/sessions/index/devices_workspace_sessions_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'product_flow_test.dart'
    show waitFor, expectHealthyRemote, tapPageAction;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  binding.reportData = {'sessionWorkspaceComplete': false};
  Map<String, dynamic>? checkpoint;
  String? acknowledged;
  String? hostError;
  developer.registerExtension('ext.connect.sessions', (_, parameters) async {
    if (parameters['ack'] == checkpoint?['name']) {
      acknowledged = parameters['ack'];
      hostError = parameters['error'];
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'checkpoint': checkpoint}),
    );
  });
  testWidgets(
    'main screen and two real apps survive returns, resume and close independently',
    (tester) async {
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      await app.main();
      await tester.pump(const Duration(milliseconds: 500));
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 45));
      String? deviceId;
      final ownedIds = <String>[];
      final closedIds = <String>[];
      final initialSessions = <String>{};
      Future<List<Json>> sessions() async => objects(
        (await request('session.list', {'deviceId': deviceId}))['sessions'],
      );
      String idOf(Json session) =>
          value(session, 'sessionId', value(session, 'id'));
      var surfaceCaptured = false;
      Future<void> screenshot(String name, {String? active}) async {
        if (!surfaceCaptured) {
          await binding.convertFlutterSurfaceToImage();
          surfaceCaptured = true;
        }
        await tester.pump(const Duration(milliseconds: 250));
        checkpoint = {
          'name': name,
          'sessionIds': [...ownedIds],
          'closedSessionIds': [...closedIds],
          'activeSessionId': active,
        };
        debugPrint('session-checkpoint: $name');
        await waitFor(
          tester,
          () => acknowledged == name,
          timeout: const Duration(seconds: 20),
          reason: 'The host must inspect actual target processes at this checkpoint.',
        );
        if (hostError != null) throw StateError(hostError!);
        await binding.takeScreenshot(name);
      }

      Future<Json> current(String? package) async {
        try {
          await waitFor(
            tester,
            () =>
                find.byType(Texture).evaluate().isNotEmpty &&
                find
                    .descendant(
                      of: find.byType(RemotePage),
                      matching: find.text('画面已暂停'),
                    )
                    .evaluate()
                    .isEmpty &&
                find
                    .descendant(
                      of: find.byType(RemotePage),
                      matching: find.byType(CircularProgressIndicator),
                    )
                    .evaluate()
                    .isEmpty,
            timeout: const Duration(seconds: 45),
            reason: 'The actual product must decode the selected window.',
          );
        } catch (_) {
          debugPrint(
            'window-failed: $package; visible=${find.byType(Text).evaluate().map((element) => (element.widget as Text).data).toList()}',
          );
          if (surfaceCaptured) {
            await binding.takeScreenshot('workspace-window-failed');
          }
          rethrow;
        }
        final active = (await sessions()).singleWhere(
          (item) =>
              item['status'] == 'streaming' && item['packageName'] == package,
        );
        expect(active['firstFrameDecoded'], isTrue);
        expect(active['evidence'], 'mdk.snapshot');
        expectHealthyRemote();
        if (!ownedIds.contains(idOf(active))) ownedIds.add(idOf(active));
        return active;
      }

      Future<void> waitForSettingsPixels(String id) async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        var lightContent = false;
        do {
          final receipt = await request('session.screenshot', {
            'sessionId': id,
          });
          final file = File(value(receipt, 'localPath'));
          try {
            final codec = await ui.instantiateImageCodec(
              await file.readAsBytes(),
              targetWidth: 32,
              targetHeight: 64,
            );
            try {
              final frame = await codec.getNextFrame();
              try {
                final pixels = await frame.image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                );
                expect(pixels, isNotNull);
                var bright = 0;
                var ink = 0;
                for (var y = 14; y < 50; y++) {
                  for (var x = 4; x < 28; x++) {
                    final offset = (y * 32 + x) * 4;
                    if (pixels!.getUint8(offset) > 180 &&
                        pixels.getUint8(offset + 1) > 180 &&
                        pixels.getUint8(offset + 2) > 180) {
                      bright++;
                    }
                    if (pixels.getUint8(offset) < 140 &&
                        pixels.getUint8(offset + 1) < 140 &&
                        pixels.getUint8(offset + 2) < 140) {
                      ink++;
                    }
                  }
                }
                // The isolated stock target's Settings is light; its HOME
                // fixture is dark. Pair this pixel check with host observation
                // of the actual Settings task, not merely a sent receipt.
                // A white launch surface is not rendered Settings content.
                lightContent = bright > 24 * 36 * .7 && ink > 12;
              } finally {
                frame.image.dispose();
              }
            } finally {
              codec.dispose();
            }
          } finally {
            await file.delete();
            await file.parent.delete();
          }
          if (!lightContent) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        } while (!lightContent && DateTime.now().isBefore(deadline));
        expect(
          lightContent,
          isTrue,
          reason: 'The controller must render Settings rather than its earlier HOME frame.',
        );
      }

      Future<void> leave(Json session) async {
        await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isEmpty,
          reason: 'Return must retain a paused window.',
        );
        Json retained = {};
        final pauseDeadline = DateTime.now().add(const Duration(seconds: 5));
        do {
          retained = (await sessions()).singleWhere(
            (item) => idOf(item) == idOf(session),
          );
          if (retained['status'] == 'paused') {
            break;
          }
          await tester.pump(const Duration(milliseconds: 100));
        } while (DateTime.now().isBefore(pauseDeadline));
        expect(retained['status'], 'paused');
        expect(retained['capturePaused'], isFalse);
        expect(retained['presentationOnly'], isTrue);
        expect(retained['textureId'], isNotNull);
      }

      Future<void> backFrom(Finder page) async {
        await tester.tap(
          find.descendant(of: page, matching: find.byType(BackButton)),
        );
        await waitFor(
          tester,
          () => page.evaluate().isEmpty,
          reason: 'Return to the same workspace.',
        );
      }

      try {
        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'attemptId': 'sessions-${DateTime.now().microsecondsSinceEpoch}',
          }),
        );
        await request('devices.connect', {'deviceId': deviceId});
        initialSessions.addAll((await sessions()).map(idOf));
        expect(
          initialSessions,
          isEmpty,
          reason:
              'Use an isolated target; never close someone else’s sessions.',
        );
        // Fixture configuration, not evidence for the quality or connection UI.
        await request('session.quality', {
          'deviceId': deviceId,
          'videoCodec': 'h264',
          'videoEncoder': null,
          'maxSize': 720,
          'maxFps': 30,
          'bitRate': 2000000,
        });
        await request('devices.wake', {'deviceId': deviceId});
        WorkspaceRoute(deviceId: deviceId!)
            .go(tester.element(find.byType(Scaffold).first));
        await waitFor(
          tester,
          () => find.byType(DeviceWorkspacePage).evaluate().isNotEmpty,
          reason: 'Open the real workspace.',
        );
        await tapPageAction(
          tester,
          find.byType(DeviceWorkspacePage),
          find.text('打开手机屏幕'),
        );
        final main = await current(null);
        for (final action in ['down', 'up']) {
          await request('session.key', {
            'sessionId': idOf(main),
            'keyCode': 3,
            'action': action,
          });
        }
        await tester.pump(const Duration(milliseconds: 500));
        await screenshot('session-main-live', active: idOf(main));
        await leave(main);
        await tapPageAction(
          tester,
          find.byType(DeviceWorkspacePage),
          find.text('手机应用'),
        );
        await waitFor(
          tester,
          () => find.byType(AppsPage).evaluate().isNotEmpty,
          reason:
              'Open the real application list for phone-screen continuation.',
        );
        await tester.enterText(find.byType(TextField), 'com.android.settings');
        final settingsApp = find.widgetWithText(
          ActionRow,
          'com.android.settings',
        );
        await waitFor(
          tester,
          () => settingsApp.evaluate().isNotEmpty,
          reason: 'The target must expose Settings.',
        );
        await tester.tap(settingsApp);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('在手机屏幕打开'));
        final continued = await current(null);
        expect(idOf(continued), idOf(main));
        expect((await sessions()).map(idOf).toList(), [idOf(main)]);
        await waitForSettingsPixels(idOf(main));
        await screenshot('session-primary-app-live', active: idOf(main));
        binding.reportData!['phoneScreenAppResumed'] = true;
        binding.reportData!['phoneScreenRenderedApp'] = true;
        await leave(continued);
        await backFrom(find.byType(AppsPage));
        for (final package in [
          'com.android.settings',
          'com.google.android.dialer',
        ]) {
          await tapPageAction(
            tester,
            find.byType(DeviceWorkspacePage),
            find.text('手机应用'),
          );
          await waitFor(
            tester,
            () => find.byType(AppsPage).evaluate().isNotEmpty,
            reason: 'Open the actual app list.',
          );
          await tester.enterText(find.byType(TextField), package);
          await waitFor(
            tester,
            () => find.widgetWithText(ActionRow, package).evaluate().isNotEmpty,
            reason: 'The target must actually expose the requested app.',
          );
          await tester.tap(find.widgetWithText(ActionRow, package));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('在独立窗口打开'));
          final session = await current(package);
          await screenshot(
            package == 'com.android.settings'
                ? 'session-settings-live'
                : 'session-dialer-live',
            active: idOf(session),
          );
          await leave(session);
          await backFrom(find.byType(AppsPage));
        }
        expect(ownedIds, hasLength(3));
        expect((await sessions()).map(idOf).toSet(), ownedIds.toSet());
        expect(
          (await sessions()).every((item) => item['status'] == 'paused'),
          isTrue,
        );
        await tapPageAction(
          tester,
          find.byType(DeviceWorkspacePage),
          find.text('当前控制会话'),
        );
        await waitFor(
          tester,
          () =>
              find.byType(SessionsPage).evaluate().isNotEmpty &&
              find
                  .byKey(ValueKey('open-session:${ownedIds.last}'))
                  .evaluate()
                  .isNotEmpty,
          reason: 'All retained windows must be listed.',
        );
        for (final command in ['session.key', 'session.pause']) {
          await expectLater(
            request(command, {
              'deviceId': deviceId,
              if (command == 'session.key') ...{'keyCode': 3, 'action': 'up'},
            }),
            throwsA(
              isA<RequestFailure>().having(
                (failure) => failure.code,
                'code',
                'ambiguous_session',
              ),
            ),
          );
        }
        await screenshot('workspace-three-paused');
        final settingsId = ownedIds[1];
        await tapPageAction(
          tester,
          find.byType(SessionsPage),
          find.byKey(ValueKey('open-session:$settingsId')),
        );
        final resumed = await current('com.android.settings');
        expect(idOf(resumed), settingsId);
        expect(
          (await sessions())
              .where((item) => idOf(item) != settingsId)
              .every((item) => item['status'] == 'paused'),
          isTrue,
        );
        await screenshot('workspace-settings-resumed', active: settingsId);
        await leave(resumed);
        await tapPageAction(
          tester,
          find.byType(SessionsPage),
          find.byKey(ValueKey('tools-session:$settingsId')),
        );
        await waitFor(
          tester,
          () => find.text('截取当前画面').evaluate().isNotEmpty,
          reason: 'Tools must resolve the selected session.',
        );
        await tester.tap(find.text('截取当前画面'));
        await waitFor(
          tester,
          () => find.byType(Image).evaluate().isNotEmpty,
          reason: 'Read the selected window’s real rendered snapshot.',
        );
        await screenshot('workspace-settings-screenshot');
        final toolContext = tester.element(find.byType(SessionToolsPage));
        Navigator.of(toolContext).pop();
        await tester.pump(const Duration(milliseconds: 400));
        await backFrom(find.byType(SessionToolsPage));
        await tapPageAction(
          tester,
          find.byType(SessionsPage),
          find.byKey(ValueKey('close-session:$settingsId')),
        );
        await waitFor(
          tester,
          () => find
              .byKey(ValueKey('open-session:$settingsId'))
              .evaluate()
              .isEmpty,
          reason: 'Closing one window must refresh the actual session list.',
        );
        ownedIds.remove(settingsId);
        closedIds.add(settingsId);
        expect((await sessions()).map(idOf).toSet(), ownedIds.toSet());
        await screenshot('workspace-one-closed');
        await tapPageAction(
          tester,
          find.byType(SessionsPage),
          find.byKey(ValueKey('open-session:${ownedIds.last}')),
        );
        final dialer = await current('com.google.android.dialer');
        expect(idOf(dialer), ownedIds.last);
        await screenshot('workspace-dialer-survives', active: idOf(dialer));
        await leave(dialer);
        binding.reportData!.addAll({
          'sessionIds': [...ownedIds, settingsId],
          'pausedWindowsVerified': 3,
          'closedWindowId': settingsId,
          'survivingWindowId': idOf(dialer),
          'sessionWorkspaceComplete': true,
        });
      } finally {
        // Only this fixture’s exact identities; never stop by device or package.
        for (final id in ownedIds) {
          if (!initialSessions.contains(id)) {
            try {
              await request('session.stop', {
                'sessionId': id,
                'keepTask': true,
              });
            } catch (_) {}
          }
        }
      }
      expect(tester.takeException(), isNull);
    },
  );
}
