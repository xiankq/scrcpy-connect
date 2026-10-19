import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:interop_bridge/interop_bridge.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real rotation replaces the decoded texture in the same session',
    (tester) async {
      final root = await getApplicationSupportDirectory();
      final bridge = (await tester.runAsync(
        () => InteropBridge.initialize(
          dataDirectory: '${root.path}/video-reconfigure',
        ),
      ))!;
      final events = <Map<String, dynamic>>[];
      final subscription = bridge.events.listen(events.add);
      String? session;
      var rotated = false;
      try {
        final ready = (await tester.runAsync(() async {
          final added = await bridge.request('devices.add', {
            'address': const String.fromEnvironment(
              'CONNECT_E2E_ADDRESS',
              defaultValue: '10.0.2.2',
            ),
            'port': int.parse(
              const String.fromEnvironment(
                'CONNECT_E2E_PORT',
                defaultValue: '15556',
              ),
            ),
          });
          final device = (added['device'] as Map<String, dynamic>)['id'];
          await bridge.request('devices.connect', {'deviceId': device});
          return bridge.request('session.start', {
            'deviceId': device,
            'maxSize': 640,
          });
        }))!;
        session = ready['sessionId'] as String;
        final firstTexture = ready['textureId'] as int;
        expect(ready['firstFrameDecoded'], true);
        expect(ready['evidence'], 'mdk.snapshot');
        await tester.pumpWidget(
          MaterialApp(home: Texture(textureId: firstTexture)),
        );
        await tester.pump();
        await tester.runAsync(() async {
          await bridge.request('session.rotate', {'sessionId': session});
          rotated = true;
        });
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        Map<String, dynamic>? changed;
        while (changed == null && DateTime.now().isBefore(deadline)) {
          for (final event in events) {
            if (event['type'] == 'session.output.changed') {
              final data = event['data'] as Map<String, dynamic>;
              if (data['sessionId'] == session &&
                  (data['generation'] as int) > (ready['generation'] as int)) {
                changed = data;
              }
            }
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          changed,
          isNotNull,
          reason: 'The existing raw connection must deliver a new real decoded generation.',
        );
        final next = changed!;
        expect(next['firstFrameDecoded'], true);
        expect(next['evidence'], 'mdk.snapshot');
        expect(next['textureId'], isNot(firstTexture));
        expect(next['decodedWidth'], ready['decodedHeight']);
        expect(next['decodedHeight'], ready['decodedWidth']);
        expect(
          events.where((event) => event['type'] == 'session.failed'),
          isEmpty,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: AspectRatio(
                aspectRatio:
                    (next['decodedWidth'] as int) /
                    (next['decodedHeight'] as int),
                child: Texture(textureId: next['textureId'] as int),
              ),
            ),
          ),
        );
        // Android's rotation animation can outlive decoder reconfiguration.
        // First-frame acceptance above stays separate from this visual check.
        await tester.pump(const Duration(milliseconds: 900));
        final sessions = (await tester.runAsync(
          () => bridge.request('session.list'),
        ))!;
        final current = (sessions['sessions'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((s) => s['sessionId'] == session);
        expect(current['width'], next['decodedWidth']);
        expect(current['height'], next['decodedHeight']);
        expect(current['sessionId'], ready['sessionId']);
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('shared-video-rotated');
        binding.reportData = {
          ...?binding.reportData,
          'reconfiguration': {
            'initialGeneration': ready['generation'],
            'generation': next['generation'],
            'sameSession': true,
            'sameRelay': ready['relayId'] == next['relayId'],
            'width': next['decodedWidth'],
            'height': next['decodedHeight'],
            'firstFrameDecoded': next['firstFrameDecoded'],
          },
        };
      } finally {
        await subscription.cancel();
        await tester.runAsync(() async {
          if (session != null) {
            if (rotated) {
              await bridge.request('session.rotate', {'sessionId': session});
              await Future<void>.delayed(const Duration(milliseconds: 300));
            }
            await bridge.request('session.stop', {'sessionId': session});
          }
          await bridge.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(tester.takeException(), isNull);
      binding.reportData!['mediaAcceptanceComplete'] = true;
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
