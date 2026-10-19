import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/main.dart' as app;

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = String.fromEnvironment('CONNECT_E2E_PORT');
  const secondPort = String.fromEnvironment('CONNECT_E2E_SECOND_PORT');
  final runId = 'focus-${DateTime.now().millisecondsSinceEpoch}';
  var stage = 'starting';
  final acknowledged = <String>{};
  final owned = <String, String>{};
  final sourceDevices = <String, String>{};
  AppController? controller;
  Future<Json> request(String command, [Json params = const {}]) =>
      controller!.request(command, params).timeout(const Duration(seconds: 40));
  developer.registerExtension('ext.connect.audioFocus', (_, params) async {
    if (params['ack'] case final String ack) acknowledged.add(ack);
    final statuses = <String, dynamic>{};
    if (params['action'] == 'status') {
      for (final entry in owned.entries) {
        try {
          statuses[entry.key] = await request('audio.status', {
            'sourceId': entry.value,
          });
        } catch (error) {
          statuses[entry.key] = {'unavailable': true, 'reason': '$error'};
        }
      }
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'runId': runId,
        'stage': stage,
        'owned': owned,
        'native': statuses,
        'core': params['action'] == 'status'
            ? await request('audio.sources')
            : null,
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      }),
    );
  });
  testWidgets(
    'real two-device audio mixing and competing Android application focus',
    (tester) async {
      await app.main();
      await tester.pump(const Duration(milliseconds: 300));
      controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      final original = {...controller!.snapshot().settings};
      final ownedSessions = <String>{};
      NavigatorState? remoteNavigator;
      var openPages = 0;
      Future<void> host(String phase) async {
        stage = phase;
        await waitFor(
          tester,
          () => acknowledged.contains(phase),
          timeout: const Duration(seconds: 90),
          reason: 'Host must prove real AudioManager focus phase $phase.',
        );
      }

      try {
        expect(
          objects((await request('audio.sources'))['sources']).where(
            (s) => ['playing', 'paused', 'starting'].contains(s['status']),
          ),
          isEmpty,
          reason:
              'This isolated E2E must not stop a pre-existing sound source.',
        );
        await controller!.updateSetting('deviceSettings', <String, dynamic>{});
        await controller!.updateSetting('backgroundKeepAlive', true);
        await host('prepare');
        final devices = <String>[];
        for (final endpoint in [port, secondPort]) {
          final id = responseDeviceId(
            await request('devices.add', {
              'address': address,
              'port': int.parse(endpoint),
              'attemptId': '$runId-$endpoint',
            }),
          );
          expect(id, isNotEmpty);
          if (id == null) fail('The real device record must have an ID.');
          await request('devices.connect', {'deviceId': id});
          devices.add(id);
        }
        expect(devices[0], isNot(devices[1]));
        await controller!.refreshDevices();
        for (var i = 0; i < devices.length; i++) {
          final before = objects((await request('session.list'))['sessions'])
              .map((s) => value(s, 'sessionId'))
              .toSet();
          final context = i == 0
              ? tester.element(find.byType(Scaffold).first)
              : tester.element(find.byType(RemotePage));
          unawaited(RemoteRoute(deviceId: devices[i]).push<void>(context));
          openPages++;
          await waitFor(
            tester,
            () => find.byType(RemotePage).evaluate().isNotEmpty,
            reason: 'Device audio belongs to an actual open remote page.',
          );
          remoteNavigator = Navigator.of(
            tester.element(find.byType(RemotePage)),
            rootNavigator: true,
          );
          final deadline = DateTime.now().add(const Duration(seconds: 40));
          Json? source;
          while (DateTime.now().isBefore(deadline)) {
            source = objects((await request('audio.sources'))['sources'])
                .where(
                  (s) =>
                      s['deviceId'] == devices[i] && s['status'] == 'playing',
                )
                .firstOrNull;
            if (source != null) break;
            await tester.pump(const Duration(milliseconds: 300));
          }
          expect(
            source,
            isNotNull,
            reason: 'Opening a remote page must start its device sound.',
          );
          source = source!;
          ownedSessions.addAll(
            objects((await request('session.list'))['sessions'])
                .map((s) => value(s, 'sessionId'))
                .toSet()
                .difference(before),
          );
          expect(source['status'], 'playing');
          owned['${i + 1}'] = value(source, 'sourceId');
          sourceDevices[value(source, 'sourceId')] = devices[i];
          final duplicate = await request('audio.start', {
            'deviceId': devices[i],
          });
          expect(duplicate['sourceId'], source['sourceId']);
        }
        expect(owned.values.toSet(), hasLength(2));
        final sources = objects((await request('audio.sources'))['sources']);
        expect(
          sources.where(
            (s) =>
                owned.containsValue(s['sourceId']) && s['status'] == 'playing',
          ),
          hasLength(2),
        );
        await request('audio.pause', {
          'deviceId': devices[0],
          'sourceId': owned['1'],
        });
        await host('transient');
        final paused = await request('audio.status', {'sourceId': owned['1']});
        final resumed = await request('audio.status', {'sourceId': owned['2']});
        expect(paused['manualPaused'], isTrue);
        expect(paused['focusPaused'], isFalse);
        expect(paused['playState'], 'paused');
        expect(resumed['playState'], 'playing');
        await request('audio.resume', {
          'deviceId': devices[0],
          'sourceId': owned['1'],
        });
        expect(
          (await request('audio.status', {
            'sourceId': owned['1'],
          }))['playState'],
          'playing',
        );
        await host('permanent');
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(
          objects((await request('audio.sources'))['sources']).where(
            (s) =>
                owned.containsValue(s['sourceId']) &&
                ['playing', 'paused', 'starting'].contains(s['status']),
          ),
          isEmpty,
          reason: 'A permanent focus loss must not automatically revive old source IDs.',
        );
        final replacement = await request('audio.start', {
          'deviceId': devices[1],
        });
        expect(replacement['status'], 'playing');
        expect(owned.containsValue(replacement['sourceId']), isFalse);
        owned['3'] = value(replacement, 'sourceId');
        sourceDevices[value(replacement, 'sourceId')] = devices[1];
        stage = 'complete';
        expect(tester.takeException(), isNull);
      } finally {
        while (openPages > 0 && remoteNavigator?.canPop() == true) {
          remoteNavigator!.pop();
          openPages--;
          await tester.pump(const Duration(milliseconds: 300));
        }
        for (final sessionId in ownedSessions) {
          await request('session.stop', {'sessionId': sessionId});
        }
        for (final sourceId in owned.values.toList()) {
          try {
            await request('audio.stop', {
              'sourceId': sourceId,
              'deviceId': sourceDevices[sourceId],
            });
          } catch (_) {
            /* Reclaimed source IDs must not stop their replacement. */
          }
        }
        for (final key in ['backgroundKeepAlive', 'deviceSettings']) {
          if (original.containsKey(key)) {
            await controller!.updateSetting(key, original[key]);
          }
        }
      }
      expect(tester.takeException(), isNull);
      binding.reportData ??= {};
      binding.reportData!['audioFocusAcceptanceComplete'] = true;
    },
    skip: address.isEmpty || port.isEmpty || secondPort.isEmpty,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
