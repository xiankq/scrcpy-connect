import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/incoming_share/incoming_share_page.dart';
import 'package:scrcpy_connect/application/app_controller.dart';

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var mode = '', stage = 'starting';
  var launcherReturned = false;
  final results = <Map<String, Object?>>[];
  developer.registerExtension('ext.connect.incomingShare', (
    _,
    parameters,
  ) async {
    if (parameters['action'] == 'launcherReturned') launcherReturned = true;
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'mode': mode, 'stage': stage}),
    );
  });
  testWidgets(
    'external grants import through Rust and the live Flutter share page',
    (tester) async {
      binding.reportData = {'incomingShares': results};
      await app.main();
      await waitFor(
        tester,
        () => find.byType(ConnectApp).evaluate().isNotEmpty,
        reason: 'The real Flutter application must initialize.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      Future<Json> request(String command, [Json params = const {}]) async =>
          (await tester.runAsync(() => controller.request(command, params)))!;
      var surfaceConverted = false;
      Future<void> capture(String name) async {
        if (!surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
        }
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot(name);
      }

      for (final share in objects(
        (await request('sharing.pending'))['shares'],
      )) {
        await request('sharing.consume', {'shareId': share['shareId']});
      }
      for (final fixtureMode in const String.fromEnvironment(
        'CONNECT_SHARE_MODES',
        defaultValue: 'text,image,multi,alias,no-grant,self-sentinel,too-many,oversize,slow',
      ).split(',')) {
        mode = fixtureMode;
        stage = 'send';
        Json? share;
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (DateTime.now().isBefore(deadline)) {
          final shares = objects((await request('sharing.pending'))['shares']);
          if (shares.isNotEmpty) {
            share = shares.single;
            if (mode == 'slow' ||
                ['ready', 'error'].contains(share['status'])) {
              break;
            }
          }
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(
          share,
          isNotNull,
          reason: 'Real OS share $mode must reach the shared importer.',
        );
        final received = share!;
        final expectedError = [
          'no-grant',
          'self-sentinel',
          'too-many',
          'oversize',
        ].contains(mode);
        expect(
          received['status'],
          mode == 'slow'
              ? 'importing'
              : expectedError
              ? 'error'
              : 'ready',
          reason: 'Fixture $mode: ${received['errors']}',
        );
        final files = objects(received['files']);
        if (mode == 'text') {
          expect(received['text'], 'Connect external text fixture 中文');
        }
        if (expectedError) {
          expect(files, isEmpty);
          final errors = strings(received['errors']).join('；');
          expect(
            errors,
            contains(switch (mode) {
              'no-grant' => '读取授权',
              'self-sentinel' => '本应用的私有内容',
              'too-many' => '最多分享 32',
              'oversize' => '容量上限',
              _ => throw StateError('Unknown negative fixture mode'),
            }),
          );
        }
        if (['image', 'multi', 'alias'].contains(mode)) {
          expect(files, hasLength(mode == 'multi' ? 2 : 1));
          for (final file in files) {
            final actual = await File(value(file, 'localPath')).readAsBytes();
            final expected = value(file, 'name').endsWith('.png')
                ? base64Decode(
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSb8AAAAASUVORK5CYII=',
                  )
                : utf8.encode('Connect incoming share fixture\n中文与空格\n');
            expect(
              actual,
              expected,
              reason: 'Rust must preserve real provider pipe bytes.',
            );
            expect(file['size'], expected.length);
          }
        }
        await tester.runAsync(controller.loadPendingShares);
        await waitFor(
          tester,
          () => find.byType(IncomingSharePage).evaluate().isNotEmpty,
          reason: 'System sharing must open the typed Flutter share route.',
        );
        if (mode == 'slow') {
          expect(find.text('正在读取分享内容，完成后即可发送。你也可以取消本次分享。'), findsOneWidget);
        }
        if (mode == 'image') {
          await capture('incoming-image-share');
        }
        results.add({
          'mode': mode,
          'status': received['status'],
          'files': files.length,
        });
        stage = 'received';
        await tester.tap(find.text('取消'));
        await waitFor(
          tester,
          () => find.byType(IncomingSharePage).evaluate().isEmpty,
          reason: 'Cancel must consume the exact share and return to the app.',
        );
        expect(objects((await request('sharing.pending'))['shares']), isEmpty);
        for (final file in files) {
          expect(
            await File(value(file, 'localPath')).exists(),
            isFalse,
            reason: 'An unsubmitted consumed share must release its source.',
          );
        }
      }
      stage = 'launcher-return';
      await waitFor(
        tester,
        () => launcherReturned,
        timeout: const Duration(seconds: 45),
        reason: 'The host must actually reopen the app from its launcher task.',
      );
      // am start -W 仅确认 Activity 启动和显示，不能证明后续 Flutter 窗口焦点消息；同时等待该真实消息。
      final resumeWait = Stopwatch()..start();
      await waitFor(
        tester,
        () =>
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        timeout: const Duration(seconds: 5),
        reason:
            'The reused Android UI host must actually regain Flutter focus.',
      );
      binding.reportData!['launcherResumeWaitMs'] =
          resumeWait.elapsedMilliseconds;
      expect(find.byTooltip('添加设备'), findsOneWidget);
      await capture('devices-after-share-launcher-return');
      stage = 'complete';
      expect(tester.takeException(), isNull);
      binding.reportData!['shareAcceptanceComplete'] = true;
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
