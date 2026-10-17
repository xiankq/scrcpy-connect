import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/main.dart' as app;

import 'product_flow_test.dart' show expectHealthyRemote, waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = String.fromEnvironment('CONNECT_E2E_PORT');
  testWidgets(
    'each actually available target encoder and local decoder renders through the product remote page',
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
      final originalSettings = {...controller.snapshot().settings};
      final outputs = <Json>[];
      final subscription = controller
          .eventStream()
          .where((event) => event['type'] == 'session.output.ready')
          .listen(outputs.add);
      String? deviceId;
      final originalSessions = <String>{};
      var sessionsCaptured = false;
      var capturedSurface = false;
      final results = <Json>[];
      binding.reportData ??= {};
      binding.reportData!['videoCodecResults'] = results;
      try {
        await controller.updateSetting('clipboardSync', false);
        await controller.updateSetting('audioDevices', []);
        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': int.parse(port),
            'attemptId': 'codecs-${DateTime.now().microsecondsSinceEpoch}',
          }),
        );
        expect(deviceId, isNotEmpty);
        final connected = await request('devices.connect', {
          'deviceId': deviceId,
        });
        expect(connected['device'], isA<Map<Object?, Object?>>());
        final device = jsonObject(connected['device']);
        expect(device['status'], 'connected');
        final existing = objects((await request('session.list'))['sessions']);
        originalSessions.addAll(
          existing.map((s) => value(s, 'sessionId', value(s, 'id'))),
        );
        sessionsCaptured = true;
        expect(
          existing.where(
            (s) => s['deviceId'] == deviceId && s['status'] != 'stopped',
          ),
          isEmpty,
          reason: 'Use an isolated target; existing device sessions must be retained.',
        );
        // This is an explicit test action, never automatic product wake-up.
        await request('devices.wake', {'deviceId': deviceId});
        final local = await request('video.capabilities');
        final localCodecs = objects(local['codecs']);
        expect(
          localCodecs,
          isNotEmpty,
          reason: 'Shared runtime codec candidates are required.',
        );
        final options = await request('session.quality.options', {
          'deviceId': deviceId,
        });
        final codecs = objects(options['codecs']);
        expect(codecs.map((c) => value(c, 'id')).toSet(), {
          'h264',
          'h265',
          'av1',
          'vp8',
          'vp9',
        });
        for (final choice in codecs) {
          final codec = value(choice, 'id');
          final decoders = localCodecs.where((item) => item['id'] == codec);
          final decoderAvailable =
              decoders.isNotEmpty &&
              (decoders.first['available'] == true ||
                  decoders.first['canAttempt'] == true);
          final available =
              choice['available'] == true &&
              (choice['targetStatus'] ?? choice['status']) == 'available' &&
              decoderAvailable;
          if (!available) {
            final reason = value(choice, 'reason');
            expect(
              reason,
              isNotEmpty,
              reason: 'Every codec excluded by the actual capability intersection needs a reason.',
            );
            final result = {
              'codec': codec,
              'status': 'unavailable',
              'reason': reason,
              'targetStatus': choice['targetStatus'] ?? choice['status'],
              'decoderStatus': choice['decoderStatus'],
            };
            results.add(result);
            debugPrint(jsonEncode({'videoCodecResult': result}));
            continue;
          }
          final saved = await request('session.quality', {
            'deviceId': deviceId,
            'videoCodec': codec,
            'videoEncoder': null,
          });
          expect(saved['appliesNextSession'], isTrue);
          outputs.clear();
          openRemoteRoute(
            tester.element(find.byType(Scaffold).first),
            deviceId: value(device, 'id'),
          );
          await waitFor(
            tester,
            () =>
                find.byType(Texture).evaluate().isNotEmpty &&
                outputs.any(
                  (event) =>
                      event['deviceId'] == deviceId &&
                      (event['data']
                              as Map<
                                Object?,
                                Object?
                              >?)?['firstFrameDecoded'] ==
                          true &&
                      (event['data'] as Map<Object?, Object?>?)?['evidence'] ==
                          'mdk.snapshot',
                ),
            timeout: const Duration(seconds: 45),
            reason:
                '$codec must produce a real decoded pixels and product Texture.',
          );
          await tester.pump(const Duration(milliseconds: 300));
          expectHealthyRemote();
          final sessions = objects((await request('session.list'))['sessions']);
          final session = sessions.singleWhere(
            (s) => s['deviceId'] == deviceId && s['status'] == 'streaming',
          );
          expect(
            session['codec'],
            codec,
            reason: 'The new session must use the persisted selected format.',
          );
          expect(session['backend'], 'fvp');
          expect(session['firstFrameDecoded'], true);
          expect(session['evidence'], 'mdk.snapshot');
          final id = value(session, 'sessionId', value(session, 'id'));
          expect(
            outputs.any(
              (event) =>
                  (event['data'] as Map<Object?, Object?>?)?['sessionId'] ==
                      id &&
                  (event['data']
                          as Map<Object?, Object?>?)?['firstFrameDecoded'] ==
                      true,
            ),
            true,
          );
          expect(
            find.descendant(
              of: find.byType(RemotePage),
              matching: find.byType(AppBar),
            ),
            findsNothing,
          );
          if (!capturedSurface) {
            await binding.convertFlutterSurfaceToImage();
            capturedSurface = true;
          }
          await tester.pump(const Duration(milliseconds: 300));
          expectHealthyRemote();
          await binding.takeScreenshot('remote-codec-$codec-live');
          final result = {
            'codec': codec,
            'status': 'rendered',
            'backend': session['backend'],
            'evidence': session['evidence'],
            'firstFrameDecoded': session['firstFrameDecoded'],
          };
          results.add(result);
          debugPrint(jsonEncode({'videoCodecResult': result}));
          await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
          await waitFor(
            tester,
            () => find.byType(RemotePage).evaluate().isEmpty,
            reason: '$codec must exit through the real floating control.',
          );
          await tester.pump(const Duration(milliseconds: 400));
          final retained = objects((await request('session.list'))['sessions'])
              .singleWhere((s) => value(s, 'sessionId', value(s, 'id')) == id);
          expect(retained['status'], 'paused');
          expect(retained['capturePaused'], true);
          // Each codec requires a new capture, rather than resuming an old one.
          await request('session.stop', {'sessionId': id, 'keepTask': true});
          expect(
            objects((await request('session.list'))['sessions'])
                .where((s) => value(s, 'sessionId', value(s, 'id')) == id),
            isEmpty,
          );
        }
        expect(
          results.where((result) => result['status'] == 'rendered'),
          isNotEmpty,
          reason: 'Capability explanations alone do not prove actual video rendering.',
        );
        expect(tester.takeException(), isNull);
      } finally {
        final cleanupErrors = <Object>[];
        Future<void> cleanup(Future<void> Function() action) async {
          try {
            await action();
          } catch (error) {
            cleanupErrors.add(error);
          }
        }

        await cleanup(subscription.cancel);
        if (deviceId != null && sessionsCaptured) {
          final cleanupDevice = deviceId;
          await cleanup(() async {
            for (final session
                in objects((await request('session.list'))['sessions']).where(
                  (s) =>
                      s['deviceId'] == deviceId &&
                      !originalSessions.contains(
                        value(s, 'sessionId', value(s, 'id')),
                      ),
                )) {
              await request('session.stop', {
                'sessionId': session['sessionId'] ?? session['id'],
                'keepTask': true,
              });
            }
          });
          await cleanup(() async {
            final latest = await request('settings.get');
            final overrides = latest['deviceQuality'] is Map<Object?, Object?>
                ? jsonObject(latest['deviceQuality'])
                : <String, dynamic>{};
            final originals = jsonObject(originalSettings['deviceQuality']);
            if (originals.containsKey(cleanupDevice)) {
              overrides[cleanupDevice] = originals[cleanupDevice];
            } else {
              overrides.remove(cleanupDevice);
            }
            await request('settings.update', {'deviceQuality': overrides});
          });
        }
        await cleanup(
          () => controller.updateSetting(
            'audioDevices',
            originalSettings['audioDevices'] ?? [],
          ),
        );
        await cleanup(
          () => controller.updateSetting(
            'clipboardSync',
            originalSettings['clipboardSync'] == true,
          ),
        );
        semantics.dispose();
        expect(
          cleanupErrors,
          isEmpty,
          reason: 'The test must restore its device preferences and close only its own sessions.',
        );
      }
      expect(tester.takeException(), isNull);
      binding.reportData!['mediaAcceptanceComplete'] = true;
    },
    skip: address.isEmpty || port.isEmpty,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
