import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/media/quality/device_quality_coordinator.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';

void main() {
  test(
    'startup and quality save serialize through renderer verification',
    () async {
      final initial = Completer<QualityJson>();
      final rebuild = Completer<QualityJson>();
      final calls = <String>[];
      final coordinator = DeviceQualityCoordinator(
        request: (command, params) async {
          calls.add(command);
          if (command == 'session.quality') {
            return {
              'current': {'maxSize': 1920},
            };
          }
          if (command == 'session.list') {
            return {
              'sessions': [
                {'deviceId': 'phone', 'sessionId': 'A'},
              ],
            };
          }
          return rebuild.future;
        },
        applyOutput: (stream) async => stream,
      );
      final first = coordinator.open('phone', () {
        calls.add('initial');
        return initial.future;
      });
      final change = coordinator.change({'deviceId': 'phone'});
      final after = coordinator.open('phone', () async {
        calls.add('later');
        return {};
      });
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['initial']);
      initial.complete({});
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(calls, [
        'initial',
        'session.quality',
        'session.list',
        'session.reconfigure',
      ]);
      rebuild.complete({
        'deviceId': 'phone',
        'sessionId': 'A',
        'generation': 2,
      });
      await change;
      await after;
      expect(calls.last, 'later');
    },
  );

  test(
    'saves once then applies every same-device window including paused',
    () async {
      final calls = <(String, QualityJson)>[];
      final coordinator = DeviceQualityCoordinator(
        request: (command, params) async {
          calls.add((command, params));
          if (command == 'session.quality') {
            return {
              'current': {
                'qualityPreset': 'clear',
                'maxSize': 1920,
                'videoCodec': 'h264',
              },
            };
          }
          if (command == 'session.list') {
            return {
              'sessions': [
                {
                  'deviceId': 'phone',
                  'sessionId': 'screen',
                  'status': 'streaming',
                },
                {
                  'deviceId': 'phone',
                  'sessionId': 'app',
                  'status': 'paused',
                  'name': '设置',
                },
                {
                  'deviceId': 'other',
                  'sessionId': 'foreign',
                  'status': 'streaming',
                },
                {
                  'deviceId': 'phone',
                  'sessionId': 'closed',
                  'status': 'stopped',
                },
              ],
            };
          }
          return {...params, 'generation': 2};
        },
        applyOutput: (stream) async => {...stream, 'textureId': 7},
      );
      final result = await coordinator.change({
        'deviceId': 'phone',
        'maxSize': 1920,
      });
      expect(calls.where((call) => call.$1 == 'session.quality'), hasLength(1));
      expect(
        calls
            .where((call) => call.$1 == 'session.reconfigure')
            .map((call) => call.$2['sessionId']),
        ['screen', 'app'],
      );
      expect(
        calls
            .where((call) => call.$1 == 'session.reconfigure')
            .map((call) => call.$2['qualityPreset']),
        ['clear', 'clear'],
      );
      expect(result['appliedToAll'], true);
      expect(result['failures'], isEmpty);
      expect(result['appliedSessions'], hasLength(2));
    },
  );
  test(
    'reports actual partial failures and continues remaining windows',
    () async {
      final coordinator = DeviceQualityCoordinator(
        request: (command, params) async {
          if (command == 'session.quality') {
            return {
              'current': {'maxSize': 1280},
            };
          }
          if (command == 'session.list') {
            return {
              'sessions': [
                {'deviceId': 'phone', 'sessionId': 'A', 'name': '设置'},
                {'deviceId': 'phone', 'sessionId': 'B', 'name': '手机屏幕'},
              ],
            };
          }
          if (params['sessionId'] == 'A') {
            throw const ApplicationCommandException('encoder_failed', '编码器失败');
          }
          return {...params, 'generation': 2};
        },
        applyOutput: (stream) async => stream,
      );
      final result = await coordinator.change({'deviceId': 'phone'});
      expect(result['saved'], true);
      expect(result['appliedToAll'], false);
      expect(result['appliedSessions'], hasLength(1));
      expect(result['failures'], [
        {
          'sessionId': 'A',
          'name': '设置',
          'reason': '编码器失败',
          'code': 'encoder_failed',
        },
      ]);
    },
  );
  test(
    'explicit close wins over pending generation and no renderer attaches',
    () async {
      final started = Completer<void>();
      final rebuild = Completer<QualityJson>();
      var attaches = 0;
      final coordinator = DeviceQualityCoordinator(
        request: (command, params) async {
          if (command == 'session.quality') {
            return {
              'current': {'maxSize': 1280},
            };
          }
          if (command == 'session.list') {
            return {
              'sessions': [
                {'deviceId': 'phone', 'sessionId': 'A'},
              ],
            };
          }
          started.complete();
          return rebuild.future;
        },
        applyOutput: (stream) async {
          attaches++;
          return stream;
        },
      );
      final result = coordinator.change({'deviceId': 'phone'});
      await started.future;
      coordinator.beforeRequest('session.stop', {'sessionId': 'A'});
      rebuild.complete({
        'deviceId': 'phone',
        'sessionId': 'A',
        'generation': 2,
      });
      expect((await result)['skippedSessions'], ['A']);
      expect(attaches, 0);
    },
  );
  test(
    'disconnect prevents queued stale quality work and remaining captures',
    () async {
      final saved = Completer<QualityJson>();
      var lists = 0;
      final coordinator = DeviceQualityCoordinator(
        request: (command, params) async {
          if (command == 'session.quality') return saved.future;
          lists++;
          return {};
        },
        applyOutput: (stream) async => stream,
      );
      final first = coordinator.change({'deviceId': 'phone'});
      final second = coordinator.change({'deviceId': 'phone'});
      final errors = [
        expectLater(first, throwsA(isA<ApplicationCommandException>())),
        expectLater(second, throwsA(isA<ApplicationCommandException>())),
      ];
      await Future<void>.delayed(Duration.zero);
      coordinator.beforeRequest('devices.disconnect', {'deviceId': 'phone'});
      saved.complete({
        'current': {'maxSize': 1280},
      });
      await Future.wait(errors);
      expect(lists, 0);
    },
  );
}
