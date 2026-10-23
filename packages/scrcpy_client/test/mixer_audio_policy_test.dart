import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

void main() {
  test('stale release cannot revoke a new mixed output lease', () async {
    final policy = MixerAudioPolicy();
    final first = await policy.request('audio.platform.focus.acquire', {
      'ownerId': 'one',
    });
    expect(first['systemFocusVerified'], false);
    await policy.request('audio.platform.focus.release', {
      'ownerId': 'one',
      'epoch': first['epoch'],
    });
    final second = await policy.request('audio.platform.focus.acquire', {
      'ownerId': 'one',
    });
    expect(second['epoch'], greaterThan(first['epoch'] as int));
    expect(
      (await policy.request('audio.platform.focus.release', {
        'ownerId': 'one',
        'epoch': first['epoch'],
      }))['released'],
      false,
    );
    expect(
      await policy.request('audio.platform.focus.acquire', {'ownerId': 'one'}),
      second,
    );
  });

  test('unsupported background playback never fabricates readiness', () async {
    final policy = MixerAudioPolicy(backgroundPlaybackSupported: false);
    expect(
      (await policy.request('audio.platform.background', {
        'ownerId': 'one',
        'enabled': true,
      }))['ready'],
      false,
    );
  });
}
