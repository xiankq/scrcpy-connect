import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/connection/connection_validation.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/main.dart' as app;

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = String.fromEnvironment('CONNECT_E2E_PORT');
  const lifecycleTest = bool.fromEnvironment('CONNECT_E2E_AUDIO_LIFECYCLE');
  var stage = 'starting';
  final returned = <String>{};
  AppController? active;
  String? activeSource;
  developer.registerExtension('ext.connect.audio', (_, params) async {
    if (params['returned'] case final String phase) returned.add(phase);
    final state = params['action'] == 'status' && activeSource != null
        ? await active!.request('audio.status', {'sourceId': activeSource})
        : null;
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'stage': stage,
        'state': state,
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      }),
    );
  });
  testWidgets(
    'real shared audio start, volume, mute, deduplication and stop',
    (tester) async {
      await app.main();
      await tester.pump(const Duration(milliseconds: 300));
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      active = controller;
      final originalBackground =
          controller.snapshot().settings['backgroundKeepAlive'] == true;
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 35));
      String? deviceId;
      String? sourceId;
      NavigatorState? remoteNavigator;
      final ownedSessions = <String>{};
      try {
        await controller.updateSetting('backgroundKeepAlive', false);
        final added = await request('devices.add', {
          'address': address,
          'port': int.parse(port),
          'attemptId': 'shared-audio-${DateTime.now().microsecondsSinceEpoch}',
        });
        deviceId = responseDeviceId(added);
        expect(deviceId, isNotEmpty);
        await request('devices.connect', {'deviceId': deviceId});
        await controller.refreshDevices();
        final baselineSessions = objects(
          (await request('session.list'))['sessions'],
        ).map((s) => value(s, 'sessionId')).toSet();
        unawaited(
          RemoteRoute(deviceId: deviceId!)
              .push<void>(tester.element(find.byType(Scaffold).first)),
        );
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isNotEmpty,
          reason: 'The remote page owns automatic device sound.',
        );
        remoteNavigator = Navigator.of(
          tester.element(find.byType(RemotePage)),
          rootNavigator: true,
        );
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        Json? started;
        while (DateTime.now().isBefore(deadline)) {
          started = objects((await request('audio.sources'))['sources'])
              .where(
                (s) => s['deviceId'] == deviceId && s['status'] == 'playing',
              )
              .firstOrNull;
          if (started != null) break;
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(started, isNotNull);
        started = started!;
        ownedSessions.addAll(
          objects((await request('session.list'))['sessions'])
              .map((s) => value(s, 'sessionId'))
              .toSet()
              .difference(baselineSessions),
        );
        sourceId = value(started, 'sourceId');
        activeSource = sourceId;
        expect(sourceId, isNotEmpty);
        expect(
          started['status'],
          'playing',
          reason: 'The bridge must wait for shared media information, real playback confirmation and clock advance.',
        );
        expect(started['nativeAttached'], isTrue);
        final output = await request('audio.status', {'sourceId': sourceId});
        expect(output['backend'], 'media_codec');
        expect(output['sourcePcmReceived'], true);
        expect(output['playbackClockAdvanced'], true);
        expect(output.containsKey('bytesWritten'), false);
        expect(output['speakerSamplesVerified'], false);

        final duplicate = await request('audio.start', {'deviceId': deviceId});
        expect(
          duplicate['sourceId'],
          sourceId,
          reason: 'One device must share one capture source.',
        );
        var sources = objects((await request('audio.sources'))['sources'])
            .where((source) => source['deviceId'] == deviceId)
            .toList();
        expect(sources, hasLength(1));
        expect(sources.single['status'], 'playing');
        expect(sources.single['nativeAttached'], isTrue);

        final adjusted = await request('audio.volume', {
          'deviceId': deviceId,
          'sourceId': sourceId,
          'volume': .3,
          'muted': false,
        });
        expect(adjusted['volume'], closeTo(.3, .001));
        expect(adjusted['muted'], isFalse);
        final muted = await request('audio.volume', {
          'deviceId': deviceId,
          'sourceId': sourceId,
          'volume': .3,
          'muted': true,
        });
        expect(muted['muted'], isTrue);
        sources = objects((await request('audio.sources'))['sources'])
            .where((source) => source['deviceId'] == deviceId)
            .toList();
        expect(sources.single['muted'], isTrue);
        expect(sources.single['volume'], closeTo(.3, .001));

        final paused = await request('audio.pause', {
          'deviceId': deviceId,
          'sourceId': sourceId,
        });
        expect(paused['status'], 'paused');
        expect(paused['manualPaused'], isTrue);
        expect(paused['presentationOnly'], isFalse);
        var native = await request('audio.status', {'sourceId': sourceId});
        expect(native['playState'], 'paused');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        native = await request('audio.status', {'sourceId': sourceId});
        final pausedPosition = native['positionMs'] as int;
        await Future<void>.delayed(const Duration(seconds: 1));
        native = await request('audio.status', {'sourceId': sourceId});
        expect(
          (native['positionMs'] as int) - pausedPosition,
          lessThanOrEqualTo(40),
        );
        final resumed = await request('audio.resume', {
          'deviceId': deviceId,
          'sourceId': sourceId,
        });
        expect(resumed['status'], 'playing');
        expect(resumed['manualPaused'], isFalse);
        await Future<void>.delayed(const Duration(seconds: 1));
        native = await request('audio.status', {'sourceId': sourceId});
        expect(native['playState'], 'playing');
        expect(native['positionMs'] as int, greaterThan(pausedPosition));

        if (lifecycleTest) {
          stage = 'background-paused';
          await waitFor(
            tester,
            () => returned.contains(stage),
            timeout: const Duration(seconds: 45),
            reason: 'Host must HOME and verify actual paused shared playback clock.',
          );
          await waitFor(
            tester,
            () =>
                WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed,
            reason: 'Controller must actually return to the foreground.',
          );
          native = await request('audio.status', {'sourceId': sourceId});
          expect(native['playState'], 'playing');
          expect(native['backgroundPaused'], isFalse);
          await controller.updateSetting('backgroundKeepAlive', true);
          stage = 'background-playing';
          await waitFor(
            tester,
            () => returned.contains(stage),
            timeout: const Duration(seconds: 45),
            reason: 'Host must HOME and verify actual ongoing shared playback clock and media FGS.',
          );
          native = await request('audio.status', {'sourceId': sourceId});
          expect(native['playState'], 'playing');
          await controller.updateSetting('backgroundKeepAlive', false);
        }
        stage = 'complete';
        await request('audio.stop', {
          'deviceId': deviceId,
          'sourceId': sourceId,
        });
        sources = objects((await request('audio.sources'))['sources'])
            .where(
              (source) =>
                  source['deviceId'] == deviceId &&
                  source['status'] == 'playing',
            )
            .toList();
        expect(sources, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        activeSource = null;
        if (remoteNavigator?.canPop() == true) {
          remoteNavigator!.pop();
          await tester.pump(const Duration(milliseconds: 300));
        }
        for (final sessionId in ownedSessions) {
          await request('session.stop', {'sessionId': sessionId});
        }
        if (deviceId != null && deviceId.isNotEmpty) {
          await controller
              .request('audio.stop', {
                'deviceId': deviceId,
                if (sourceId != null && sourceId.isNotEmpty)
                  'sourceId': sourceId,
              })
              .timeout(const Duration(seconds: 10));
        }
        await controller.updateSetting(
          'backgroundKeepAlive',
          originalBackground,
        );
      }
      expect(tester.takeException(), isNull);
      binding.reportData ??= {};
      binding.reportData!['audioAcceptanceComplete'] = true;
    },
    skip: address.isEmpty || port.isEmpty,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
