import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/services/connection/connection_validation.dart';

import 'product_flow_test.dart' show expectHealthyRemote, waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  binding.reportData = {
    'stateRecoveryComplete': false,
    'mediaAcceptanceComplete': false,
  };
  testWidgets(
    'real snapshot reconciliation preserves live video and never recreates an ended window',
    (tester) async {
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
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
      final initialDevices = objects(
        (await request('devices.list'))['devices'],
      );
      final originalFocus = controller.snapshot().focusedDeviceId;
      String? deviceId;
      var createdDevice = false;
      var initiallyConnected = false;
      var isolated = false;
      final observed = <Json>[];
      final pendingAtMarkers = <bool>[];
      final subscription = controller.eventStream().listen((event) {
        if (value(event, 'type').startsWith('state.') ||
            (value(event, 'type').startsWith('session.') &&
                event['type'] != 'session.frame')) {
          observed.add(event);
        }
        if (event['type'] == 'state.resync') {
          pendingAtMarkers.add(controller.snapshot().reconciliationPending);
        }
      });
      String? ownedId;
      try {
        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'attemptId': 'recovery-${DateTime.now().microsecondsSinceEpoch}',
          }),
        )!;
        expect(deviceId, isNotEmpty);
        createdDevice = !initialDevices.any(
          (device) => device['id'] == deviceId,
        );
        initiallyConnected = initialDevices.any(
          (device) =>
              device['id'] == deviceId && device['status'] == 'connected',
        );
        await request('devices.connect', {'deviceId': deviceId});
        final existing = objects((await request('session.list'))['sessions'])
            .where((session) => session['deviceId'] == deviceId);
        expect(
          existing,
          isEmpty,
          reason: 'Use an isolated target with no preexisting sessions.',
        );
        isolated = true;
        await request('devices.wake', {'deviceId': deviceId});
        openRemoteRoute(
          tester.element(find.byType(Scaffold).first),
          deviceId: deviceId,
        );
        await waitFor(
          tester,
          () => find.byType(Texture).evaluate().isNotEmpty,
          reason: 'A real remote frame must exist before reconciliation.',
        );
        expectHealthyRemote();
        final initial = objects((await request('session.list'))['sessions'])
            .where((session) => session['deviceId'] == deviceId)
            .single;
        ownedId = value(initial, 'sessionId');
        expect(initial['evidence'], 'media_codec.snapshot');
        final watermarks = <int>[];
        for (final concurrent in [false, true]) {
          observed.clear();
          final results = await Future.wait([
            request('state.reconcile'),
            if (concurrent) request('state.reconcile'),
          ]);
          debugPrint(
            '[connect.recovery.test] concurrent=$concurrent snapshot=${results.first['sessions']}',
          );
          final sequence = results.first['sequence'];
          expect(sequence, isA<int>());
          expect(
            results.every((result) => result['sequence'] == sequence),
            isTrue,
          );
          watermarks.add(sequence as int);
          await waitFor(
            tester,
            () => observed.any(
              (event) =>
                  event['type'] == 'session.output.resumed' &&
                  jsonObject(event['data'])['sessionId'] == ownedId &&
                  jsonObject(event['data'])['evidence'] ==
                      'media_codec.snapshot',
            ),
            reason: 'The same actual player must verify resumed pixels after the state barrier.',
          );
          expect(
            observed.where((event) => event['type'] == 'state.resynced').length,
            1,
          );
          expect(controller.snapshot().reconciliationPending, isFalse);
          await waitFor(
            tester,
            () =>
                find.text('正在核验会话状态').evaluate().isEmpty &&
                find.text('画面已暂停').evaluate().isEmpty,
            reason: 'The full-screen view must leave its verification gate.',
          );
          expectHealthyRemote();
          final current = objects((await request('session.list'))['sessions'])
              .where((session) => session['deviceId'] == deviceId)
              .single;
          expect(current['sessionId'], ownedId);
          expect(current['status'], 'streaming');
          expect(current['capturePaused'], isFalse);
        }
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot('state-recovery-active');
        await request('session.stop', {'sessionId': ownedId, 'keepTask': true});
        await request('state.reconcile');
        await waitFor(
          tester,
          () => find.textContaining('原会话已结束或无法核验').evaluate().isNotEmpty,
          reason: 'An absent session must remain ended after authoritative reconciliation.',
        );
        expect(find.byType(Texture), findsNothing);
        final completedBefore = observed
            .where((event) => event['type'] == 'state.resynced')
            .length;
        await tester.tap(find.text('重新检查'));
        await waitFor(
          tester,
          () =>
              observed
                  .where((event) => event['type'] == 'state.resynced')
                  .length >
              completedBefore,
          reason: 'Retry must use the read-only reconciliation command.',
        );
        expect(
          objects((await request('session.list'))['sessions'])
              .where((session) => session['deviceId'] == deviceId),
          isEmpty,
        );
        expect(find.textContaining('原会话已结束或无法核验'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 750));
        expect(find.text('控制会话已结束'), findsOneWidget);
        expect(find.text('正在核验会话状态'), findsNothing);
        await binding.takeScreenshot('state-recovery-ended');
        await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
        await tester.pump();
        await tester.ensureVisible(find.text('关闭画面'));
        await tester.tap(find.text('关闭画面'));
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isEmpty,
          reason: 'Explicit close removes the ended window without retaining a route to resume.',
        );
        final afterClose = await request('state.reconcile');
        expect(
          objects(afterClose['sessions'])
              .where((session) => session['sessionId'] == ownedId),
          isEmpty,
        );

        expect(pendingAtMarkers, isNotEmpty);
        expect(pendingAtMarkers.every((pending) => pending), isTrue);
        binding.reportData!.addAll({
          'stateRecoveryComplete': true,
          'mediaAcceptanceComplete': true,
          'sessionId': ownedId,
          'watermarks': watermarks,
          'sameSessionResumes': 2,
          'endedSessionNotRecreated': true,
        });
      } catch (failure) {
        debugPrint('[connect.recovery.test] failed=$failure');
        for (final event in observed) {
          final data = jsonObject(event['data']);
          debugPrint(
            '[connect.recovery.test] event=${event['type']} sequence=${event['sequence']} session=${data['sessionId']} status=${data['status']} reason=${data['reason']}',
          );
        }
        rethrow;
      } finally {
        await subscription.cancel();
        if (ownedId != null &&
            objects((await request('session.list'))['sessions'])
                .any((session) => session['sessionId'] == ownedId)) {
          await request('session.stop', {
            'sessionId': ownedId,
            'keepTask': true,
          });
        }
        await controller.focusDevice(originalFocus);
        if (createdDevice && deviceId != null) {
          await request('devices.forget', {'deviceId': deviceId});
        } else if (!initiallyConnected && isolated && deviceId != null) {
          await request('devices.disconnect', {'deviceId': deviceId});
        }
        semantics.dispose();
      }
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
