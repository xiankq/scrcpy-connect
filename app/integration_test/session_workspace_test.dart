import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/apps/devices_workspace_apps_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
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
    'phone and application windows release exact resources on close and keep real tasks',
    (tester) async {
      final semantics = tester.ensureSemantics();
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      await app.main();
      await waitFor(
        tester,
        () => find.byType(ConnectApp).evaluate().isNotEmpty,
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
        reason: 'Startup reconciliation must finish before fixture changes.',
      );
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 45));
      final initialDevices = objects(
        (await request('devices.list'))['devices'],
      );
      final originalSettings = {...controller.snapshot().settings};
      final originalFocus = controller.snapshot().focusedDeviceId;
      String? deviceId;
      var createdDevice = false;
      var initiallyConnected = false;
      final ownedIds = <String>[];
      final allIds = <String>[];
      Finder appRow(String package) => find.ancestor(
        of: find.byWidgetPredicate(
          (widget) => widget is PhoneAppIcon && widget.packageName == package,
        ),
        matching: find.byType(ListTile),
      );
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
        if (!allIds.contains(idOf(active))) allIds.add(idOf(active));
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
        await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
        await tester.pump();
        await tester.ensureVisible(find.text('关闭画面'));
        await tester.tap(find.text('关闭画面'));
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isEmpty,
          reason: 'Close must release this exact window.',
        );
        final closeDeadline = DateTime.now().add(const Duration(seconds: 5));
        var remaining = <Json>[];
        do {
          remaining = (await sessions())
              .where(
                (item) =>
                    idOf(item) == idOf(session) && item['status'] != 'stopped',
              )
              .toList();
          if (remaining.isEmpty) break;
          await tester.pump(const Duration(milliseconds: 100));
        } while (DateTime.now().isBefore(closeDeadline));
        expect(remaining, isEmpty);
        ownedIds.remove(idOf(session));
        closedIds.add(idOf(session));
        if (session['packageName'] != null) {
          final tasks = await request('apps.list', {
            'deviceId': deviceId,
            'filter': 'running',
          });
          expect(
            objects(tasks['apps'])
                .any((app) => app['packageName'] == session['packageName']),
            isTrue,
            reason: 'Closing the control window must keep the actual application task.',
          );
        }
        await screenshot('session-closed-${closedIds.length}');
      }

      Future<void> backFrom(Finder page) async {
        final label = MaterialLocalizations.of(tester.element(page))
            .backButtonTooltip;
        final back = find
            .descendant(of: page, matching: find.bySemanticsLabel(label))
            .hitTestable();
        await waitFor(
          tester,
          () => back.evaluate().isNotEmpty,
          reason: 'The current page must expose its real back action.',
        );
        await tester.tap(back);
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
        createdDevice = !initialDevices.any(
          (device) => device['id'] == deviceId,
        );
        initiallyConnected = initialDevices.any(
          (device) =>
              device['id'] == deviceId && device['status'] == 'connected',
        );
        await request('devices.connect', {'deviceId': deviceId});
        initialSessions.addAll((await sessions()).map(idOf));
        expect(
          initialSessions,
          isEmpty,
          reason:
              'Use an isolated target; never close someone else’s sessions.',
        );
        await controller.updateSetting('deviceSettings', {
          ...jsonObject(originalSettings['deviceSettings']),
          deviceId!: {'wakeOnConnect': true, 'lockOnClose': false},
        });
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
        WorkspaceRoute(deviceId: deviceId)
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
          find.text('全部应用'),
        );
        await waitFor(
          tester,
          () =>
              find.byType(AppsPage).evaluate().isNotEmpty &&
              find
                  .descendant(
                    of: find.byType(AppsPage),
                    matching: find.byType(TextField),
                  )
                  .evaluate()
                  .isNotEmpty,
          reason:
              'Open the real application list for phone-screen continuation.',
        );
        await tester.enterText(find.byType(TextField), 'com.android.settings');
        final settingsApp = appRow('com.android.settings');
        await waitFor(
          tester,
          () => settingsApp.evaluate().isNotEmpty,
          reason: 'The target must expose Settings.',
        );
        await tester.tap(settingsApp);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('在手机屏幕打开'));
        final continued = await current(null);
        expect(idOf(continued), isNot(idOf(main)));
        expect((await sessions()).map(idOf).toList(), [idOf(continued)]);
        await waitForSettingsPixels(idOf(continued));
        await screenshot('session-primary-app-live', active: idOf(continued));
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
            find.text('全部应用'),
          );
          await waitFor(
            tester,
            () =>
                find.byType(AppsPage).evaluate().isNotEmpty &&
                find
                    .descendant(
                      of: find.byType(AppsPage),
                      matching: find.byType(TextField),
                    )
                    .evaluate()
                    .isNotEmpty,
            reason: 'Open the actual app list.',
          );
          await tester.enterText(find.byType(TextField), package);
          await waitFor(
            tester,
            () => appRow(package).evaluate().isNotEmpty,
            reason: 'The target must actually expose the requested app.',
          );
          await tester.tap(appRow(package));
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
        expect(ownedIds, isEmpty);
        expect(allIds.toSet(), hasLength(4));
        expect(
          (await sessions()).where((item) => item['status'] != 'stopped'),
          isEmpty,
        );
        binding.reportData!.addAll({
          'sessionIds': allIds,
          'closedWindowIds': closedIds,
          'releasedWindowsVerified': 4,
          'sessionWorkspaceComplete': true,
        });
      } finally {
        semantics.dispose();
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
        try {
          await controller.updateSetting(
            'deviceSettings',
            jsonObject(originalSettings['deviceSettings']),
          );
          await controller.updateSetting(
            'deviceQuality',
            jsonObject(originalSettings['deviceQuality']),
          );
          await controller.focusDevice(originalFocus);
        } finally {
          if (createdDevice && deviceId != null) {
            await request('devices.forget', {'deviceId': deviceId});
          } else if (!initiallyConnected &&
              deviceId != null &&
              initialSessions.isEmpty) {
            await request('devices.disconnect', {'deviceId': deviceId});
          }
        }
      }
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
