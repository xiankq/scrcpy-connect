import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/interop_exception.dart';
import 'package:interop_bridge/src/media/video_presentation.dart';

void main() {
  test(
    'capture stays running until local pause ACK and queued resume waits',
    () async {
      final calls = <String>[];
      final paused = Completer<void>();
      final owner = VideoPresentation(
        core: (command, params) async {
          calls.add('$command:${params['sessionId']}');
          return {'capturePaused': command == 'session.pause'};
        },
        pauseOutput: (id) async {
          calls.add('local.pause:$id');
          await paused.future;
          return {'applied': true, 'paused': true};
        },
        resumeOutput: (id) async {
          calls.add('local.resume:$id');
          return {'applied': true, 'paused': false};
        },
      );
      final pause = owner.request('session.pause', {'sessionId': 'A'});
      final resume = owner.request('session.resume', {'sessionId': 'A'});
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['local.pause:A']);
      paused.complete();
      expect((await pause)['capturePaused'], true);
      expect((await resume)['capturePaused'], false);
      expect(calls, [
        'local.pause:A',
        'session.pause:A',
        'session.resume:A',
        'local.resume:A',
      ]);
    },
  );

  test(
    'failed local pause never suspends capture and restores the consumer',
    () async {
      final calls = <String>[];
      const failure = InteropException('pause_unconfirmed', 'not confirmed');
      final owner = VideoPresentation(
        core: (command, _) async {
          calls.add(command);
          return {};
        },
        pauseOutput: (id) async => throw failure,
        resumeOutput: (id) async {
          calls.add('restore:$id');
          return {};
        },
      );
      await expectLater(
        owner.request('session.pause', {'sessionId': 'A'}),
        throwsA(same(failure)),
      );
      expect(calls, ['restore:A']);
    },
  );

  test(
    'capture failure restores only its own output and preserves original error',
    () async {
      final calls = <String>[];
      const failure = InteropException('disconnected', 'capture ended');
      final owner = VideoPresentation(
        core: (command, params) async => throw failure,
        pauseOutput: (id) async {
          calls.add('pause:$id');
          return {'applied': true};
        },
        resumeOutput: (id) async {
          calls.add('restore:$id');
          throw StateError('rollback also failed');
        },
      );
      await expectLater(
        owner.request('session.pause', {'sessionId': 'A'}),
        throwsA(same(failure)),
      );
      expect(calls, ['pause:A', 'restore:A']);
    },
  );

  test('a stopped source cannot resume its local output', () async {
    final calls = <String>[];
    const failure = InteropException('disconnected', 'already stopped');
    final owner = VideoPresentation(
      core: (_, _) async => throw failure,
      pauseOutput: (_) async => {},
      resumeOutput: (id) async {
        calls.add(id);
        return {};
      },
    );
    await expectLater(
      owner.request('session.resume', {'sessionId': 'A'}),
      throwsA(same(failure)),
    );
    expect(calls, isEmpty);
  });

  test(
    'device lookup resolves the exact existing session before acting',
    () async {
      final calls = <String>[];
      final owner = VideoPresentation(
        core: (command, params) async {
          if (command == 'session.list') {
            return {
              'sessions': [
                {'sessionId': 'A', 'deviceId': 'device-A'},
                {'sessionId': 'B', 'deviceId': 'device-B'},
              ],
            };
          }
          calls.add('$command:${params['sessionId']}');
          return {};
        },
        pauseOutput: (_) async => {},
        resumeOutput: (id) async {
          calls.add('local:$id');
          return {};
        },
      );
      await owner.request('session.resume', {'deviceId': 'device-B'});
      expect(calls, ['session.resume:B', 'local:B']);
    },
  );
}
