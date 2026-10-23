import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/main.dart' as app;

import 'product_flow_test.dart' show expectHealthyRemote, waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = String.fromEnvironment('CONNECT_E2E_PORT');
  final runId = 'input-${DateTime.now().millisecondsSinceEpoch}';
  binding.reportData = {'nativeInputReleaseComplete': false};
  var stage = 'starting';
  String? sessionId;
  final acknowledgements = <String>{};
  developer.registerExtension('ext.connect.inputRelease', (_, params) async {
    if (params['action'] != null) acknowledgements.add(params['action']!);
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'stage': stage,
        'runId': runId,
        'sessionId': sessionId,
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      }),
    );
  });
  testWidgets(
    'real target dispatchKeyEvent observes key-up after actual controller HOME',
    (tester) async {
      final semantics = tester.ensureSemantics();
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
              .timeout(const Duration(seconds: 40));
      Future<void> host(String next, String ack) async {
        stage = next;
        final deadline = DateTime.now().add(const Duration(seconds: 75));
        while (!acknowledgements.contains(ack) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          acknowledgements,
          contains(ack),
          reason:
              'Independent host must verify real input fixture stage $next.',
        );
      }

      final originalSettings = {...controller.snapshot().settings};
      final initialDevices = objects(
        (await request('devices.list'))['devices'],
      );
      final originalFocus = controller.snapshot().focusedDeviceId;
      String? deviceId;
      var createdDevice = false;
      var initiallyConnected = false;
      var isolated = false;
      final observed = <Json>[];
      final subscription = controller
          .eventStream()
          .where((e) => value(e, 'type').startsWith('session.'))
          .listen(observed.add);
      try {
        await controller.updateSetting('deviceSettings', <String, dynamic>{});

        await host('prepare', 'prepared');
        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': int.parse(port),
            'attemptId': runId,
          }),
        );
        expect(deviceId, isNotEmpty);
        createdDevice = !initialDevices.any(
          (device) => device['id'] == deviceId,
        );
        initiallyConnected = initialDevices.any(
          (device) =>
              device['id'] == deviceId && device['status'] == 'connected',
        );
        final connected = await request('devices.connect', {
          'deviceId': deviceId,
        });
        expect(connected['device'], isA<Map<Object?, Object?>>());
        final device = jsonObject(connected['device']);
        expect(device['status'], 'connected');
        await controller.updateSetting('deviceSettings', {
          deviceId!: {'wakeOnConnect': true},
        });
        expect(
          objects(
            (await request('session.list'))['sessions'],
          ).where((s) => s['deviceId'] == deviceId && s['status'] != 'stopped'),
          isEmpty,
          reason: 'The fixture must use an isolated target without disrupting existing sessions.',
        );
        isolated = true;
        openRemoteRoute(
          tester.element(find.byType(Scaffold).first),
          deviceId: value(device, 'id'),
        );
        await waitFor(
          tester,
          () =>
              find.byType(Texture).evaluate().isNotEmpty &&
              find.text('画面已暂停').evaluate().isEmpty &&
              find
                  .descendant(
                    of: find.byType(RemotePage),
                    matching: find.byType(CircularProgressIndicator),
                  )
                  .evaluate()
                  .isEmpty,
          reason:
              'Actual native rendering must precede the physical input test.',
        );
        final rendered = objects(
          (await request('session.list', {'deviceId': deviceId}))['sessions'],
        ).singleWhere((session) => session['status'] == 'streaming');
        expect(rendered['firstFrameDecoded'], isTrue);
        expect(rendered['evidence'], 'media_codec.snapshot');
        expect(
          rendered['textureId'],
          tester.widget<Texture>(find.byType(Texture)).textureId,
        );
        sessionId = value(rendered, 'sessionId');
        expect(sessionId, isNotEmpty);
        expectHealthyRemote();
        await host('arm', 'armed');
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          WidgetsBinding.instance.lifecycleState,
          AppLifecycleState.resumed,
        );
        observed.clear();
        // Public Flutter hardware-key input traverses the real product handler,
        // FRB, scrcpy control transport and Android InputManager injection.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 200));
        // Host first proves native DOWN=1/UP=0, then actually sends HOME to the
        // controller and independently proves native UP=1 on the target.
        await host('hold', 'returned');
        await waitFor(
          tester,
          () {
            bool owns(Json event) =>
                (event['data'] as Map<Object?, Object?>?)?['sessionId'] ==
                sessionId;
            final pause = observed.indexWhere(
              (e) =>
                  owns(e) &&
                  e['type'] == 'session.updated' &&
                  (e['data'] as Map<Object?, Object?>?)?['status'] == 'paused',
            );
            if (pause < 0) return false;
            final resume = observed.indexWhere(
              (e) =>
                  owns(e) &&
                  e['type'] == 'session.updated' &&
                  (e['data'] as Map<Object?, Object?>?)?['status'] ==
                      'streaming',
              pause + 1,
            );
            return resume >= 0 &&
                observed
                    .skip(resume + 1)
                    .any(
                      (e) =>
                          owns(e) &&
                          e['type'] == 'session.output.resumed' &&
                          jsonObject(e['data'])['firstFrameDecoded'] == true &&
                          jsonObject(e['data'])['evidence'] ==
                              'media_codec.snapshot',
                    );
          },
          reason: 'The same real session must pause, resume and render a new actual native frame.',
        );
        await tester.pump(const Duration(milliseconds: 300));
        expectHealthyRemote();
        if (HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.arrowDown,
        )) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        }
        await tester.pump(const Duration(milliseconds: 300));
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
        expectHealthyRemote();
        await binding.takeScreenshot('remote-after-native-key-release');
        await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
        await tester.pump();
        await tester.ensureVisible(find.text('关闭画面'));
        await tester.tap(find.text('关闭画面'));
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isEmpty,
          reason: 'The real session must exit normally after release.',
        );
        final closeDeadline = DateTime.now().add(const Duration(seconds: 10));
        List<Json> remaining;
        do {
          remaining = objects((await request('session.list'))['sessions'])
              .where(
                (s) =>
                    value(s, 'sessionId', value(s, 'id')) == sessionId &&
                    s['status'] != 'stopped',
              )
              .toList();
          if (remaining.isEmpty) break;
          await tester.pump(const Duration(milliseconds: 100));
        } while (DateTime.now().isBefore(closeDeadline));
        expect(
          remaining,
          isEmpty,
          reason: 'Close releases the exact window after draining input.',
        );
        await host('verify-exit', 'verified');
        stage = 'complete';
        binding.reportData!.addAll({
          'nativeInputReleaseComplete': true,
          'sessionId': sessionId,
        });
        expect(tester.takeException(), isNull);
      } finally {
        if (HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.arrowDown,
        )) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        }
        await subscription.cancel();
        try {
          if (sessionId?.isNotEmpty == true &&
              objects((await request('session.list'))['sessions']).any(
                (s) => value(s, 'sessionId', value(s, 'id')) == sessionId,
              )) {
            await request('session.stop', {
              'sessionId': sessionId,
              'keepTask': true,
            });
          }
        } finally {
          await controller.updateSetting(
            'deviceSettings',
            jsonObject(originalSettings['deviceSettings']),
          );
          await controller.focusDevice(originalFocus);
          if (createdDevice && deviceId != null) {
            await request('devices.forget', {'deviceId': deviceId});
          } else if (!initiallyConnected && isolated && deviceId != null) {
            await request('devices.disconnect', {'deviceId': deviceId});
          }
          semantics.dispose();
        }
      }
    },
    skip: address.isEmpty || port.isEmpty,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
