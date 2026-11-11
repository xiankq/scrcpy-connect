import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/models/connection_validation.dart';

import 'support/production_app.dart'
    show startProductionApp, expectHealthyRemote, tapPageAction, waitFor;

// 配合 test/driver/remote_ime.dart 运行，仅注入 Flutter 输入法编辑值，不声称覆盖 Gboard 中文候选界面。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  Map<String, dynamic>? checkpoint;
  Map<String, dynamic>? hostResult;
  String? acknowledged;
  String? hostError;
  developer.registerExtension('ext.connect.remoteIme', (_, parameters) async {
    if (parameters['ack'] == checkpoint?['name']) {
      acknowledged = parameters['ack'];
      hostError = parameters['error'];
      hostResult = parameters['result'] == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(parameters['result']!) as Map);
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'checkpoint': checkpoint}),
    );
  });
  binding.reportData = {'remoteImeComplete': false};
  testWidgets(
    'committed Chinese and emoji reach the real Android EditText once',
    (tester) async {
      final semantics = tester.ensureSemantics();
      // IntegrationTest 通常保留平台输入法；为此编辑序列明确注册 Flutter 输入协议替身。
      tester.testTextInput.register();
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      final controller = await startProductionApp(tester);
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
      int? captureGeneration;
      var createdDevice = false;
      var initiallyConnected = false;
      var targetFocused = false;
      final initialSessionIds = <String>{};
      String id(Json item) => value(item, 'sessionId', value(item, 'id'));
      Future<List<Json>> sessions() async => objects(
        (await request('session.list', {'deviceId': deviceId}))['sessions'],
      );
      Future<Map<String, dynamic>> host(String name) async {
        hostResult = null;
        hostError = null;
        checkpoint = {'name': name, 'sessionId': sessionId};
        await waitFor(
          tester,
          () => acknowledged == name,
          timeout: const Duration(seconds: 40),
          reason: 'Host must inspect the actual Android EditText at $name.',
        );
        if (hostError != null) throw StateError(hostError!);
        return hostResult ?? {};
      }

      Future<Json> live() async {
        await waitFor(
          tester,
          () =>
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
          reason: 'The production Flutter decoder must render the real target.',
        );
        final current = (await sessions()).singleWhere(
          (item) =>
              item['status'] == 'streaming' &&
              !initialSessionIds.contains(id(item)),
        );
        sessionId = id(current);
        captureGeneration = current['captureGeneration'] as int;
        expect(current['firstFrameDecoded'], isTrue);
        expect(current['evidence'], 'media_codec.snapshot');
        expectHealthyRemote();
        return current;
      }

      try {
        await controller.updateSetting('deviceSettings', <String, dynamic>{});

        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'attemptId': 'remote-ime-${DateTime.now().microsecondsSinceEpoch}',
          }),
        );
        expect(deviceId, isNotEmpty);
        createdDevice = !initialDevices.any((item) => item['id'] == deviceId);
        initiallyConnected = initialDevices.any(
          (item) => item['id'] == deviceId && item['status'] == 'connected',
        );
        await request('devices.connect', {'deviceId': deviceId});
        await controller.updateSetting('deviceSettings', {
          deviceId: {'wakeOnConnect': true},
        });
        initialSessionIds.addAll(
          (await sessions()).where((s) => s['status'] != 'stopped').map(id),
        );
        expect(
          initialSessionIds,
          isEmpty,
          reason:
              'Use a target without another person’s active control session.',
        );
        WorkspaceRoute(deviceId: deviceId!)
            .go(tester.element(find.byType(Scaffold).first));
        await waitFor(
          tester,
          () => find.byType(DeviceWorkspacePage).evaluate().isNotEmpty,
          reason: 'Open the production device workspace.',
        );
        await tapPageAction(
          tester,
          find.byType(DeviceWorkspacePage),
          find.text('打开手机屏幕'),
        );
        await live();
        await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
        await tester.pump();
        await tester.ensureVisible(find.text('键盘'));
        await tester.tap(find.text('键盘'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const ValueKey('remote-tool-panel')),
          findsNothing,
          reason: 'Choosing keyboard closes the tool panel before touching the target.',
        );
        final current = await live();
        final coordinates = await host('prepare-settings');
        final width = (current['width'] as num).toInt();
        final height = (current['height'] as num).toInt();
        final x =
            ((coordinates['x'] as num) * width / (coordinates['width'] as num))
                .round()
                .clamp(0, width - 1);
        final y =
            ((coordinates['y'] as num) *
                    height /
                    (coordinates['height'] as num))
                .round()
                .clamp(0, height - 1);
        final texture = tester.getRect(find.byType(Texture));
        final viewport = tester.getRect(
          find
              .ancestor(
                of: find.byType(Texture),
                matching: find.byType(Listener),
              )
              .first,
        );
        expect(
          viewport.top,
          0,
          reason: 'Video input includes the host top safe area.',
        );
        expect(texture.width / texture.height, closeTo(width / height, .005));
        final touch = Offset(
          texture.left + x * texture.width / width,
          texture.top + y * texture.height / height,
        );
        // 经过生产视频 Listener 和 sourcePoint 转换，独立宿主证明此次点击聚焦真实目标字段。
        await tester.tapAt(touch);
        await host('focused-empty');
        targetFocused = true;
        final fieldFinder = find.descendant(
          of: find.byType(RemotePage),
          matching: find.byType(TextField),
        );
        await waitFor(
          tester,
          () =>
              fieldFinder.evaluate().length == 1 &&
              tester.widget<TextField>(fieldFinder).focusNode!.hasFocus &&
              tester.testTextInput.hasAnyClients,
          reason: 'The public keyboard action must attach the hidden Flutter IME field.',
        );
        final baseline = tester.widget<TextField>(fieldFinder).controller!.text;
        const committed = '你好🙂';
        final composed = '$baseline$committed';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: composed,
            selection: TextSelection.collapsed(offset: composed.length),
            composing: TextRange(start: baseline.length, end: composed.length),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await host('composing-no-leak');
        // 关键回归：仅组合范围改变，文字与选区完全一致，单独使用 TextField.onChanged 会漏掉此次提交。
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: composed,
            selection: TextSelection.collapsed(offset: composed.length),
            composing: TextRange.empty,
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await host('committed-once');
        await tester.pump(const Duration(seconds: 2));
        await host('committed-still-once');
        binding.reportData!.addAll({
          'remoteImeComplete': true,
          'committedText': committed,
          'inputMethod':
              'Flutter TestTextInput editing values; no Gboard candidate UI',
          'targetFocusMethod': 'Flutter video surface pointer through production sourcePoint and scrcpy transport',
          'viewport': {
            'left': viewport.left,
            'top': viewport.top,
            'width': viewport.width,
            'height': viewport.height,
          },
          'texture': {
            'left': texture.left,
            'top': texture.top,
            'width': texture.width,
            'height': texture.height,
          },
          'targetFocusPoint': {
            'x': x,
            'y': y,
            'width': width,
            'height': height,
          },
          'decodedFrameVerified': true,
          'publicKeyboardActionVerified': true,
        });
        expect(tester.takeException(), isNull);
      } finally {
        // 设置初始查询为空；仅经本夹具自己的控制通道恢复输入，再只停止拥有的会话。
        try {
          if (sessionId != null && !initialSessionIds.contains(sessionId)) {
            try {
              if (targetFocused) {
                await request('session.key', {
                  'sessionId': sessionId,
                  'captureGeneration': captureGeneration,
                  'keyCode': 29,
                  'metaState': 4096,
                  'action': 'press',
                });
                await request('session.key', {
                  'sessionId': sessionId,
                  'captureGeneration': captureGeneration,
                  'keyCode': 67,
                  'action': 'press',
                });
                await host('cleanup-empty');
                binding.reportData!['targetQueryRestored'] = true;
              }
            } finally {
              await request('session.stop', {
                'sessionId': sessionId,
                'keepTask': true,
              });
            }
          }
        } finally {
          try {
            await controller.focusDevice(initialFocus);
            await controller.updateSetting(
              'deviceSettings',
              jsonObject(initialSettings['deviceSettings']),
            );
          } finally {
            try {
              if (deviceId != null && createdDevice) {
                await request('devices.forget', {'deviceId': deviceId});
              } else if (deviceId != null &&
                  !initiallyConnected &&
                  initialSessionIds.isEmpty) {
                await request('devices.disconnect', {'deviceId': deviceId});
              }
            } finally {
              tester.testTextInput.unregister();
              semantics.dispose();
            }
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
