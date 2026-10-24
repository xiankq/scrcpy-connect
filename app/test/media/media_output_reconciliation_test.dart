import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/media/output/media_output_reconciliation.dart';
import 'package:scrcpy_connect/application/events/state_recovery.dart';

import '../application/events/state_recovery_test.dart' show snapshot;

void main() {
  test('quality retry retains failed window but explicit stop and disconnect retire it', () async {
    for (final status in ['failed', 'stopped', 'disconnected']) {
      final videos = <String, StateJson>{
        'A': {'textureId': 8},
      };
      final closed = <String>[];
      await readAndReconcileMediaSnapshot(
        read: () async => {
          ...snapshot(1),
          'sessions': [
            {'sessionId': 'A', 'status': status, 'qualityRetryable': true},
          ],
        },
        videos: videos,
        audios: {},
        closeVideo: (id) async {
          closed.add(id);
          videos.remove(id);
        },
        closeAudio: (_) async {},
        current: () => true,
      );
      expect(closed, status == 'failed' ? isEmpty : ['A']);
    }
  });

  test('only ended exact owners are retired and application state remains authoritative', () async {
    final videos = <String, StateJson>{
      'alive': {'textureId': 7, 'status': 'streaming', 'capturePaused': false},
      'ended': {'textureId': 8},
    };
    final audios = <String, StateJson>{'sound': {}, 'gone': {}, 'error': {}};
    final closed = <String>[];
    final result = await readAndReconcileMediaSnapshot(
      read: () async => {
        ...snapshot(5),
        'sessions': [
          {'sessionId': 'alive', 'status': 'paused', 'capturePaused': true},
          {'sessionId': 'ended', 'status': 'failed'},
        ],
        'sources': [
          {'sourceId': 'sound', 'status': 'paused'},
          {'sourceId': 'error', 'status': 'error'},
        ],
      },
      videos: videos,
      audios: audios,
      closeVideo: (id) async {
        closed.add('video:$id');
        videos.remove(id);
      },
      closeAudio: (id) async {
        closed.add('audio:$id');
        audios.remove(id);
      },
      current: () => true,
    );
    expect(closed, ['video:ended', 'audio:gone', 'audio:error']);
    final session = (result['sessions'] as List).first as StateJson;
    expect(session['textureId'], 7);
    expect(session['status'], 'paused');
    expect(session['capturePaused'], isTrue);
    expect(audios.keys, ['sound']);
  });

  test(
    'a pending read cannot retire replacement or newly created owners',
    () async {
      final reading = Completer<StateJson>();
      final videos = <String, StateJson>{
        'replace': {'textureId': 1},
        'old': {'textureId': 2},
      };
      final audios = <String, StateJson>{'replace': {}, 'old': {}};
      final closed = <String>[];
      final result = readAndReconcileMediaSnapshot(
        read: () => reading.future,
        videos: videos,
        audios: audios,
        closeVideo: (id) async {
          closed.add('video:$id');
          videos.remove(id);
        },
        closeAudio: (id) async {
          closed.add('audio:$id');
          audios.remove(id);
        },
        current: () => true,
      );
      videos['replace'] = {'textureId': 3};
      videos['new'] = {'textureId': 4};
      audios['replace'] = {};
      audios['new'] = {};
      reading.complete(snapshot(3));
      await result;
      expect(closed, ['video:old', 'audio:old']);
      expect(videos.keys, ['replace', 'new']);
      expect(audios.keys, ['replace', 'new']);
    },
  );

  test('invalid or cancelled reads cannot authorize cleanup', () async {
    for (final valid in [false, true]) {
      final closed = <String>[];
      await expectLater(
        readAndReconcileMediaSnapshot(
          read: () async => valid ? snapshot(1) : {'sequence': 1},
          videos: {'A': {}},
          audios: {'B': {}},
          closeVideo: (id) async {
            closed.add(id);
          },
          closeAudio: (id) async {
            closed.add(id);
          },
          current: () => !valid,
        ),
        throwsA(isA<ApplicationCommandException>()),
      );
      expect(closed, isEmpty);
    }
  });
}
