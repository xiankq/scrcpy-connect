import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/application_background_policy.dart';

void main() {
  test('entering the application requests connection background before audio with no device or page', () async {
    final calls = <String>[];
    final background = ApplicationBackgroundPolicy(
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
    final background = ApplicationBackgroundPolicy(
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
}
