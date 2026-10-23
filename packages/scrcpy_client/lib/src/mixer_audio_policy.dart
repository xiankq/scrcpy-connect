import 'package:device_protocol/device_protocol.dart';

/// Local ownership for hosts that mix application audio without Android focus.
/// Native output creation still has to confirm the actual OS audio device.
class MixerAudioPolicy {
  MixerAudioPolicy({this.backgroundPlaybackSupported = true});

  final bool backgroundPlaybackSupported;
  int _nextEpoch = 0;
  final _leases = <String, int>{};

  Future<Map<String, dynamic>> request(
    String command,
    Map<String, dynamic> params,
  ) async {
    final owner = params['ownerId'];
    if (owner is! String || owner.isEmpty) {
      throw const InteropException('invalid_argument', '缺少声音输出所有者。');
    }
    switch (command) {
      case 'audio.platform.focus.acquire':
        final epoch = _leases.putIfAbsent(owner, () => ++_nextEpoch);
        return {
          'granted': true,
          'epoch': epoch,
          'scope': 'applicationMixer',
          'systemFocusVerified': false,
        };
      case 'audio.platform.focus.release':
        final matches = _leases[owner] == params['epoch'];
        if (matches) _leases.remove(owner);
        return {'released': matches};
      case 'audio.platform.background':
        return {
          'supported': backgroundPlaybackSupported,
          'ready': params['enabled'] != true || backgroundPlaybackSupported,
          'systemServiceRequired': false,
        };
      default:
        throw const InteropException('unsupported', '此主控不支持该声音平台操作。');
    }
  }
}
