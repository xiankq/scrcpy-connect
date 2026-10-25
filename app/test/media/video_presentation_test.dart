import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/media/output/video_presentation.dart';

void main() {
  test(
    'retained old texture does not manufacture evidence for new capture',
    () {
      final combined = sessionWithVideoOutput(
        {
          'sessionId': 'A',
          'captureGeneration': 2,
          'generation': 7,
          'qualityRebuilding': true,
        },
        {
          'sessionId': 'A',
          'captureGeneration': 1,
          'generation': 6,
          'textureId': 9,
          'firstFrameDecoded': true,
          'evidence': 'media_codec.decodedFrame',
        },
      );
      expect(combined['textureId'], 9);
      expect(combined['captureGeneration'], 2);
      expect(combined['generation'], 7);
      expect(combined['outputCaptureGeneration'], 1);
      expect(combined['outputGeneration'], 6);
      expect(combined['firstFrameDecoded'], false);
      expect(combined['outputRetained'], true);
    },
  );

  test('a delayed old resume cannot replace a committed generation, whose resume still updates state', () async {
    final oldResume = Completer<Map<String, dynamic>>();
    final resumed = Completer<void>();
    var calls = 0;
    final presentation = VideoPresentation(
      request: (_, params) async => {'sessionId': params['sessionId']},
      pauseOutput: (_) async => {},
      resumeOutput: (_) async {
        if (++calls == 1) {
          resumed.complete();
          return oldResume.future;
        }
        return {
          'generation': 2,
          'textureId': 8,
          'paused': false,
          'firstFrameDecoded': true,
          'evidence': 'media_codec.decodedFrame',
          'snapshotReceipts': 2,
        };
      },
    );
    var output = <String, dynamic>{
      'sessionId': 'A',
      'generation': 1,
      'textureId': 7,
      'paused': true,
    };
    final restoring = presentation.request('session.resume', {
      'sessionId': 'A',
    });
    await resumed.future;

    // 旧恢复操作等待像素期间，轮询器提交了替换输出。
    output = mergeVideoOutputReceipt(output, {
      'generation': 2,
      'textureId': 8,
      'paused': true,
      'firstFrameDecoded': true,
      'evidence': 'media_codec.decodedFrame',
      'snapshotReceipts': 1,
    });
    oldResume.complete({
      'generation': 1,
      'textureId': 7,
      'paused': false,
      'firstFrameDecoded': true,
      'evidence': 'media_codec.decodedFrame',
      'snapshotReceipts': 9,
    });
    output = mergeVideoOutputReceipt(output, await restoring);
    expect(output, {
      'sessionId': 'A',
      'generation': 2,
      'textureId': 8,
      'paused': true,
      'firstFrameDecoded': true,
      'evidence': 'media_codec.decodedFrame',
      'snapshotReceipts': 1,
    });

    output = mergeVideoOutputReceipt(
      output,
      await presentation.request('session.resume', {'sessionId': 'A'}),
    );
    expect(output['generation'], 2);
    expect(output['textureId'], 8);
    expect(output['paused'], isFalse);
    expect(output['firstFrameDecoded'], isTrue);
    expect(output['evidence'], 'media_codec.decodedFrame');
    expect(output['snapshotReceipts'], 2);
  });

  test(
    'presentation pause waits for local ACK and serializes queued resume',
    () async {
      final calls = <String>[];
      final paused = Completer<void>();
      final owner = VideoPresentation(
        request: (command, params) async {
          calls.add('$command:${params['sessionId']}');
          return {
            'capturePaused': false,
            'presentationOnly': true,
            'status': command == 'session.pause' ? 'paused' : 'streaming',
          };
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
      final pausedReceipt = await pause;
      expect(pausedReceipt['capturePaused'], false);
      expect(pausedReceipt['presentationOnly'], true);
      expect(pausedReceipt['paused'], true);
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
      const failure = ApplicationCommandException(
        'pause_unconfirmed',
        'not confirmed',
      );
      final owner = VideoPresentation(
        request: (command, _) async {
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
      const failure = ApplicationCommandException(
        'disconnected',
        'capture ended',
      );
      final owner = VideoPresentation(
        request: (command, params) async => throw failure,
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
}
