import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/stores/application_session.dart';

// 在隔离私有目录中运行生产桥接和真实 Android 服务；不打开设备、远控页面、捕获或音频输出。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannel('dev.scrcpyconnect/platform');

  testWidgets(
    'application entry, explicit preference and engine reattachment keep background independent of media',
    (tester) async {
      expect(
        Platform.isAndroid,
        true,
        reason: 'This acceptance requires an actual Android host.',
      );
      final directory = await Directory.systemTemp.createTemp(
        'background-acceptance-',
      );
      ApplicationSession? bridge;
      Future<Map<String, dynamic>> nativeStatus() async =>
          Map<String, dynamic>.from(
            await platform.invokeMethod<Map<Object?, Object?>>(
                  'background.status',
                ) ??
                {},
          );
      Future<Map<String, dynamic>> waitRunning(bool running) async {
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        var status = await nativeStatus();
        while (status['running'] != running &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          status = await nativeStatus();
        }
        expect(status['running'], running, reason: '$status');
        return status;
      }

      try {
        bridge = await ApplicationSession.initialize(
          dataDirectory: directory.path,
        );
        expect(
          (await bridge.request('settings.get'))['backgroundKeepAlive'],
          true,
        );
        var status = await waitRunning(true);
        expect(status['connectionRequested'], true);
        expect(status['audioRequested'], false);
        expect(status['mediaPlaybackReady'], false);
        expect((await bridge.request('session.list'))['sessions'], isEmpty);
        expect((await bridge.request('audio.sources'))['sources'], isEmpty);

        await bridge.request('settings.update', {'backgroundKeepAlive': false});
        await waitRunning(false);
        await bridge.request('settings.get');
        await tester.pump(const Duration(milliseconds: 300));
        expect((await nativeStatus())['running'], false);

        await bridge.request('settings.update', {'backgroundKeepAlive': true});
        await waitRunning(true);
        await bridge.dispose();
        bridge = null;
        // 释放输出和观察者不能终止应用后台连接。
        await waitRunning(true);
        bridge = await ApplicationSession.initialize(
          dataDirectory: directory.path,
        );
        status = await waitRunning(true);
        expect(status['audioRequested'], false);
        expect(status['mediaPlaybackReady'], false);
        expect((await bridge.request('session.list'))['sessions'], isEmpty);
        expect((await bridge.request('audio.sources'))['sources'], isEmpty);
        binding.reportData = {
          'backgroundApplicationEntry': true,
          'backgroundExplicitPreference': true,
          'backgroundEngineReattachment': true,
          'noMediaStarted': true,
        };
      } finally {
        if (bridge != null) {
          await bridge.request('settings.update', {
            'backgroundKeepAlive': false,
          });
          await waitRunning(false);
          await bridge.dispose();
        }
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
