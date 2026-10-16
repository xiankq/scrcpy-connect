import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'dart:convert';
import 'dart:developer' as developer;

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
  var stage = 'starting';
  var hostReturned = false;
  developer.registerExtension('ext.connect.background', (_, parameters) async {
    if (parameters['action'] == 'returned') hostReturned = true;
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'stage': stage}),
    );
  });
  testWidgets(
    'actual HOME pauses video and foreground waits for a verified decoded frame',
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
              .timeout(const Duration(seconds: 35));
      final observed = <Json>[];
      final subscription = controller
          .eventStream()
          .where((e) => value(e, 'type').startsWith('session.'))
          .listen(observed.add);
      String? deviceId;
      try {
        final added = await request('devices.add', {
          'address': address,
          'port': int.parse(port),
          'attemptId': 'background-${DateTime.now().microsecondsSinceEpoch}',
        });
        deviceId = responseDeviceId(added);
        expect(deviceId, isNotEmpty);
        final connected = await request('devices.connect', {
          'deviceId': deviceId,
        });
        final device = connected['device'] is Map<Object?, Object?>
            ? jsonObject(connected['device'])
            : {'id': deviceId, 'name': 'Android', 'status': 'connected'};
        openRemoteRoute(
          tester.element(find.byType(Scaffold).first),
          deviceId: value(device, 'id'),
        );
        await waitFor(
          tester,
          () => find.byType(Texture).evaluate().isNotEmpty,
          reason: 'The real stream must render before backgrounding.',
        );
        expectHealthyRemote();
        observed.clear();
        stage = 'ready';
        await waitFor(
          tester,
          () => hostReturned,
          timeout: const Duration(seconds: 45),
          reason: 'Host driver must complete actual HOME and Activity foreground return.',
        );
        await waitFor(
          tester,
          () {
            final pause = observed.indexWhere(
              (e) =>
                  e['type'] == 'session.updated' &&
                  (e['data'] as Map<Object?, Object?>?)?['status'] == 'paused',
            );
            if (pause < 0) return false;
            final resume = observed.indexWhere(
              (e) =>
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
                          e['type'] == 'session.output.resumed' &&
                          (e['data']
                                  as Map<
                                    Object?,
                                    Object?
                                  >?)?['firstFrameDecoded'] ==
                              true &&
                          (e['data'] as Map<Object?, Object?>?)?['evidence'] ==
                              'mdk.snapshot',
                    );
          },
          reason: 'A real paused update, resumed stream and later verified shared-player snapshot are required.',
        );
        await tester.pump(const Duration(milliseconds: 300));
        expectHealthyRemote();
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot('remote-after-actual-background');
        final exit = find.bySemanticsLabel(RegExp('退出控制，返回'));
        expect(exit, findsOneWidget);
        await tester.tap(exit);
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isEmpty,
          reason: 'The recovered session must exit normally.',
        );
        stage = 'complete';
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await subscription.cancel();
        if (deviceId != null) {
          for (final session
              in objects((await request('session.list'))['sessions']).where(
                (s) => s['deviceId'] == deviceId && s['status'] != 'stopped',
              )) {
            await request('session.stop', {
              'deviceId': deviceId,
              'sessionId': session['sessionId'] ?? session['id'],
            });
          }
        }
      }
    },
    skip: address.isEmpty || port.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
