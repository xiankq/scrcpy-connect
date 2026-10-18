import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/media_intent.dart';

void main() {
  test('closing a device page cancels its unbound audio start before player attachment', () {
    final intents = MediaIntents();
    final old = intents.begin('A', audio: true);
    final other = intents.begin('B', audio: true);
    intents.stopAudioDevice('A');
    expect(old.cancelled, isTrue);
    expect(other.cancelled, isFalse);
    final reopened = intents.begin('A', audio: true);
    old.bind('late-old-source');
    expect(old.cancelled, isTrue);
    expect(reopened.cancelled, isFalse);
  });
  test('a stop before startup returns its ID still prevents native attach and retry', () {
    final intents = MediaIntents();
    final pending = intents.begin('device-A', audio: false);
    intents.stop('first-session', audio: false);
    expect(pending.cancelled, isFalse);
    pending.bind('first-session');
    expect(pending.cancelled, isTrue);
    pending.bind('retry-session');
    expect(pending.cancelled, isTrue);
  });
  test('old IDs cannot cancel another device or its replacement source', () {
    final intents = MediaIntents();
    final audio = intents.begin('A', audio: true)..bind('new-source');
    final video = intents.begin('A', audio: false)..bind('video');
    final other = intents.begin('B', audio: true)..bind('other-source');
    intents.stop('old-source', audio: true);
    expect(audio.cancelled, isFalse);
    intents.stopAudioDevice('A');
    expect(audio.cancelled, isTrue);
    expect(video.cancelled, isFalse);
    expect(other.cancelled, isFalse);
    intents.stopDevice('A');
    expect(video.cancelled, isTrue);
    expect(other.cancelled, isFalse);
  });
  test('dispose cancellation covers late ID binding and completion drains in-flight ownership', () async {
    final intents = MediaIntents();
    final old = intents.begin('A', audio: false);
    final pendingDone = old.done;
    intents.cancelAll();
    old.bind('late-session');
    expect(old.cancelled, isTrue);
    intents.finish(old);
    await pendingDone;
    expect(intents.active, isEmpty);
    // Finishing again is harmless during competing native failure cleanup.
    intents.finish(old);
  });
}
