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
      await tester.pump(const Duration(milliseconds: 300));
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 40));
      Future<void> host(String next, String ack) async {
        stage = next;
        await waitFor(
          tester,
          () => acknowledgements.contains(ack),
          timeout: const Duration(seconds: 75),
          reason:
              'Independent host must verify real input fixture stage $next.',
        );
      }

      final originalSettings = {...controller.snapshot().settings};
      final observed = <Json>[];
      final subscription = controller
          .eventStream()
          .where((e) => value(e, 'type').startsWith('session.'))
          .listen(observed.add);
      try {
        await controller.updateSetting('deviceSettings', <String, dynamic>{});

        await host('prepare', 'prepared');
        final deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': int.parse(port),
            'attemptId': runId,
          }),
        );
        expect(deviceId, isNotEmpty);
        final connected = await request('devices.connect', {
          'deviceId': deviceId,
        });
        expect(connected['device'], isA<Map<Object?, Object?>>());
        final device = jsonObject(connected['device']);
        expect(device['status'], 'connected');
        expect(
          objects(
            (await request('session.list'))['sessions'],
          ).where((s) => s['deviceId'] == deviceId && s['status'] != 'stopped'),
          isEmpty,
          reason: 'The fixture must use an isolated target without disrupting existing sessions.',
        );
        openRemoteRoute(
          tester.element(find.byType(Scaffold).first),
          deviceId: value(device, 'id'),
        );
        await waitFor(
          tester,
          () =>
              find.byType(Texture).evaluate().isNotEmpty &&
              observed.any(
                (e) =>
                    e['type'] == 'session.frame' &&
                    e['deviceId'] == deviceId &&
                    ((e['data'] as Map<Object?, Object?>?)?['framesDecoded']
                                as num? ??
                            0) >
                        0,
              ),
          reason:
              'Actual native rendering must precede the physical input test.',
        );
        final frame = observed.lastWhere(
          (e) => e['type'] == 'session.frame' && e['deviceId'] == deviceId,
        );
        sessionId = value(jsonObject(frame['data']), 'sessionId');
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
                          e['type'] == 'session.frame' &&
                          ((e['data']
                                          as Map<
                                            Object?,
                                            Object?
                                          >?)?['framesDecoded']
                                      as num? ??
                                  0) >
                              0,
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
        await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isEmpty,
          reason: 'The real session must exit normally after release.',
        );
        expect(
          objects((await request('session.list'))['sessions']).where(
            (s) =>
                value(s, 'sessionId', value(s, 'id')) == sessionId &&
                s['status'] != 'stopped',
          ),
          isEmpty,
        );
        await host('verify-exit', 'verified');
        stage = 'complete';
        expect(tester.takeException(), isNull);
      } finally {
        if (HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.arrowDown,
        )) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        }
        await subscription.cancel();
        try {
          if (sessionId?.isNotEmpty == true) {
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
          semantics.dispose();
        }
      }
    },
    skip: address.isEmpty || port.isEmpty,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
