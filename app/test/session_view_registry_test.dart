import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';

void main() {
  test('a retryable quality failure retains the same owner through snapshots and closes exactly', () async {
    final calls = <(String, SessionJson)>[];
    final views = SessionViewRegistry((command, [params = const {}]) async {
      calls.add((command, params));
      return {};
    });
    final owner = views.claim('window', visible: true);
    views.markUncertain();
    views.reconcile([
      {'sessionId': 'window', 'status': 'failed', 'qualityRetryable': true},
    ]);
    expect(owner.isCurrent, isTrue);
    await owner.close();
    expect(calls.single.$1, 'session.stop');
    expect(calls.single.$2, {'sessionId': 'window', 'keepTask': true});
  });
  test(
    'explicit close stops only its exact window and preserves the real task',
    () async {
      final calls = <(String, SessionJson)>[];
      final views = SessionViewRegistry((command, [params = const {}]) async {
        calls.add((command, params));
        return {};
      });
      final one = views.claim('one', visible: true);
      final two = views.claim('two', visible: true);
      await one.close();
      await one.resume();
      await one.close();
      expect(calls, hasLength(1));
      expect(calls.single.$1, 'session.stop');
      expect(calls.single.$2, {'sessionId': 'one', 'keepTask': true});
      expect(one.isCurrent, isFalse);
      expect(() => views.claim('one', visible: true), throwsStateError);
      expect(two.isCurrent, isTrue);
    },
  );
  test(
    'close releases a window even while its prior pause receipt is blocked',
    () async {
      final pause = Completer<SessionJson>();
      final calls = <String>[];
      final views = SessionViewRegistry((command, [params = const {}]) async {
        calls.add(command);
        return command == 'session.pause' ? pause.future : {};
      });
      final window = views.claim('one', visible: true);
      final pendingPause = window.pause();
      await Future<void>.delayed(Duration.zero);
      await window.close();
      expect(calls, ['session.pause', 'session.stop']);
      expect(window.isCurrent, isFalse);
      pause.complete({});
      await pendingPause;
      await window.resume();
      expect(calls, ['session.pause', 'session.stop']);
    },
  );

  test('ended transport revokes queued old visibility without touching a successor', () async {
    final commands = <String>[];
    final gate = Completer<void>();
    final views = SessionViewRegistry((command, [params = const {}]) async {
      commands.add('$command:${params['sessionId']}');
      return {};
    });
    final old = views.claim('old', visible: true);
    final pending = old.pause(afterInput: gate.future);
    old.abandonEndedSession();
    final successor = views.claim('old', visible: false);
    old.abandonEndedSession();
    gate.complete();
    await pending;
    await old.resume();
    await old.release();
    expect(commands, isEmpty);
    expect(old.isCurrent, false);
    expect(successor.isCurrent, true);
    await successor.resume();
    expect(commands, ['session.resume:old']);
  });
  test(
    'leaving during unknown state still pauses its exact live owner as cleanup',
    () async {
      final commands = <String>[];
      final views = SessionViewRegistry((command, [params = const {}]) async {
        commands.add('$command:${params['sessionId']}');
        return {};
      });
      final live = views.claim('live', visible: true);
      views.markUncertain();
      await live.release();
      expect(commands, ['session.pause:live']);
      views.reconcile([
        {'sessionId': 'live', 'status': 'streaming'},
      ]);
      await live.release();
      expect(commands, ['session.pause:live']);
    },
  );

  test(
    'a visibility command queued before resync cannot run after calibration',
    () async {
      final commands = <String>[];
      final input = Completer<void>();
      final views = SessionViewRegistry((command, [params = const {}]) async {
        commands.add(command);
        return {};
      });
      final live = views.claim('live', visible: true);
      final oldPause = live.pause(afterInput: input.future);
      final oldResume = live.resume();
      await Future<void>.delayed(Duration.zero);
      views.markUncertain();
      views.reconcile([
        {'sessionId': 'live', 'status': 'paused', 'capturePaused': true},
      ]);
      final verifiedResume = live.resume();
      input.complete();
      await Future.wait([oldPause, oldResume, verifiedResume]);
      expect(commands, ['session.resume']);
    },
  );

  test('snapshot calibration invalidates missing and terminal owners without releasing them', () async {
    final commands = <String>[];
    final views = SessionViewRegistry((command, [params = const {}]) async {
      commands.add('$command:${params['sessionId']}');
      return {};
    });
    final missing = views.claim('missing', visible: true);
    final failed = views.claim('failed', visible: true);
    final live = views.claim('live', visible: false);
    views.reconcile([
      {'sessionId': 'failed', 'status': 'failed'},
      {'sessionId': 'live', 'status': 'paused', 'capturePaused': true},
    ]);
    expect(missing.isCurrent, isFalse);
    expect(failed.isCurrent, isFalse);
    expect(live.isCurrent, isTrue);
    await missing.release();
    await failed.resume();
    await live.resume();
    expect(commands, ['session.resume:live']);
  });

  test(
    'failed resume still pauses presentation when the view is released',
    () async {
      final commands = <String>[];
      final views = SessionViewRegistry((command, [params = const {}]) async {
        commands.add(command);
        if (command == 'session.resume') {
          throw StateError('decoder unavailable after capture resumed');
        }
        return {};
      });
      final view = views.claim('one', visible: false);
      await expectLater(view.resume(), throwsStateError);
      await view.release();
      expect(commands, ['session.resume', 'session.pause']);
      expect(view.isCurrent, isFalse);
    },
  );

  test('a successor verifies resume after an in-flight pause despite a stale visible snapshot', () async {
    final commands = <String>[];
    final paused = Completer<Map<String, dynamic>>();
    final views = SessionViewRegistry((command, [params = const {}]) async {
      commands.add(command);
      return command == 'session.pause' ? paused.future : {};
    });
    final old = views.claim('one', visible: true);
    final stopping = old.pause();
    await Future<void>.delayed(Duration.zero);
    final next = views.claim('one', visible: true);
    final resumed = next.resume();
    paused.complete({});
    await stopping;
    await resumed;
    expect(commands, ['session.pause', 'session.resume']);
  });

  test(
    'a successor waits for old input releases and a stale view cannot pause it',
    () async {
      final commands = <String>[];
      final views = SessionViewRegistry((command, [params = const {}]) async {
        commands.add('$command:${params['sessionId']}');
        return {};
      });
      final old = views.claim('one', visible: true);
      final input = Completer<void>();
      final release = old.release(afterInput: input.future);
      final next = views.claim('one', visible: false);
      final resumed = next.resume();
      await Future<void>.delayed(Duration.zero);
      expect(commands, isEmpty);
      input.complete();
      await release;
      await resumed;
      expect(commands, ['session.resume:one']);
      await old.pause();
      expect(commands, ['session.resume:one']);
      expect(next.isCurrent, isTrue);
    },
  );
  test('return pauses only its own session and does not stop the persistent activity', () async {
    final commands = <String>[];
    final views = SessionViewRegistry((command, [params = const {}]) async {
      commands.add('$command:${params['sessionId']}');
      return {};
    });
    final one = views.claim('one', visible: true);
    final two = views.claim('two', visible: true);
    await one.release();
    expect(commands, ['session.pause:one']);
    expect(two.isCurrent, isTrue);
    await two.pause();
    await two.pause();
    await two.resume();
    expect(commands, [
      'session.pause:one',
      'session.pause:two',
      'session.resume:two',
    ]);
  });
  test('failed pause preserves ownership for an explicit retry', () async {
    var attempts = 0;
    final views = SessionViewRegistry((command, [params = const {}]) async {
      if (++attempts == 1) throw StateError('capture did not pause');
      return {};
    });
    final view = views.claim('one', visible: true);
    await expectLater(view.release(), throwsStateError);
    expect(view.isCurrent, isTrue);
    await view.release();
    expect(attempts, 2);
    expect(view.isCurrent, isFalse);
  });
}
