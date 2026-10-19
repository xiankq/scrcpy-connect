import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/sessions/tools/devices_workspace_sessions_tools_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'product_flow_test.dart'
    show expectHealthyRemote, tapPageAction, waitFor;

// Run with tool/driver/remote_ime.dart. This injects Flutter IME editing values;
// it does not claim to exercise Gboard's Chinese candidate UI.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  Map<String, dynamic>? checkpoint;
  Map<String, dynamic>? hostResult;
  String? acknowledged;
  String? hostError;
  developer.registerExtension('ext.connect.remoteIme', (_, parameters) async {
    if (parameters['ack'] == checkpoint?['name']) {
      acknowledged = parameters['ack'];
      hostError = parameters['error'];
      hostResult = parameters['result'] == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(parameters['result']!) as Map);
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'checkpoint': checkpoint}),
    );
  });
  binding.reportData = {'remoteImeComplete': false};
  testWidgets(
    'committed Chinese and emoji reach the real Android EditText once',
    (tester) async {
      // IntegrationTest normally leaves the platform IME installed. Register
      // the Flutter input protocol mock explicitly for this editing sequence.
      tester.testTextInput.register();
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      await app.main();
      await waitFor(
        tester,
        () => find.byType(ConnectApp).evaluate().isNotEmpty,
        reason: 'The production app must initialize before reading providers.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
        reason: 'Production startup reconciliation must finish before fixtures change state.',
      );
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 40));
      final initialDevices = objects(
        (await request('devices.list'))['devices'],
      );
      final initialSettings = {...controller.snapshot().settings};
      final initialFocus = controller.snapshot().focusedDeviceId;
      String? deviceId;
      String? sessionId;
      var createdDevice = false;
      var initiallyConnected = false;
      var targetFocused = false;
      final initialSessionIds = <String>{};
      String id(Json item) => value(item, 'sessionId', value(item, 'id'));
      Future<List<Json>> sessions() async => objects(
        (await request('session.list', {'deviceId': deviceId}))['sessions'],
      );
      Future<Map<String, dynamic>> host(String name) async {
        hostResult = null;
        hostError = null;
        checkpoint = {'name': name, 'sessionId': sessionId};
        await waitFor(
          tester,
          () => acknowledged == name,
          timeout: const Duration(seconds: 40),
          reason: 'Host must inspect the actual Android EditText at $name.',
        );
        if (hostError != null) throw StateError(hostError!);
        return hostResult ?? {};
      }

      Future<Json> live() async {
        await waitFor(
          tester,
          () =>
              find.byType(Texture).evaluate().isNotEmpty &&
              find
                  .descendant(
                    of: find.byType(RemotePage),
                    matching: find.byType(CircularProgressIndicator),
                  )
                  .evaluate()
                  .isEmpty &&
              find.text('画面已暂停').evaluate().isEmpty,
          timeout: const Duration(seconds: 45),
          reason: 'The production Flutter decoder must render the real target.',
        );
        final current = (await sessions()).singleWhere(
          (item) =>
              item['status'] == 'streaming' &&
              !initialSessionIds.contains(id(item)),
        );
        sessionId = id(current);
        expect(current['firstFrameDecoded'], isTrue);
        expect(current['evidence'], 'mdk.snapshot');
        expectHealthyRemote();
        return current;
      }

      try {
        await controller.updateSetting('deviceSettings', <String, dynamic>{});

        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'attemptId': 'remote-ime-${DateTime.now().microsecondsSinceEpoch}',
          }),
        );
        expect(deviceId, isNotEmpty);
        createdDevice = !initialDevices.any((item) => item['id'] == deviceId);
        initiallyConnected = initialDevices.any(
          (item) => item['id'] == deviceId && item['status'] == 'connected',
        );
        await request('devices.connect', {'deviceId': deviceId});
        initialSessionIds.addAll(
          (await sessions()).where((s) => s['status'] != 'stopped').map(id),
        );
        expect(
          initialSessionIds,
          isEmpty,
          reason:
              'Use a target without another person’s active control session.',
        );
        WorkspaceRoute(deviceId: deviceId!)
            .go(tester.element(find.byType(Scaffold).first));
        await waitFor(
          tester,
          () => find.byType(DeviceWorkspacePage).evaluate().isNotEmpty,
          reason: 'Open the production device workspace.',
        );
        await tapPageAction(
          tester,
          find.byType(DeviceWorkspacePage),
          find.text('打开手机屏幕'),
        );
        await live();
        await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isEmpty,
          reason: 'Return to the workspace retaining this exact session.',
        );
        SessionToolsRoute(
          deviceId: deviceId,
          sessionId: sessionId,
        ).push<void>(tester.element(find.byType(Scaffold).first));
        await waitFor(
          tester,
          () =>
              find.byType(SessionToolsPage).evaluate().isNotEmpty &&
              find.text('使用本机键盘').evaluate().isNotEmpty &&
              find
                  .descendant(
                    of: find.byType(SessionToolsPage),
                    matching: find.byType(Scrollable),
                  )
                  .evaluate()
                  .isNotEmpty,
          reason:
              'The public input tools must finish loading before scrolling.',
        );
        await tapPageAction(
          tester,
          find.byType(SessionToolsPage),
          find.text('使用本机键盘'),
        );
        final current = await live();
        final coordinates = await host('prepare-settings');
        final width = (current['width'] as num).toInt();
        final height = (current['height'] as num).toInt();
        final x =
            ((coordinates['x'] as num) * width / (coordinates['width'] as num))
                .round()
                .clamp(0, width - 1);
        final y =
            ((coordinates['y'] as num) *
                    height /
                    (coordinates['height'] as num))
                .round()
                .clamp(0, height - 1);
        // Actual scrcpy touch via the public runtime; this is not a tester tap
        // against the Flutter video surface. The host never taps the target.
        for (final action in ['down', 'up']) {
          await request('session.touch', {
            'sessionId': sessionId,
            'action': action,
            'pointerId': 41,
            'x': x,
            'y': y,
            'screenWidth': width,
            'screenHeight': height,
            'pressure': action == 'up' ? 0.0 : 1.0,
          });
        }
        await host('focused-empty');
        targetFocused = true;
        final fieldFinder = find.descendant(
          of: find.byType(RemotePage),
          matching: find.byType(TextField),
        );
        await waitFor(
          tester,
          () =>
              fieldFinder.evaluate().length == 1 &&
              tester.widget<TextField>(fieldFinder).focusNode!.hasFocus &&
              tester.testTextInput.hasAnyClients,
          reason: 'The public keyboard action must attach the hidden Flutter IME field.',
        );
        final baseline = tester.widget<TextField>(fieldFinder).controller!.text;
        const committed = '你好🙂';
        final composed = '$baseline$committed';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: composed,
            selection: TextSelection.collapsed(offset: composed.length),
            composing: TextRange(start: baseline.length, end: composed.length),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await host('composing-no-leak');
        // Critical regression: only composing changes; text and selection stay
        // identical, so TextField.onChanged alone would miss this commitment.
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: composed,
            selection: TextSelection.collapsed(offset: composed.length),
            composing: TextRange.empty,
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await host('committed-once');
        await tester.pump(const Duration(seconds: 2));
        await host('committed-still-once');
        binding.reportData!.addAll({
          'remoteImeComplete': true,
          'committedText': committed,
          'inputMethod':
              'Flutter TestTextInput editing values; no Gboard candidate UI',
          'targetFocusMethod':
              'session.touch through real scrcpy control transport',
          'decodedFrameVerified': true,
          'publicKeyboardActionVerified': true,
        });
        expect(tester.takeException(), isNull);
      } finally {
        // Settings started with an empty query. Restore only this fixture’s input
        // through its own control channel, then stop only the owned session.
        try {
          if (sessionId != null && !initialSessionIds.contains(sessionId)) {
            try {
              if (targetFocused) {
                await request('session.key', {
                  'sessionId': sessionId,
                  'keyCode': 29,
                  'metaState': 4096,
                  'action': 'press',
                });
                await request('session.key', {
                  'sessionId': sessionId,
                  'keyCode': 67,
                  'action': 'press',
                });
                await host('cleanup-empty');
                binding.reportData!['targetQueryRestored'] = true;
              }
            } finally {
              await request('session.stop', {
                'sessionId': sessionId,
                'keepTask': true,
              });
            }
          }
        } finally {
          try {
            await controller.focusDevice(initialFocus);
            await controller.updateSetting(
              'deviceSettings',
              jsonObject(initialSettings['deviceSettings']),
            );
          } finally {
            try {
              if (deviceId != null && createdDevice) {
                await request('devices.forget', {'deviceId': deviceId});
              } else if (deviceId != null &&
                  !initiallyConnected &&
                  initialSessionIds.isEmpty) {
                await request('devices.disconnect', {'deviceId': deviceId});
              }
            } finally {
              tester.testTextInput.unregister();
            }
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
