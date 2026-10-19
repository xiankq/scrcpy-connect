import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/remote_launch_intent.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'product_flow_test.dart' show waitFor;
import 'video_performance_test.dart' show pattern;

// A real adbd sits behind the host driver's per-connection TCP proxy. No device
// state or video endpoint is simulated; only this test's transport is cut.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var hostReady = false;
  String? checkpoint, acknowledged;
  developer.registerExtension('ext.connect.videoRecovery', (
    _,
    parameters,
  ) async {
    if (parameters['ready'] == 'true') hostReady = true;
    acknowledged = parameters['ack'] ?? acknowledged;
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'ready': hostReady,
        'checkpoint': checkpoint == null ? null : {'name': checkpoint},
      }),
    );
  });
  binding.reportData = {'videoRecoveryComplete': false};
  testWidgets(
    'visible phone screen recovers after its real ADB transport is cut',
    (tester) async {
      await waitFor(
        tester,
        () => hostReady,
        reason: 'Host must prepare the independent fixture and TCP proxy.',
      );
      await app.main();
      await waitFor(
        tester,
        () => find.byType(ConnectApp).evaluate().isNotEmpty,
        reason: 'Production app must initialize.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
        reason: 'Production startup reconciliation must finish.',
      );
      Future<Json> request(String command, [Json params = const {}]) async {
        final result = await tester.runAsync(
          () => controller
              .request(command, params)
              .timeout(const Duration(seconds: 40)),
        );
        if (result == null) throw StateError('Real command failed: $command');
        return result;
      }

      final initialSettings = {...controller.snapshot().settings};
      final initialDevices = objects(
        (await request('devices.list'))['devices'],
      );
      final events = <Json>[];
      final subscription = controller.eventStream().listen((event) {
        if (events.length < 300 &&
            const [
              'devices.changed',
              'session.disconnected',
              'session.failed',
              'session.updated',
              'session.frame',
            ].contains(event['type'])) {
          final data = jsonObject(event['data']);
          events.add({
            'type': event['type'],
            'deviceId': event['deviceId'],
            'sessionId': data['sessionId'],
            'status': data['status'],
            if (data['devices'] is List)
              'devices': [
                for (final d in objects(data['devices']))
                  {'id': d['id'], 'status': d['status']},
              ],
          });
        }
      });
      binding.reportData!['events'] = events;
      String? deviceId;
      var created = false;
      try {
        await controller.updateSetting('deviceSettings', <String, dynamic>{});

        final added = await request('devices.add', {
          'address': const String.fromEnvironment(
            'CONNECT_E2E_ADDRESS',
            defaultValue: '10.0.2.2',
          ),
          'port': const int.fromEnvironment(
            'CONNECT_E2E_PORT',
            defaultValue: 25557,
          ),
        });
        deviceId = responseDeviceId(added);
        expect(deviceId, isNotEmpty);
        created = !initialDevices.any((d) => d['id'] == deviceId);
        expect(
          created,
          true,
          reason: 'Use a fresh proxy endpoint, not another active device.',
        );
        await request('devices.connect', {'deviceId': deviceId});
        RemoteRoute(
          deviceId: deviceId!,
          $extra: const RemoteLaunchIntent(),
        ).push<void>(tester.element(find.byType(Scaffold).first));
        Future<Json> live({String? previous}) async {
          Json? current;
          await waitFor(
            tester,
            () =>
                find.byType(RemotePage).evaluate().isNotEmpty &&
                find.byType(Texture).evaluate().isNotEmpty,
            timeout: const Duration(seconds: 45),
            reason: 'Real phone video must be visible.',
          );
          final watch = Stopwatch()..start();
          while (watch.elapsed < const Duration(seconds: 30)) {
            final sessions = objects(
              (await request('session.list', {
                'deviceId': deviceId,
              }))['sessions'],
            );
            current = sessions
                .where(
                  (s) =>
                      s['status'] == 'streaming' &&
                      s['firstFrameDecoded'] == true &&
                      s['sessionId'] != previous,
                )
                .firstOrNull;
            if (current != null) return current;
            await tester.pump(const Duration(milliseconds: 100));
          }
          throw StateError(
            'The visible phone screen did not automatically recover a fresh decoded session.',
          );
        }

        final first = await live();
        final firstId = value(first, 'sessionId', value(first, 'id'));
        binding.reportData!['initialSessionId'] = firstId;
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        Future<void> presented(int expected, String stage) async {
          final samples = <int?>[];
          binding.reportData!['${stage}Pixels'] = samples;
          for (var attempt = 0; attempt < 10; attempt++) {
            await tester.pump(const Duration(milliseconds: 100));
            final bytes = await binding.takeScreenshot('$stage-$attempt');
            final codec = await ui.instantiateImageCodec(
              Uint8List.fromList(bytes),
            );
            final frame = await codec.getNextFrame();
            try {
              final rgba = await frame.image.toByteData();
              final rect = tester.getRect(find.byType(Texture).first);
              final sx =
                  frame.image.width *
                  tester.view.devicePixelRatio /
                  tester.view.physicalSize.width;
              final sy =
                  frame.image.height *
                  tester.view.devicePixelRatio /
                  tester.view.physicalSize.height;
              final actual = pattern(
                rgba!.buffer.asUint8List(),
                frame.image.width,
                frame.image.height,
                region: ui.Rect.fromLTWH(
                  rect.left * sx,
                  rect.top * sy,
                  rect.width * sx,
                  rect.height * sy,
                ),
              );
              samples.add(actual);
              if (actual == expected) return;
            } finally {
              frame.image.dispose();
              codec.dispose();
            }
          }
          fail(
            'Actual Flutter composition must present counter $expected at $stage; got $samples.',
          );
        }

        await presented(0, 'before-cut');
        checkpoint = 'cut-transport';
        await waitFor(
          tester,
          () => acknowledged == checkpoint,
          reason: 'Host must cut this actual ADB TCP connection.',
        );
        final recovery = Stopwatch()..start();
        final second = await live(previous: firstId);
        final secondId = value(second, 'sessionId', value(second, 'id'));
        binding.reportData!['recoveryMs'] = recovery.elapsedMilliseconds;
        binding.reportData!['recoveredSessionId'] = secondId;
        expect(secondId, isNot(firstId));
        for (final action in ['down', 'up']) {
          await request('session.key', {
            'sessionId': secondId,
            'keyCode': 20,
            'action': action,
          });
        }
        await presented(1, 'after-recovery');
        // A user stop must remain stopped, despite a later device state refresh.
        await request('session.stop', {'sessionId': secondId});
        await tester.pump(const Duration(seconds: 2));
        final remaining = objects(
          (await request('session.list', {'deviceId': deviceId}))['sessions'],
        );
        expect(
          remaining.where(
            (s) => !['stopped', 'failed', 'error'].contains(s['status']),
          ),
          isEmpty,
        );
      } finally {
        await subscription.cancel();
        if (deviceId != null && created) {
          await request('devices.disconnect', {'deviceId': deviceId});
          await request('devices.forget', {'deviceId': deviceId});
        }
        await controller.updateSetting(
          'deviceSettings',
          jsonObject(initialSettings['deviceSettings']),
        );
        // Removing the production app closes its bridge/provider container.
        // Restore owned runtime state before that teardown, not afterwards.
        await tester.pumpWidget(const SizedBox.shrink());
      }
      binding.reportData!['videoRecoveryComplete'] = true;
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
