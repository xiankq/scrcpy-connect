import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/remote_input_queue.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

void main() {
  const binding = ('session', 1);

  test('coalesces pending moves while an earlier input is in flight', () async {
    final firstDispatch = Completer<void>();
    final calls = <Json>[];
    final queue = RemoteInputQueue(
      admits: (_, _, _) => true,
      dispatch: (_, params, _) async {
        calls.add({...params});
        if (calls.length == 1) await firstDispatch.future;
      },
    );

    final down = queue.enqueue('session.touch', {
      'action': 'down',
      'pointerId': 7,
      'x': 10,
      'y': 20,
    }, binding);
    await Future<void>.delayed(Duration.zero);
    expect(calls, hasLength(1));

    final move1 = queue.enqueue('session.touch', {
      'action': 'move',
      'pointerId': 7,
      'x': 20,
      'y': 20,
    }, binding);
    final move2 = queue.enqueue('session.touch', {
      'action': 'move',
      'pointerId': 7,
      'x': 30,
      'y': 20,
    }, binding);
    final move3 = queue.enqueue('session.touch', {
      'action': 'move',
      'pointerId': 7,
      'x': 40,
      'y': 20,
    }, binding);
    final up = queue.enqueue('session.touch', {
      'action': 'up',
      'pointerId': 7,
      'x': 40,
      'y': 20,
    }, binding);

    expect(calls, hasLength(1));
    firstDispatch.complete();
    await queue.idle;
    await Future.wait([down, move1, move2, move3, up]);

    expect(calls.map((call) => call['action']), ['down', 'move', 'up']);
    expect(calls.map((call) => call['x']), [10, 40, 40]);
  });

  test('a stalled move storm retains one shared completion', () async {
    final gate = Completer<void>();
    final calls = <Json>[];
    final queue = RemoteInputQueue(
      admits: (_, _, _) => true,
      dispatch: (_, params, _) async {
        calls.add(params);
        if (calls.length == 1) await gate.future;
      },
    );
    final down = queue.enqueue('session.touch', {'action': 'down', 'pointerId': 1}, binding);
    final first = queue.enqueue('session.touch', {'action': 'move', 'pointerId': 1, 'x': 0}, binding);
    for (var index = 1; index <= 10000; index++) {
      expect(identical(first, queue.enqueue('session.touch', {
        'action': 'move', 'pointerId': 1, 'x': index,
      }, binding)), isTrue);
    }
    gate.complete();
    await Future.wait([down, first, queue.idle]);
    expect(calls.last['x'], 10000);
    expect(calls, hasLength(2));
  });

  test('edge admission is bounded while an earlier dispatch stalls', () async {
    final gate = Completer<void>();
    final queue = RemoteInputQueue(capacity: 2,
      admits: (_, _, _) => true,
      dispatch: (_, _, _) => gate.future,
    );
    final first = queue.enqueue('session.text', {'text': 'first'}, binding);
    final second = queue.enqueue('session.text', {'text': 'second'}, binding);
    final third = queue.enqueue('session.text', {'text': 'third'}, binding);
    await expectLater(queue.enqueue('session.text', {'text': 'overflow'}, binding), throwsStateError);
    gate.complete();
    await Future.wait([first, second, third, queue.idle]);
  });

  test('keeps one pending move independently for each pointer', () async {
    final firstDispatch = Completer<void>();
    final calls = <Json>[];
    final queue = RemoteInputQueue(
      admits: (_, _, _) => true,
      dispatch: (_, params, _) async {
        calls.add({...params});
        if (calls.length == 1) await firstDispatch.future;
      },
    );

    final down = queue.enqueue('session.touch', {
      'action': 'down',
      'pointerId': 1,
      'x': 10,
    }, binding);
    await Future<void>.delayed(Duration.zero);
    final first = queue.enqueue('session.touch', {
      'action': 'move',
      'pointerId': 1,
      'x': 11,
    }, binding);
    final second = queue.enqueue('session.touch', {
      'action': 'move',
      'pointerId': 2,
      'x': 21,
    }, binding);
    final latestFirst = queue.enqueue('session.touch', {
      'action': 'move',
      'pointerId': 1,
      'x': 12,
    }, binding);

    firstDispatch.complete();
    await queue.idle;
    await Future.wait([down, first, second, latestFirst]);

    expect(calls.map((call) => (call['pointerId'], call['x'])), [
      (1, 10),
      (2, 21),
      (1, 12),
    ]);
  });

  test('does not coalesce edge or non-touch commands', () async {
    final calls = <(String, Json)>[];
    final queue = RemoteInputQueue(
      admits: (_, _, _) => true,
      dispatch: (command, params, _) async {
        calls.add((command, {...params}));
      },
    );

    await Future.wait([
      queue.enqueue('session.touch', {
        'action': 'down',
        'pointerId': 1,
      }, binding),
      queue.enqueue('session.touch', {
        'action': 'down',
        'pointerId': 2,
      }, binding),
      queue.enqueue('session.key', {'keyCode': 4, 'action': 'down'}, binding),
      queue.enqueue('session.key', {'keyCode': 4, 'action': 'up'}, binding),
    ]);

    expect(calls.map((call) => call.$1), [
      'session.touch',
      'session.touch',
      'session.key',
      'session.key',
    ]);
    expect(calls.skip(2).map((call) => call.$2['action']), ['down', 'up']);
  });

  test('does not merge a new move across its pointer edge', () async {
    final firstDispatch = Completer<void>();
    final calls = <Json>[];
    final queue = RemoteInputQueue(
      admits: (_, _, _) => true,
      dispatch: (_, params, _) async {
        calls.add({...params});
        if (calls.length == 1) await firstDispatch.future;
      },
    );

    final down = queue.enqueue('session.touch', {
      'action': 'down',
      'pointerId': 1,
      'x': 10,
    }, binding);
    await Future<void>.delayed(Duration.zero);
    final beforeEdge = queue.enqueue('session.touch', {
      'action': 'move',
      'pointerId': 1,
      'x': 11,
    }, binding);
    final up = queue.enqueue('session.touch', {
      'action': 'up',
      'pointerId': 1,
      'x': 11,
    }, binding);
    final afterEdge = queue.enqueue('session.touch', {
      'action': 'move',
      'pointerId': 1,
      'x': 12,
    }, binding);

    firstDispatch.complete();
    await queue.idle;
    await Future.wait([down, beforeEdge, up, afterEdge]);

    expect(calls.map((call) => (call['action'], call['x'])), [
      ('down', 10),
      ('move', 11),
      ('up', 11),
      ('move', 12),
    ]);
  });

  test(
    'drops commands rejected by the captured presentation binding',
    () async {
      final calls = <Json>[];
      final queue = RemoteInputQueue(
        admits: (_, params, _) => params['action'] != 'move',
        dispatch: (_, params, _) async => calls.add({...params}),
      );

      await queue.enqueue('session.touch', {
        'action': 'move',
        'pointerId': 1,
        'x': 20,
      }, binding);
      await queue.enqueue('session.touch', {
        'action': 'cancel',
        'pointerId': 1,
        'x': 20,
      }, binding);
      await queue.idle;

      expect(calls.map((call) => call['action']), ['cancel']);
    },
  );
}
