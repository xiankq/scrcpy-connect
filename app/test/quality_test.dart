import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';

import 'support/router_test_app.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
            {
              'id': 'h264',
              'name': 'H.264',
              'available': true,
              'status': 'available',
              'decoderStatus': 'available',
              'encoders': [
                {
                  'name': 'c2.avc.encoder',
                  'available': true,
                  'status': 'available',
                },
              ],
            },
            {
              'id': 'h265',
              'name': 'H.265',
              'available': true,
              'status': 'available',
              'decoderStatus': 'available',
              'encoders': [
                {
                  'name': 'c2.hevc.encoder',
                  'available': true,
                  'status': 'available',
                },
              ],
            },
          ],
        };
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: QualityPage(
            controller: controller,
            device: const {'id': 'phone', 'name': '手机'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('画面设置'), findsOneWidget);
      expect(find.text('屏幕比例'), findsOneWidget);
      expect(find.textContaining('关闭后重新打开'), findsNothing);
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
      await tester.ensureVisible(find.text('视频编码器'));
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
      expect(tester.takeException(), isNull);
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
            {
              'id': 'h264',
              'name': 'H.264',
              'available': true,
              'status': 'available',
              'decoderStatus': 'available',
            },
            {
              'id': 'h265',
              'name': 'H.265',
              'available': true,
              'status': 'available',
              'decoderStatus': 'unavailable',
              'canAttempt': true,
              'reason': '本机没有可用解码器。',
            },
            {
              'id': 'av1',
              'name': 'AV1',
              'available': false,
              'status': 'unknown',
              'decoderStatus': 'available',
              'canAttempt': true,
              'reason': '尚未完成目标编码器探测。',
            },
            {
              'id': 'vp8',
              'name': 'VP8',
              'available': true,
              'status': 'available',
              'decoderStatus': 'unknown',
            },
            {
              'id': 'vp9',
              'name': 'VP9',
              'available': true,
              'status': 'available',
              'decoderStatus': 'unknown',
              'canAttempt': true,
            },
          ],
        };
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: QualityPage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('编码格式'));
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
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
