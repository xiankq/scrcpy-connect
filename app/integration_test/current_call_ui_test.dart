import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/calls/devices_workspace_calls_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/services/connection/connection_validation.dart';

import 'product_flow_test.dart'
    show expectHealthyRemote, tapPageAction, waitFor;

// 仅配合 test/driver/current_call_ui.dart 的隔离虚拟调制解调器运行；生产 CallsPage 拥有观察和 calls.open，本验收流程必须实际点击产品动作，不能以运行时调用替代。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  final runId = DateTime.now().microsecondsSinceEpoch.toString();
  Map<String, Object?>? checkpoint;
  Map<String, dynamic>? hostResult;
  String? acknowledged;
  String? hostError;
  var sequence = 0;
  developer.registerExtension('ext.connect.currentCallUi', (
    _,
    parameters,
  ) async {
    if (checkpoint != null && parameters['ack'] == checkpoint!['id']) {
      acknowledged = parameters['ack'];
      hostError = parameters['error'];
      hostResult = parameters['result'] == null
          ? null
          : jsonDecode(parameters['result']!) as Map<String, dynamic>;
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'checkpoint': checkpoint}),
    );
  });
  binding.reportData = {'currentCallUiComplete': false};
  testWidgets(
    'CallsPage opens the actual current system call in a decoded control session',
    (tester) async {
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      final report = binding.reportData!;
      await app.main();
      await waitFor(
        tester,
        () => find.byType(ConnectApp).evaluate().isNotEmpty,
        reason: 'The production app must initialize before preserving state.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
        reason: 'Production reconciliation must finish before fixture setup.',
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
      var connectedByTest = false;
      var observationStarted = false;
      Json? observationBefore;
      var hostFixtureRequested = false;
      final baselineSessions = <String>{};
      String id(Json item) => value(item, 'sessionId', value(item, 'id'));
      Future<List<Json>> sessions() async => objects(
        (await request('session.list', {'deviceId': deviceId}))['sessions'],
      );
      Future<Map<String, dynamic>> host(String name) async {
        hostResult = null;
        hostError = null;
        acknowledged = null;
        final checkpointId = '$runId:${++sequence}:$name';
        checkpoint = {
          'id': checkpointId,
          'name': name,
          'runId': runId,
          'sequence': sequence,
          'deviceId': deviceId,
          'sessionId': sessionId,
        };
        await waitFor(
          tester,
          () => acknowledged == checkpointId,
          timeout: const Duration(seconds: 70),
          reason: 'The independent host must complete $name for this run.',
        );
        if (hostError != null) throw StateError(hostError!);
        return hostResult ?? {};
      }

      try {
        await controller.updateSetting('deviceSettings', <String, dynamic>{});

        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'attemptId': 'current-call-ui-$runId',
          }),
        );
        expect(deviceId, isNotEmpty);
        final original = initialDevices
            .where((d) => d['id'] == deviceId)
            .firstOrNull;
        createdDevice = original == null;
        connectedByTest = original?['status'] != 'connected';
        if (connectedByTest) {
          await request('devices.connect', {'deviceId': deviceId});
        }
        baselineSessions.addAll((await sessions()).map(id));
        expect(
          (await sessions()).where(
            (s) => !['stopped', 'failed', 'error'].contains(s['status']),
          ),
          isEmpty,
          reason: 'This isolated target must have no existing control session.',
        );
        observationBefore = await request('observation.status', {
          'deviceId': deviceId,
        });
        observationStarted = observationBefore['wanted'] != true;
        CallsRoute(deviceId: deviceId!)
            .go(tester.element(find.byType(Scaffold).first));
        final page = find.byType(CallsPage);
        await waitFor(
          tester,
          () =>
              page.evaluate().isNotEmpty &&
              (find.text('重新核验通话').evaluate().isNotEmpty ||
                  find.text('启用通知与来电观察').evaluate().isNotEmpty),
          reason: 'Open the formal production CallsPage.',
        );
        await tapPageAction(
          tester,
          page,
          find.text(
            find.text('重新核验通话').evaluate().isNotEmpty ? '重新核验通话' : '启用通知与来电观察',
          ),
        );
        Json calls = {};
        final observationDeadline = DateTime.now().add(
          const Duration(seconds: 30),
        );
        do {
          calls = await request('calls.list', {'deviceId': deviceId});
          if (calls['live'] == true) break;
          await tester.pump(const Duration(milliseconds: 200));
        } while (DateTime.now().isBefore(observationDeadline));
        expect(calls['live'], isTrue);
        expect(
          objects(calls['calls']),
          isEmpty,
          reason: 'Never create a fixture call over an existing real call.',
        );
        hostFixtureRequested = true;
        await host('prepare-ringing-settings');
        // 生产应用会在当前页面上呈现来电面板，沿用其实际动作，不穿透模态遮罩点击。
        await waitFor(
          tester,
          () => find.text('查看来电与声音').hitTestable().evaluate().isNotEmpty,
          reason: 'The actual incoming-call reminder must be handled first.',
        );
        await tester.tap(find.text('查看来电与声音').hitTestable());
        await waitFor(
          tester,
          () =>
              find.byType(BottomSheet).evaluate().isEmpty &&
              page.evaluate().length == 1 &&
              find
                  .descendant(of: page, matching: find.byType(Scrollable))
                  .evaluate()
                  .isNotEmpty,
          reason:
              'The reminder must dismiss and the formal CallsPage must load.',
        );
        report['incomingCallReminderHandled'] = true;
        await waitFor(
          tester,
          () => find.text('打开系统通话界面').evaluate().isNotEmpty,
          timeout: const Duration(seconds: 35),
          reason:
              'Live observation must expose the current system call action.',
        );
        calls = await request('calls.list', {'deviceId': deviceId});
        expect(calls['live'], isTrue);
        expect(objects(calls['calls']).single['state'], 'ringing');
        report['formalCallsPageObservedRinging'] = true;
        final openAction = find.text('打开系统通话界面');
        await tester.scrollUntilVisible(
          openAction,
          -250,
          scrollable: find
              .descendant(of: page, matching: find.byType(Scrollable))
              .first,
          maxScrolls: 12,
        );
        await Scrollable.ensureVisible(
          tester.element(openAction),
          alignment: .5,
        );
        await tester.pump(const Duration(milliseconds: 400));
        await host('before-open');
        expect(find.byType(RemotePage), findsNothing);
        expect((await sessions()).map(id).toSet(), baselineSessions);
        await tapPageAction(tester, page, openAction);
        await waitFor(
          tester,
          () =>
              find.byType(RemotePage).evaluate().isNotEmpty &&
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
          reason: 'The actual full screen control page must decode the target.',
        );
        final current = (await sessions()).singleWhere(
          (s) =>
              s['status'] == 'streaming' && !baselineSessions.contains(id(s)),
        );
        sessionId = id(current);
        expect(current['firstFrameDecoded'], isTrue);
        expect(current['evidence'], 'media_codec.snapshot');
        expect(
          current['packageName'],
          isNull,
          reason: 'The CallsPage action must enter full screen remote control.',
        );
        expectHealthyRemote();
        // 宿主截取主控及视频纹理前，先等待真实 InCallActivity 首帧到达物理显示器。
        await tester.pump(const Duration(seconds: 1));
        await host('decoded-incall');
        calls = await request('calls.list', {'deviceId': deviceId});
        expect(objects(calls['calls']).single['state'], 'ringing');
        report.addAll({
          'sessionId': sessionId,
          'decodedFrameVerified': true,
          'frameEvidence': current['evidence'],
          'fullRemotePageVerified': true,
          'callRemainsRinging': true,
          'formalOpenSystemCallActionVerified': true,
        });
        expect(tester.takeException(), isNull);
      } finally {
        final cleanupErrors = <String>[];
        Future<void> clean(String name, Future<void> Function() action) async {
          try {
            await action();
          } catch (error) {
            cleanupErrors.add('$name: $error');
          }
        }

        await clean('leave remote page', () async {
          const DevicesRoute().go(tester.element(find.byType(Scaffold).first));
          await tester.pump(const Duration(milliseconds: 400));
        });
        if (deviceId != null) {
          await clean('owned sessions', () async {
            for (final current in await sessions()) {
              if (!baselineSessions.contains(id(current))) {
                await request('session.stop', {
                  'sessionId': id(current),
                  'keepTask': true,
                });
              }
            }
            expect(
              (await sessions()).where(
                (s) =>
                    !baselineSessions.contains(id(s)) &&
                    s['status'] != 'stopped',
              ),
              isEmpty,
            );
            report['ownedSessionsStopped'] = true;
          });
        }
        if (hostFixtureRequested) {
          await clean('target fixture', () async {
            await host('cleanup-target');
            report['targetFixtureRestored'] = true;
          });
        }
        final expectedObservation = observationBefore;
        if (deviceId != null && expectedObservation != null) {
          await clean('observation', () async {
            if (observationStarted) {
              await request('observation.stop', {'deviceId': deviceId});
            }
            final after = await request('observation.status', {
              'deviceId': deviceId,
            });
            expect(after['wanted'], expectedObservation['wanted']);
            report['observationRestored'] = true;
          });
        }
        await clean('settings', () async {
          for (final key in ['deviceSettings']) {
            await controller.updateSetting(key, initialSettings[key]);
            expect(controller.snapshot().settings[key], initialSettings[key]);
          }
          report['settingsRestored'] = true;
        });
        if (deviceId != null) {
          await clean('connection', () async {
            if (createdDevice) {
              await request('devices.forget', {'deviceId': deviceId});
            } else if (connectedByTest) {
              await request('devices.disconnect', {'deviceId': deviceId});
            }
            final after = objects((await request('devices.list'))['devices']);
            expect(
              after.map((d) => d['id']).toSet(),
              initialDevices.map((d) => d['id']).toSet(),
            );
            for (final before in initialDevices) {
              expect(
                after.singleWhere((d) => d['id'] == before['id'])['status'],
                before['status'],
              );
            }
            report['connectionsRestored'] = true;
          });
        }
        await clean('focus', () async {
          await controller.focusDevice(initialFocus);
          expect(controller.snapshot().focusedDeviceId, initialFocus);
          report['focusRestored'] = true;
        });
        report['cleanupErrors'] = cleanupErrors;
        report['ownedCleanupComplete'] = cleanupErrors.isEmpty;
        expect(cleanupErrors, isEmpty);
      }
      report['currentCallUiComplete'] = true;
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
