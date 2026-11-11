import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/models/connection_validation.dart';

import 'support/production_app.dart' show startProductionApp;

// 真实 AppStore/MDK 验收；配套宿主驱动独立观察目标进程、任务 ID、电源状态与 userActivity 时间戳。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  final run = DateTime.now().microsecondsSinceEpoch.toString();
  Json? checkpoint;
  String? acknowledged, hostError;
  var sequence = 0;
  developer.registerExtension('ext.connect.keepActive', (_, parameters) async {
    if (checkpoint != null && parameters['ack'] == checkpoint!['id']) {
      acknowledged = parameters['ack'];
      hostError = parameters['error'];
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'checkpoint': checkpoint}),
    );
  });
  binding.reportData = {'keepActiveComplete': false};
  testWidgets('saved keep-active follows all open real windows dynamically', (
    tester,
  ) async {
    expect(address, isNotEmpty);
    expect(port, inInclusiveRange(1, 65535));
    final controller = await startProductionApp(tester);
    Future<Json> request(String command, [Json params = const {}]) => controller
        .request(command, params)
        .timeout(const Duration(seconds: 60));
    final originalSettings = await request('settings.get');
    final initialDevices = objects((await request('devices.list'))['devices']);
    final originalFocus = controller.snapshot().focusedDeviceId;
    final owned = <String>{};
    final events = <Json>[];
    final subscription = controller.eventStream().listen(events.add);
    final display = ValueNotifier<List<Json>>([]);
    final receipts = <Json>[];
    final applicationTasks = <int>{};
    binding.reportData!['checkpoints'] = receipts;
    OverlayEntry? overlay;
    String? deviceId;
    var created = false, initiallyConnected = false, changedSettings = false;
    String idOf(Json item) => value(item, 'sessionId', value(item, 'id'));
    Future<List<Json>> sessions() async => objects(
      (await request('session.list', {'deviceId': deviceId}))['sessions'],
    );
    Json receipt(Json item) => {
      for (final key in const [
        'sessionId',
        'deviceId',
        'packageName',
        'taskId',
        'displayId',
        'status',
        'captureGeneration',
        'rendererGeneration',
        'textureId',
        'backend',
        'firstFrameDecoded',
        'evidence',
        'decodedWidth',
        'decodedHeight',
        'outputCaptureGeneration',
        'outputGeneration',
        'keepActive',
        'keepActiveApplied',
        'keepActiveLeaseActive',
        'keepActiveLeaseId',
        'keepActivePid',
        'keepActiveConnectionId',
        'keepActiveError',
      ])
        key: item[key],
    };
    Future<void> host(String name, {int? leases, bool advance = false}) async {
      final records = await sessions();
      display.value = records
          .where((item) => owned.contains(idOf(item)))
          .toList();
      await tester.pump(const Duration(milliseconds: 200));
      final id = '$run:${++sequence}:$name';
      acknowledged = null;
      hostError = null;
      checkpoint = {
        'id': id,
        'name': name,
        'deviceId': deviceId,
        'expectedLeases': ?leases,
        'advance': advance,
        'sessions': records.map(receipt).toList(),
        'ownedApplicationTasks': applicationTasks.toList(),
      };
      receipts.add(checkpoint!);
      debugPrint('keep-active-checkpoint: $name');
      final deadline = DateTime.now().add(const Duration(seconds: 50));
      while (acknowledged != id && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(acknowledged, id, reason: 'Independent host must verify $name.');
      if (hostError != null) throw StateError(hostError!);
    }

    Future<Json> ready(String id) async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      do {
        final found = (await sessions()).where((item) => idOf(item) == id);
        if (found.length == 1) {
          final item = found.single;
          if (item['backend'] == 'media_codec' &&
              item['status'] == 'streaming' &&
              item['firstFrameDecoded'] == true &&
              item['evidence'] == 'media_codec.snapshot' &&
              item['textureId'] is int &&
              (item['textureId'] as int) >= 0 &&
              (item['decodedWidth'] as num? ?? 0) > 0 &&
              (item['decodedHeight'] as num? ?? 0) > 0 &&
              item['outputCaptureGeneration'] == item['captureGeneration'] &&
              item['outputGeneration'] == item['rendererGeneration'] &&
              events.any((event) {
                final data = jsonObject(event['data']);
                return [
                      'session.output.ready',
                      'session.output.changed',
                    ].contains(event['type']) &&
                    event['deviceId'] == deviceId &&
                    data['sessionId'] == id &&
                    data['captureGeneration'] == item['captureGeneration'] &&
                    data['generation'] == item['rendererGeneration'] &&
                    data['textureId'] == item['textureId'] &&
                    data['firstFrameDecoded'] == true &&
                    data['evidence'] == 'media_codec.snapshot';
              })) {
            return item;
          }
        }
        await tester.pump(const Duration(milliseconds: 200));
      } while (DateTime.now().isBefore(deadline));
      fail('Actual local MDK output failed to verify: ${await sessions()}');
    }

    Future<Json> open([String? package]) async {
      try {
        final result = await request('session.start', {
          'deviceId': deviceId, 'packageName': ?package,
          // 有意不直接覆盖 keepActive，由保存的产品设置决定。
        });
        final id = idOf(result);
        expect(id, isNotEmpty);
        owned.add(id);
        if (package != null && result['taskId'] is int) {
          applicationTasks.add(result['taskId'] as int);
        }
        return await ready(id);
      } on RequestFailure catch (error) {
        final detail = jsonObject(error.details);
        if (detail['deviceId'] == deviceId && idOf(detail).isNotEmpty) {
          owned.add(idOf(detail));
          if (package != null && detail['taskId'] is int) {
            applicationTasks.add(detail['taskId'] as int);
          }
        }
        rethrow;
      }
    }

    Future<void> setting(bool enabled) =>
        controller.updateDeviceSettings(deviceId!, {'stayAwake': enabled});
    Future<void> unchanged(Json before, {required bool keepActive}) async {
      final now = (await sessions()).singleWhere(
        (item) => idOf(item) == idOf(before),
      );
      for (final field in [
        'sessionId',
        'taskId',
        'displayId',
        'captureGeneration',
        'rendererGeneration',
        'textureId',
        'outputCaptureGeneration',
        'outputGeneration',
      ]) {
        expect(
          now[field],
          before[field],
          reason: 'Changing keep-active must preserve $field.',
        );
      }
      expect(now['status'], 'paused');
      expect(now['keepActive'], keepActive);
      expect(now['keepActiveApplied'], true);
      expect(now['keepActiveLeaseActive'], keepActive);
      expect(now['firstFrameDecoded'], true);
    }

    try {
      await host('baseline', leases: 0);
      deviceId = responseDeviceId(
        await request('devices.add', {
          'address': address,
          'port': port,
          'attemptId': 'keep-active-$run',
        }),
      );
      created = !initialDevices.any((item) => item['id'] == deviceId);
      initiallyConnected = initialDevices.any(
        (item) => item['id'] == deviceId && item['status'] == 'connected',
      );
      await request('devices.connect', {'deviceId': deviceId});
      expect(
        await sessions(),
        isEmpty,
        reason: 'Never change another owner’s windows.',
      );
      await controller.focusDevice(deviceId);
      changedSettings = true;
      await controller.updateDeviceSettings(deviceId!, {
        'stayAwake': false,
        'wakeOnConnect': false,
        'lockOnClose': false,
      });
      final phone = await open();
      await request('session.pause', {'sessionId': idOf(phone)});
      overlay = OverlayEntry(
        builder: (_) => Positioned.fill(
          child: Material(
            color: Colors.black,
            child: SafeArea(
              child: ValueListenableBuilder<List<Json>>(
                valueListenable: display,
                builder: (_, records, _) => Row(
                  children: [
                    for (final item in records)
                      if (item['textureId'] is int)
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio:
                                  (item['decodedWidth'] as num) /
                                  (item['decodedHeight'] as num),
                              child: Texture(
                                textureId: item['textureId'] as int,
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Overlay.of(tester.element(find.byType(Scaffold).first)).insert(overlay);
      await host('paused-off', leases: 0);
      await setting(true);
      await unchanged(phone, keepActive: true);
      await host('enabled-existing-paused', leases: 1);
      final application = await open('com.android.settings');
      expect(application['taskId'], isA<int>());
      await unchanged(phone, keepActive: true);
      await host('two-windows-one-lease', leases: 1);
      await request('session.stop', {
        'sessionId': idOf(application),
        'keepTask': true,
      });
      owned.remove(idOf(application));
      await unchanged(phone, keepActive: true);
      await host('application-closed-phone-paused', leases: 1, advance: true);
      await setting(false);
      await unchanged(phone, keepActive: false);
      await host('disabled-existing-paused', leases: 0);
      await host('sleep-target', leases: 0);
      await setting(true);
      await unchanged(phone, keepActive: true);
      await host('enabled-asleep-no-wake', leases: 1);
      await setting(false);
      await host('disabled-asleep', leases: 0);
      await host('wake-target', leases: 0);
      await setting(true);
      await unchanged(phone, keepActive: true);
      await host('reenabled-existing-paused', leases: 1, advance: true);
      await request('session.stop', {
        'sessionId': idOf(phone),
        'keepTask': true,
      });
      owned.remove(idOf(phone));
      expect(await sessions(), isEmpty);
      await host('last-window-closed', leases: 0);
      binding.reportData!['keepActiveComplete'] = true;
    } finally {
      final cleanupErrors = <String>[];
      Future<void> clean(String name, Future<void> Function() action) async {
        try {
          await action();
        } catch (error) {
          cleanupErrors.add('$name: $error');
        }
      }

      overlay?.remove();
      overlay?.dispose();
      await tester.pump();
      for (final id in owned.toList()) {
        await clean('session:$id', () async {
          await request('session.stop', {'sessionId': id, 'keepTask': true});
        });
      }
      if (deviceId != null) {
        if (changedSettings) {
          await clean('settings', () async {
            final latest = jsonObject(
              (await request('settings.get'))['deviceSettings'],
            );
            final previous = jsonObject(originalSettings['deviceSettings']);
            if (previous.containsKey(deviceId)) {
              latest[deviceId!] = previous[deviceId];
            } else {
              latest.remove(deviceId);
            }
            await controller.updateSetting('deviceSettings', latest);
          });
        }
        if (created || !initiallyConnected) {
          await clean('connection', () async {
            expect(await sessions(), isEmpty);
            await request(created ? 'devices.forget' : 'devices.disconnect', {
              'deviceId': deviceId,
            });
          });
        }
      }
      await clean('focus', () => controller.focusDevice(originalFocus));
      await clean('subscription', subscription.cancel);
      await clean('host', () => host('cleanup', leases: 0));
      display.dispose();
      binding.reportData!['cleanupErrors'] = cleanupErrors;
      expect(cleanupErrors, isEmpty);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
