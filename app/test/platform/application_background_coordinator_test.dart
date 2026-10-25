import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/platform/application_background_coordinator.dart';

void main() {
  test('entering the application requests connection background before audio with no device or page', () async {
    final calls = <String>[];
    final background = ApplicationBackgroundCoordinator(
      request: (command, params) async {
        calls.add(command);
        expect(params, {'enabled': true, 'automatic': true});
        return {'running': true};
      },
      audioPolicy: (_) async {
        calls.add('audio.policy');
      },
      emit: (_) {},
    );
    await background.apply(true, automatic: true);
    expect(calls, ['background.request', 'audio.policy']);
  });

  test('platform refusal reports status while preserving application startup and preference', () async {
    final events = <Map<String, dynamic>>[];
    final audio = <bool>[];
    final background = ApplicationBackgroundCoordinator(
      request: (_, _) async => throw StateError('foreground denied'),
      audioPolicy: (enabled) async {
        audio.add(enabled);
      },
      emit: events.add,
    );
    await background.apply(true, automatic: true);
    expect(audio, [true]);
    expect(events.single['type'], 'background.failed');
    expect(
      (events.single['data'] as Map)['reason'],
      contains('foreground denied'),
    );
  });

  test('a native stopped receipt remains stopped and startup does not request retry or media', () async {
    final calls = <String>[];
    final events = <Map<String, dynamic>>[];
    final background = ApplicationBackgroundCoordinator(
      request: (command, params) async {
        calls.add(command);
        expect(params['automatic'], true);
        return {'running': false, 'stopped': true};
      },
      audioPolicy: (_) async {},
      emit: events.add,
    );
    final status = await background.apply(true, automatic: true);
    expect(status?['stopped'], true);
    expect(calls, ['background.request']);
    expect(events.single['data'], {'running': false, 'stopped': true});
  });

  test('an unsupported host applies its audio policy without claiming native background support', () async {
    final audio = <bool>[];
    final events = <Map<String, dynamic>>[];
    final background = ApplicationBackgroundCoordinator(
      request: null,
      audioPolicy: (enabled) async {
        audio.add(enabled);
      },
      emit: events.add,
    );
    await background.apply(true, automatic: true);
    expect(audio, [true]);
    expect(events, isEmpty);
  });
}
