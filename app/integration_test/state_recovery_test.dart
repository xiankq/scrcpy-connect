import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

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
      await tester.pump(const Duration(milliseconds: 400));
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 40));
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
        final deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'attemptId': 'recovery-${DateTime.now().microsecondsSinceEpoch}',
          }),
        )!;
        expect(deviceId, isNotEmpty);
        await request('devices.connect', {'deviceId': deviceId});
        final existing = objects((await request('session.list'))['sessions'])
            .where((session) => session['deviceId'] == deviceId);
        expect(
          existing,
          isEmpty,
          reason: 'Use an isolated target with no preexisting sessions.',
        );
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
        expect(initial['evidence'], 'mdk.snapshot');
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
                  jsonObject(event['data'])['evidence'] == 'mdk.snapshot',
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
        await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isEmpty,
          reason: 'Leaving retains the exact session.',
        );
        final paused = await request('state.reconcile');
        final retained = objects(paused['sessions'])
            .singleWhere((session) => session['sessionId'] == ownedId);
        expect(retained['status'], 'paused');
        expect(retained['capturePaused'], isTrue);
        openRemoteRoute(
          tester.element(find.byType(Scaffold).first),
          deviceId: deviceId,
          sessionId: ownedId,
        );
        await waitFor(
          tester,
          () =>
              find.byType(Texture).evaluate().isNotEmpty &&
              find.text('画面已暂停').evaluate().isEmpty,
          reason: 'Reopen the retained session without creating a replacement.',
        );
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
        semantics.dispose();
      }
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
