import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/app.dart';
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

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = String.fromEnvironment('CONNECT_E2E_PORT');
  const secondPort = String.fromEnvironment('CONNECT_E2E_SECOND_PORT');
  final runId = 'clipboard-${DateTime.now().millisecondsSinceEpoch}';
  var stage = 'starting';
  final acknowledgements = <String>{};
  AppController? activeController;
  developer.registerExtension('ext.connect.clipboard', (_, parameters) async {
    final action = parameters['action'];
    if (action != null) acknowledgements.add(action);
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'stage': stage,
        'runId': runId,
        'state': activeController?.snapshot().clipboardState,
        'reads': activeController?.snapshot().clipboardReadCount,
        'writes': activeController?.snapshot().clipboardWriteCount,
        'sends': activeController?.snapshot().clipboardSendCount,
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      }),
    );
  });
  testWidgets(
    'actual foreground clipboard, independent remote client, device isolation and background suspension',
    (tester) async {
      await app.main();
      await tester.pump(const Duration(milliseconds: 300));
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      activeController = controller;
      final originalSettings = {...controller.snapshot().settings};
      final originalFocused = controller.snapshot().focusedDeviceId;
      final originalLocal = await Clipboard.getData(Clipboard.kTextPlain);
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 35));
      Future<void> host(String next, String acknowledgement) async {
        stage = next;
        await waitFor(
          tester,
          () => acknowledgements.contains(acknowledgement),
          timeout: const Duration(seconds: 60),
          reason:
              'Host must perform actual independent clipboard action $next.',
        );
      }

      Future<String> remote(String id) async =>
          value(await request('clipboard.get', {'deviceId': id}), 'text');
      Future<void> expectRemote(String id, String expected) async {
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        var text = await remote(id);
        while (text != expected && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 300));
          text = await remote(id);
        }
        expect(
          text,
          expected,
          reason: 'Actual target clipboard must contain the new local copy.',
        );
      }

      Future<void> expectLocal(String expected) async {
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        var text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        while (text != expected && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 200));
          text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        }
        expect(
          text,
          expected,
          reason: 'Actual Android local clipboard must receive the independently changed target value.',
        );
      }

      try {
        await controller.updateSetting('clipboardSync', false);
        await controller.updateSetting('audioDevices', []);
        final a = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': int.parse(port),
          }),
        )!;
        final b = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': int.parse(secondPort),
          }),
        )!;
        expect(
          a,
          isNot(b),
          reason: 'Two independently booted Android targets must have distinct persistent identities.',
        );
        await request('devices.connect', {'deviceId': a});
        await request('devices.connect', {'deviceId': b});
        await controller.refreshDevices();
        await host('prepare', 'prepared');
        await Clipboard.setData(ClipboardData(text: '$runId-local-baseline'));
        await controller.updateSetting('clipboardMode', 'follow');
        await controller.focusDevice(a);
        await controller.updateSetting('clipboardSync', true);
        await waitFor(
          tester,
          () => controller.snapshot().clipboardState == 'watching',
          reason: 'The actual selected target and local clipboard must establish a live baseline.',
        );
        ClipboardRoute().push<void>(
          tester.element(find.byType(Scaffold).first),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await Clipboard.setData(ClipboardData(text: '$runId-local-a'));
        await expectRemote(a, '$runId-local-a');
        expect(await remote(b), '$runId-baseline-b');
        final beforeRemoteSends = controller.snapshot().clipboardSendCount;
        await host('external-a', 'externalA');
        await expectLocal('$runId-external-a');
        await tester.pump(const Duration(seconds: 2));
        expect(
          controller.snapshot().clipboardSendCount,
          beforeRemoteSends,
          reason: 'The external Binder event must not echo back as a new device write.',
        );
        await controller.focusDevice(b);
        await waitFor(
          tester,
          () => controller.snapshot().clipboardState == 'watching',
          reason: 'Follow mode must rebase on the independently connected second target.',
        );
        await Clipboard.setData(ClipboardData(text: '$runId-local-b'));
        await expectRemote(b, '$runId-local-b');
        expect(await remote(a), '$runId-external-a');
        await host('unselected-a', 'unselectedA');
        await tester.pump(const Duration(milliseconds: 1200));
        await expectLocal('$runId-local-b');
        expect(await remote(b), '$runId-local-b');
        await controller.updateSetting('clipboardDevice', a);
        await controller.updateSetting('clipboardMode', 'fixed');
        await waitFor(
          tester,
          () => controller.snapshot().clipboardState == 'watching',
          reason: 'Fixed mode must select the first real target.',
        );
        await controller.focusDevice(b);
        await Clipboard.setData(ClipboardData(text: '$runId-fixed-a'));
        await expectRemote(a, '$runId-fixed-a');
        expect(await remote(b), '$runId-local-b');
        await host('background', 'backgroundReturned');
        await expectLocal('$runId-background-a');
        await waitFor(
          tester,
          () => controller.snapshot().clipboardState == 'watching',
          reason: 'Foreground return must recheck the actual selected target.',
        );
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot('clipboard-after-real-background');
        await controller.updateSetting('clipboardSync', false);
        final disabledReads = controller.snapshot().clipboardReadCount;
        final disabledWrites = controller.snapshot().clipboardWriteCount;
        await Clipboard.setData(ClipboardData(text: '$runId-disabled-local'));
        await host('disabled-a', 'disabledA');
        await tester.pump(const Duration(seconds: 2));
        await expectLocal('$runId-disabled-local');
        expect(controller.snapshot().clipboardReadCount, disabledReads);
        expect(controller.snapshot().clipboardWriteCount, disabledWrites);
        stage = 'complete';
        expect(tester.takeException(), isNull);
      } finally {
        await controller.updateSetting('clipboardSync', false);
        await Clipboard.setData(ClipboardData(text: originalLocal?.text ?? ''));
        await controller.updateSetting(
          'clipboardMode',
          originalSettings['clipboardMode'] ?? 'follow',
        );
        await controller.updateSetting(
          'clipboardDevice',
          originalSettings['clipboardDevice'],
        );
        await controller.focusDevice(originalFocused);
        await controller.updateSetting(
          'audioDevices',
          originalSettings['audioDevices'] ?? [],
        );
        await controller.updateSetting(
          'clipboardSync',
          originalSettings['clipboardSync'] == true,
        );
      }
    },
    skip: address.isEmpty || port.isEmpty || secondPort.isEmpty,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
