import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/activities/activities_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = String.fromEnvironment('CONNECT_E2E_PORT');
  testWidgets(
    'stop real device sound from current activities without disconnecting',
    (tester) async {
      expect(address, isNotEmpty);
      expect(int.tryParse(port), inInclusiveRange(1, 65535));
      binding.reportData = {'audioActivitiesComplete': false};
      final report = binding.reportData!;
      await app.main();
      await waitFor(
        tester,
        () => find.byType(ConnectApp).evaluate().isNotEmpty,
        reason: 'Production app must initialize before taking its baseline.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
        reason:
            'Production bootstrap must settle before preserving preferences.',
      );
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 40));
      final originalSettings = {...controller.snapshot().settings};
      final baselineDevices = objects(
        (await request('devices.list'))['devices'],
      );
      final baselineIds = baselineDevices.map((d) => value(d, 'id')).toSet();
      final baselineSessions = objects(
        (await request('session.list'))['sessions'],
      ).map((s) => value(s, 'sessionId')).toSet();
      final baselineSources = objects(
        (await request('audio.sources'))['sources'],
      ).map((s) => value(s, 'sourceId')).toSet();
      String? deviceId;
      String? sourceId;
      Json? originalObservation;
      var connectedByTest = false;
      var observationStarted = false;
      try {
        await controller.updateSetting('audioDevices', []);
        await controller.updateSetting('audioMode', 'mix');
        await controller.updateSetting('clipboardSync', false);
        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': int.parse(port),
            'attemptId':
                'audio-activity-${DateTime.now().microsecondsSinceEpoch}',
          }),
        );
        expect(deviceId, isNotNull);
        expect(deviceId, isNotEmpty);
        final previousDevice = baselineDevices
            .where((d) => d['id'] == deviceId)
            .firstOrNull;
        connectedByTest = previousDevice?['status'] != 'connected';
        if (connectedByTest) {
          await request('devices.connect', {'deviceId': deviceId});
        }
        originalObservation = await request('observation.status', {
          'deviceId': deviceId,
        });
        observationStarted = originalObservation['wanted'] != true;
        var observation = await request('observation.start', {
          'deviceId': deviceId,
        });
        final observationDeadline = DateTime.now().add(
          const Duration(seconds: 20),
        );
        while (observation['phase'] == 'starting' &&
            DateTime.now().isBefore(observationDeadline)) {
          await tester.pump(const Duration(milliseconds: 200));
          observation = await request('observation.status', {
            'deviceId': deviceId,
          });
        }
        expect(observation['wanted'], isTrue);
        expect(['observing', 'limited'], contains(observation['phase']));
        expect(
          objects((await request('audio.sources'))['sources']).where(
            (s) =>
                s['deviceId'] == deviceId &&
                ['playing', 'paused', 'starting'].contains(s['status']),
          ),
          isEmpty,
          reason: 'The test may only stop an audio source it created.',
        );
        final started = await request('audio.start', {'deviceId': deviceId});
        sourceId = value(started, 'sourceId');
        expect(sourceId, isNotEmpty);
        expect(baselineSources, isNot(contains(sourceId)));
        expect(started['status'], 'playing');
        final output = await request('audio.status', {'sourceId': sourceId});
        for (final flag in [
          'mediaInfoReady',
          'playingConfirmed',
          'sourcePcmReceived',
          'playbackClockAdvanced',
        ]) {
          expect(output[flag], isTrue, reason: flag);
        }
        expect(output['backend'], 'fvp');
        report['actualPlaybackReady'] = true;
        report['deviceId'] = deviceId;
        report['sourceId'] = sourceId;
        final activities = objects(
          (await request('activities.list'))['activities'],
        );
        final audioActivity = activities.singleWhere(
          (a) => a['id'] == 'audio:$sourceId',
        );
        expect(audioActivity['deviceId'], deviceId);
        expect(audioActivity['sourceId'], sourceId);
        expect(audioActivity['name'], '设备声音');
        expect(audioActivity['canStop'], isTrue);
        const ActivitiesRoute().push<void>(
          tester.element(find.byType(Scaffold).first),
        );
        await waitFor(
          tester,
          () => find.byType(ActivitiesPage).evaluate().isNotEmpty,
          reason: 'The production current activities page must open.',
        );
        final row = find.byWidgetPredicate(
          (widget) =>
              widget is ActionRow &&
              widget.title == '设备声音' &&
              widget.subtitle?.startsWith(
                    '${value(audioActivity, 'deviceName')} · ',
                  ) ==
                  true,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.scrollUntilVisible(
          row,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ActivitiesPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(row, findsOneWidget);
        await Scrollable.ensureVisible(tester.element(row), alignment: .5);
        await tester.pump(const Duration(milliseconds: 500));
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot('audio-activity-playing');
        await tester.tap(find.descendant(of: row, matching: find.text('停止')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('停止“设备声音”？'), findsOneWidget);
        expect(find.text(value(audioActivity, 'stopImpact')), findsOneWidget);
        await binding.takeScreenshot('audio-activity-confirm');
        await tester.tap(find.text('停止活动'));
        await waitFor(
          tester,
          () => row.evaluate().isEmpty,
          reason: 'Confirmed stop must refresh the activity projection.',
        );
        final sources = objects((await request('audio.sources'))['sources']);
        expect(sources.where((s) => s['sourceId'] == sourceId), isEmpty);
        report['coreSourceAbsent'] = true;
        final local = await request('audio.status');
        expect(
          objects(local['sources']).where((s) => s['sourceId'] == sourceId),
          isEmpty,
        );
        var exactOutputEnded = false;
        try {
          await request('audio.status', {'sourceId': sourceId});
        } on RequestFailure catch (error) {
          exactOutputEnded = error.code == 'audio_source_required';
        }
        expect(exactOutputEnded, isTrue);
        report['localOutputAbsent'] = true;
        final remaining = objects(
          (await request('activities.list'))['activities'],
        );
        expect(remaining.where((a) => a['id'] == 'audio:$sourceId'), isEmpty);
        expect(
          remaining.where((a) => a['id'] == 'connection:$deviceId'),
          hasLength(1),
        );
        expect(
          remaining.where((a) => a['id'] == 'observation:$deviceId'),
          hasLength(1),
        );
        final devices = objects((await request('devices.list'))['devices']);
        expect(
          devices.singleWhere((d) => d['id'] == deviceId)['status'],
          'connected',
        );
        report['connectionPreserved'] = true;
        final observedAfter = await request('observation.status', {
          'deviceId': deviceId,
        });
        expect(observedAfter['wanted'], observation['wanted']);
        expect(observedAfter['generation'], observation['generation']);
        expect(observedAfter['phase'], observation['phase']);
        report['observationPreserved'] = true;
        expect(
          objects((await request('session.list'))['sessions'])
              .map((s) => value(s, 'sessionId'))
              .toSet(),
          containsAll(baselineSessions),
        );
        expect(
          sources.map((s) => value(s, 'sourceId')).toSet(),
          containsAll(baselineSources),
        );
        report['baselineMediaPreserved'] = true;
        await tester.pump(const Duration(milliseconds: 400));
        await binding.takeScreenshot(
          'audio-activity-stopped-connection-preserved',
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (sourceId != null && deviceId != null) {
          final sources = objects((await request('audio.sources'))['sources']);
          if (sources.any((s) => s['sourceId'] == sourceId)) {
            await request('audio.stop', {
              'sourceId': sourceId,
              'deviceId': deviceId,
            });
          }
        }
        if (deviceId != null) {
          if (!baselineIds.contains(deviceId)) {
            await request('devices.forget', {'deviceId': deviceId});
          } else {
            if (observationStarted) {
              await request('observation.stop', {'deviceId': deviceId});
            }
            if (connectedByTest) {
              await request('devices.disconnect', {'deviceId': deviceId});
            }
          }
        }
        for (final key in ['audioMode', 'audioDevices', 'clipboardSync']) {
          if (originalSettings.containsKey(key)) {
            await controller.updateSetting(key, originalSettings[key]);
          }
        }
        final finalIds = objects((await request('devices.list'))['devices'])
            .map((d) => value(d, 'id'))
            .toSet();
        expect(finalIds, baselineIds);
        report['ownedCleanupComplete'] = true;
      }
      report['audioActivitiesComplete'] = true;
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
