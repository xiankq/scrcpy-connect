import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/session_views.dart';

void main() {
  test(
    'failed resume still pauses capture when the view is released',
    () async {
      final commands = <String>[];
      final views = SessionViews((command, [params = const {}]) async {
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
    final views = SessionViews((command, [params = const {}]) async {
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
      final views = SessionViews((command, [params = const {}]) async {
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
    final views = SessionViews((command, [params = const {}]) async {
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
    final views = SessionViews((command, [params = const {}]) async {
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
