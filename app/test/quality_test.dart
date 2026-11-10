import 'package:scrcpy_connect/models/application_request.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';

import 'support/router_test_app.dart';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/stores/app_store.dart';

Future<void> reveal(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label).hitTestable(),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Json codec(
  String id,
  String name, {
  bool available = true,
  String status = 'available',
  String decoder = 'available',
  bool? canAttempt,
  String? reason,
  String? encoder,
}) => {
  'id': id,
  'name': name,
  'available': available,
  'status': status,
  'decoderStatus': decoder,
  'canAttempt': ?canAttempt,
  'reason': ?reason,
  if (encoder != null)
    'encoders': [
      {'name': encoder, 'available': true, 'status': 'available'},
    ],
};

Future<void> mount(WidgetTester tester, AppStore controller) async {
  await tester.pumpWidget(
    RouterTestApp(
      controller: controller,
      theme: ConnectTokens.theme(Brightness.light),
      home: QualityPage(controller: controller, device: const {'id': 'phone'}),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'codec changes reset the encoder and expose only its matching encoders for all device sessions',
    (tester) async {
      final requests = <(String, Json)>[];
      final current = <String, dynamic>{
        'preset': 'balanced',
        'videoCodec': 'h264',
        'videoEncoder': 'c2.avc.encoder',
      };
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        requests.add((command, params));
        if (command == 'session.quality') {
          current.addAll({...params}..remove('deviceId'));
          return {
            'appliedSessions': ['live-session'],
            'failures': <Json>[],
          };
        }
        return {
          'current': {...current},
          'codecs': [
            codec('h264', 'H.264', encoder: 'c2.avc.encoder'),
            codec('h265', 'H.265', encoder: 'c2.hevc.encoder'),
          ],
        };
      });
      await mount(tester, controller);
      expect(find.text('画面与控制'), findsOneWidget);
      expect(find.text('屏幕比例'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      await reveal(tester, '编码格式');
      await tester.tap(find.text('编码格式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('H.265'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.$1 == 'session.quality').single.$2, {
        'deviceId': 'phone',
        'videoCodec': 'h265',
        'videoEncoder': null,
      });
      await reveal(tester, '视频编码器');
      await tester.tap(find.text('视频编码器'));
      await tester.pumpAndSettle();
      expect(find.text('c2.avc.encoder'), findsNothing);
      await tester.tap(find.text('c2.hevc.encoder'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(requests.lastWhere((r) => r.$1 == 'session.quality').$2, {
        'deviceId': 'phone',
        'videoEncoder': 'c2.hevc.encoder',
      });
      await tester.tap(find.text('视频编码器'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自动选择'));
      await tester.pumpAndSettle();
      expect(requests.lastWhere((r) => r.$1 == 'session.quality').$2, {
        'deviceId': 'phone',
        'videoEncoder': null,
      });
      expect(
        requests.where(
          (r) => [
            'session.stop',
            'session.start',
            'session.resume',
          ].contains(r.$1),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'unconfirmed decoder choices show their actual reasons and a rejected change preserves the current quality',
    (tester) async {
      final requests = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        requests.add((command, params));
        if (command == 'session.quality') {
          throw const RequestFailure(
            'encoder_unavailable',
            '编码器资源不足，当前会话继续运行。',
          );
        }
        return {
          'current': {'videoCodec': 'h264', 'videoEncoder': null},
          'codecs': [
            codec('h264', 'H.264'),
            codec(
              'h265',
              'H.265',
              decoder: 'unavailable',
              canAttempt: true,
              reason: '本机没有可用解码器。',
            ),
            codec(
              'av1',
              'AV1',
              available: false,
              status: 'unknown',
              canAttempt: true,
              reason: '尚未完成目标编码器探测。',
            ),
            codec('vp8', 'VP8', decoder: 'unknown'),
            codec('vp9', 'VP9', decoder: 'unknown', canAttempt: true),
          ],
        };
      });
      await mount(tester, controller);
      await reveal(tester, '编码格式');
      await tester.tap(find.text('编码格式'));
      await tester.pumpAndSettle();
      for (final label in ['H.265', 'AV1', 'VP8']) {
        final tile = tester.widget<ListTile>(
          find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
        );
        expect(
          tile.enabled,
          isFalse,
          reason: '$label lacks a confirmed encoder and decoder intersection.',
        );
      }
      expect(find.byTooltip('本机没有可用解码器。'), findsOneWidget);
      expect(find.byTooltip('尚未完成目标编码器探测。'), findsOneWidget);
      await tester.ensureVisible(find.text('VP9'));
      await tester.tap(find.text('VP9'));
      await tester.pumpAndSettle();
      expect(find.text('编码器资源不足，当前会话继续运行。'), findsOneWidget);
      expect(requests.where((r) => r.$1 == 'session.quality'), hasLength(1));
      expect(
        requests.where((r) => r.$1 == 'session.quality.options'),
        hasLength(1),
      );
      expect(find.text('H.264'), findsOneWidget);
      expect(requests.where((r) => r.$1 == 'session.stop'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
