import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/remote_presentation.dart';

const _pixels = <String, dynamic>{
  'sessionId': 'original',
  'deviceId': 'phone',
  'status': 'streaming',
  'textureId': 1,
  'width': 200,
  'height': 400,
  'firstFrameDecoded': true,
  'evidence': 'media_codec.decodedFrame',
};

RemotePresentation _viewed() => RemotePresentation()
  ..beginStart()
  ..replaceBinding()
  ..bindStart(
    _pixels,
    retained: false,
    recoveringConnection: false,
    submittedAppStart: false,
  );

bool _input(RemotePresentation state) =>
    state.canSendInput(foreground: true, ownerCurrent: true);

bool _queued(
  RemotePresentation state,
  RemoteBinding binding,
  String command,
  RemoteData params,
) => state.admitsQueuedInput(
  binding,
  command,
  params,
  foreground: true,
  ownerCurrent: true,
);

void main() {
  test('queued hover and scroll lose permission when the window loses input ownership', () {
    final state = _viewed();
    for (final command in ['session.touch', 'session.scroll']) {
      for (final ownership in [(false, true), (true, false)]) {
        expect(
          state.admitsQueuedInput(
            state.binding,
            command,
            {'action': 'hover'},
            foreground: ownership.$1,
            ownerCurrent: ownership.$2,
          ),
          isFalse,
        );
      }
    }
  });
  test('capture resize preserves decoded image proportions and fences input until output catches up', () {
    final state = _viewed();
    state.output({
      ..._pixels,
      'decodedWidth': 200,
      'decodedHeight': 400,
    }, verified: true);
    final outgoing = state.binding;
    expect(state.updateSession({'width': 400, 'height': 200}), isTrue);
    expect(state.imageWidth / state.imageHeight, .5);
    expect(_input(state), isFalse);
    expect(
      _queued(state, outgoing, 'session.touch', {'action': 'down'}),
      isFalse,
    );
    expect(
      state.output({'decodedWidth': 400, 'decodedHeight': 200}, verified: true),
      isTrue,
    );
    expect(state.imageWidth / state.imageHeight, 2);
    expect(_input(state), isTrue);
  });

  test('a retained older texture in a new snapshot is a display placeholder until matching output verifies', () {
    final state = _viewed();
    state.beginReconciliation();
    state.reconcile(
      {
        'sequence': 100,
        'sessions': [
          {
            ..._pixels,
            'captureGeneration': 2,
            'rendererGeneration': 20,
            'generation': 20,
            'qualityRebuilding': false,
            'qualityRebuildOutcome': 'applied',
            'qualityRebuildTarget': 2,
            'width': 400,
            'height': 200,
            'decodedWidth': 200,
            'decodedHeight': 400,
            'outputCaptureGeneration': 1,
            'outputGeneration': 10,
            'outputRetained': true,
            'firstFrameDecoded': false,
            'evidence': 'retained_previous_output',
          },
        ],
      },
      packageName: null,
      deviceId: 'phone',
    );
    expect(_input(state), isFalse);
    expect(state.session?['textureId'], 1);
    expect(state.session?['width'], 200);
    expect(state.session?['height'], 400);
    state.output({
      ..._pixels,
      'captureGeneration': 1,
      'generation': 999,
    }, verified: true);
    expect(_input(state), isFalse);
    state.output({
      ..._pixels,
      'captureGeneration': 2,
      'generation': 20,
      'textureId': 2,
      'width': 400,
      'height': 200,
      'decodedWidth': 400,
      'decodedHeight': 200,
      'outputCaptureGeneration': 2,
      'outputGeneration': 20,
    }, verified: true);
    expect(_input(state), isTrue);
    expect(state.session?['textureId'], 2);
    expect(state.session?['width'], 400);
  });
  test('retryable quality failure snapshot retains its window without resume or launch permission', () {
    final state = _viewed()..beginReconciliation();
    state.reconcile(
      {
        'sequence': 101,
        'sessions': [
          {
            ..._pixels,
            'status': 'failed',
            'qualityRetryable': true,
            'qualityRebuildOutcome': 'failed',
          },
        ],
      },
      packageName: null,
      deviceId: 'phone',
    );
    expect(state.sessionEnded, isFalse);
    expect(state.qualityRetryable, isTrue);
    expect(state.sessionId, 'original');
    expect(state.session?['textureId'], 1);
    expect(_input(state), isFalse);
    expect(state.canResume(foreground: true), isFalse);
  });
  for (final readyFirst in [false, true]) {
    test(
      'quality barrier requires matching capture ready and verified output, readyFirst=$readyFirst',
      () {
        final state = _viewed();
        state.updateSession({'captureGeneration': 1, 'generation': 10});
        final old = state.binding;
        expect(
          state.updateSession({
            'qualityRebuilding': true,
            'qualityRebuildTarget': 2,
          }),
          isTrue,
        );
        expect(_input(state), isFalse);
        expect(state.binding, isNot(old));
        expect(state.session?['textureId'], 1);
        expect(_queued(state, old, 'session.key', {'action': 'up'}), isTrue);
        expect(
          _queued(state, old, 'session.touch', {'action': 'cancel'}),
          isTrue,
        );
        expect(_queued(state, old, 'session.rotate', {}), isFalse);
        final fresh = {
          ..._pixels,
          'captureGeneration': 2,
          'generation': 20,
          'textureId': 2,
        };
        final ready = {
          ...fresh,
          'qualityRebuilding': false,
          'qualityRebuildOutcome': 'applied',
        };
        if (readyFirst) {
          state.updateSession(ready);
        } else {
          state.output(fresh, verified: true);
        }
        expect(_input(state), isFalse);
        expect(state.session?['textureId'], 1);
        if (readyFirst) {
          state.output(fresh, verified: true);
        } else {
          state.updateSession(ready);
        }
        expect(_input(state), isTrue);
        expect(state.sessionId, 'original');
        expect(state.session?['textureId'], 2);
        expect(_queued(state, old, 'session.text', {'text': 'late'}), isFalse);
      },
    );
  }
  test(
    'old capture output and ready cannot unlock quality; explicit rollback can',
    () {
      final state = _viewed();
      state.updateSession({'captureGeneration': 1, 'generation': 10});
      final resume = state.beginResume();
      state.updateSession({
        'qualityRebuilding': true,
        'qualityRebuildTarget': 2,
      });
      expect(
        state.completeResume(resume, _pixels, ownerCurrent: true),
        RemoteResumeResult.stale,
      );
      expect(
        state.output({
          ..._pixels,
          'captureGeneration': 1,
          'generation': 999,
        }, verified: true),
        isFalse,
      );
      state.updateSession({
        'qualityRebuilding': false,
        'status': 'streaming',
        'captureGeneration': 1,
        'generation': 10,
      });
      expect(_input(state), isFalse);
      expect(
        state.acceptsFailure({'captureGeneration': 1, 'generation': 999}),
        isFalse,
      );
      state.updateSession({
        'qualityRebuilding': false,
        'qualityRebuildOutcome': 'restored',
        'status': 'streaming',
        'captureGeneration': 1,
        'generation': 10,
      });
      expect(_input(state), isTrue);
      expect(state.session?['textureId'], 1);
    },
  );
  test(
    'lost quality capture stays unavailable until an explicit retry succeeds',
    () {
      final state = _viewed();
      state.updateSession({'captureGeneration': 1, 'generation': 10});
      state.updateSession({
        'qualityRebuilding': true,
        'qualityRebuildTarget': 2,
      });
      state.updateSession({
        'qualityRebuilding': false,
        'qualityRebuildOutcome': 'failed',
        'qualityRetryable': true,
        'status': 'failed',
        'reason': 'encoder failed',
        'captureGeneration': 1,
        'generation': 10,
      });
      expect(_input(state), isFalse);
      expect(state.qualityRetryable, isTrue);
      expect(state.session?['textureId'], 1);
      state.output({
        ..._pixels,
        'captureGeneration': 1,
        'generation': 10,
      }, verified: true);
      state.updateSession({
        'status': 'streaming',
        'captureGeneration': 1,
        'generation': 10,
      });
      expect(_input(state), isFalse);
      expect(state.canResume(foreground: true), isFalse);
      state.updateSession({
        'qualityRebuilding': true,
        'qualityRebuildTarget': 2,
      });
      final fresh = {
        ..._pixels,
        'captureGeneration': 2,
        'generation': 20,
        'textureId': 2,
      };
      state.updateSession({
        ...fresh,
        'qualityRebuilding': false,
        'qualityRebuildOutcome': 'applied',
      });
      state.output(fresh, verified: true);
      expect(_input(state), isTrue);
      expect(state.qualityRetryable, isFalse);
    },
  );
  test('only current visible foreground ownership admits new input', () {
    final state = _viewed();
    expect(_input(state), isTrue);
    expect(state.canSendInput(foreground: false, ownerCurrent: true), isFalse);
    expect(state.canSendInput(foreground: true, ownerCurrent: false), isFalse);
    state.cover(true);
    expect(_input(state), isFalse);
    state.cover(false);
    final epoch = state.beginResume();
    expect(_input(state), isFalse);
    expect(
      state.completeResume(epoch, {'textureId': 2}, ownerCurrent: true),
      RemoteResumeResult.rendererNotReady,
    );
    expect(_input(state), isFalse);
    expect(
      state.completeResume(epoch, _pixels, ownerCurrent: true),
      RemoteResumeResult.ready,
    );
    expect(_input(state), isTrue);
  });

  for (final interruption in [
    'cover',
    'background',
    'disconnect',
    'resync',
    'exit',
    'owner',
  ]) {
    test('a late resume cannot restore input after $interruption', () {
      final state = _viewed();
      final epoch = state.beginResume();
      switch (interruption) {
        case 'cover':
          state.cover(true);
          state.beginPause();
        case 'background':
          state.lifecycleVisibility(false);
          state.beginPause();
        case 'disconnect':
          state.disconnect('connection ended');
        case 'resync':
          state.beginReconciliation();
          state.replaceBinding();
        case 'exit':
          state.leave();
        case 'owner':
          break;
      }
      expect(
        state.completeResume(epoch, {
          ..._pixels,
          'textureId': 99,
        }, ownerCurrent: interruption != 'owner'),
        RemoteResumeResult.stale,
      );
      expect(_input(state), isFalse);
      expect(state.session?['textureId'], 1);
    });
  }

  test('queued input stays with its binding while UP cleanup drains', () {
    final state = _viewed();
    final old = state.binding;
    state.beginPause();
    expect(_queued(state, old, 'session.key', {'action': 'down'}), isFalse);
    expect(_queued(state, old, 'session.key', {'action': 'up'}), isTrue);
    expect(_queued(state, old, 'session.touch', {'action': 'cancel'}), isTrue);
    state.replaceBinding();
    state.bindStart(
      {..._pixels, 'sessionId': 'replacement'},
      retained: false,
      recoveringConnection: false,
      submittedAppStart: false,
    );
    expect(_input(state), isTrue);
    expect(_queued(state, old, 'session.text', {'text': 'late'}), isFalse);
    expect(_queued(state, old, 'session.key', {'action': 'up'}), isFalse);
    expect(_queued(state, old, 'session.touch', {'action': 'cancel'}), isFalse);
  });

  test('unknown app record permits only captured cleanup until drained', () {
    final state = _viewed();
    final outgoing = state.permitDetachedCleanup();
    state.detachBinding();
    state.showUnknownAppLaunch({
      'sessionId': 'operation',
      'launchOutcome': 'unknown',
    });
    expect(_input(state), isFalse);
    expect(state.canResume(foreground: true), isFalse);
    expect(_queued(state, outgoing, 'session.text', {'text': 'late'}), isFalse);
    expect(_queued(state, outgoing, 'session.key', {'action': 'up'}), isTrue);
    expect(
      _queued(state, outgoing, 'session.touch', {'action': 'cancel'}),
      isTrue,
    );
    state.finishDetachedCleanup(outgoing);
    expect(_queued(state, outgoing, 'session.key', {'action': 'up'}), isFalse);
    state.closeUnknownAppLaunch(resetInitialAction: true);
    expect(state.sessionId, isEmpty);
    expect(state.appLaunchUnknown, isFalse);
    expect(state.appLaunchClosed, isTrue);
    expect(_input(state), isFalse);
  });

  test('resync freezes attempts and requires a verified capture receipt', () {
    final state = _viewed();
    final attempt = state.beginStart();
    state.beginReconciliation();
    state.replaceBinding();
    expect(state.acceptsStart(attempt), isFalse);
    expect(state.requiresVerification(attempt), isTrue);
    expect(_input(state), isFalse);
    final snapshot = <String, dynamic>{
      'sequence': 4,
      'sessions': [_pixels],
    };
    expect(
      state.reconcile(snapshot, packageName: null, deviceId: 'phone'),
      isTrue,
    );
    expect(state.stateUnverified, isFalse);
    expect(_input(state), isFalse);
    final epoch = state.beginResume();
    expect(
      state.completeResume(epoch, _pixels, ownerCurrent: true),
      RemoteResumeResult.ready,
    );
    expect(_input(state), isTrue);
    expect(
      state.takeInitialAction(foreground: true, ownerCurrent: true),
      isFalse,
      reason:
          'Recovery must not replay the initial action after input resumes.',
    );
    expect(
      state.reconcile(snapshot, packageName: null, deviceId: 'phone'),
      isFalse,
    );
    expect(
      _input(state),
      isTrue,
      reason: 'Duplicate snapshots must not pause a resumed view.',
    );
  });

  test(
    'unknown app snapshot without a bound session never creates authority',
    () {
      final state = RemotePresentation()..beginReconciliation();
      state.reconcile(
        {
          'sequence': 1,
          'sessions': [
            {
              'sessionId': 'operation',
              'deviceId': 'phone',
              'packageName': 'example.app',
              'launchOutcome': 'unknown',
              'textureId': 4,
            },
          ],
        },
        packageName: 'example.app',
        deviceId: 'phone',
      );
      expect(state.appLaunchUnknown, isTrue);
      expect(state.sessionId, 'operation');
      expect(state.session?['textureId'], isNull);
      expect(state.canResume(foreground: true), isFalse);
      expect(_input(state), isFalse);
    },
  );

  test('missing session rejects resume and automatic connection recovery', () {
    final state = _viewed()
      ..beginReconciliation()
      ..replaceBinding();
    state.reconcile(
      {'sequence': 5, 'sessions': <RemoteData>[]},
      packageName: null,
      deviceId: 'phone',
    );
    expect(state.sessionEnded, isTrue);
    expect(state.stateUnverified, isTrue);
    expect(state.session?['textureId'], isNull);
    expect(state.canResume(foreground: true), isFalse);
    expect(
      state.canRecoverConnection(
        foreground: true,
        phoneScreen: true,
        reconciliationPending: false,
        routeCurrent: true,
      ),
      isFalse,
    );
  });

  test(
    'one-shot initial action is consumed before its asynchronous receipt',
    () {
      final state = _viewed();
      expect(
        state.takeInitialAction(foreground: true, ownerCurrent: true),
        isTrue,
      );
      state.beginPause();
      final epoch = state.beginResume();
      state.completeResume(epoch, _pixels, ownerCurrent: true);
      expect(
        state.takeInitialAction(foreground: true, ownerCurrent: true),
        isFalse,
      );
    },
  );
}
