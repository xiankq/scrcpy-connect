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
  'evidence': 'mdk.snapshot',
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
    expect(state.initialActionApplied, isTrue);
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
