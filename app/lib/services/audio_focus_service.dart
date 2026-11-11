import 'package:scrcpy_connect/models/application_request.dart';

/// 为直接混音的宿主登记本机焦点租约，不将租约当作系统焦点证明。
/// 原生输出创建仍须确认实际系统音频设备。
class AudioFocusService {
  AudioFocusService({this.backgroundPlaybackSupported = true});

  final bool backgroundPlaybackSupported;
  int _nextEpoch = 0;
  final _leases = <String, int>{};

  Future<Map<String, dynamic>> request(
    String command,
    Map<String, dynamic> params,
  ) async {
    final owner = params['ownerId'];
    if (owner is! String || owner.isEmpty) {
      throw const RequestFailure('invalid_argument', '缺少声音输出所有者。');
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
        throw const RequestFailure('unsupported', '此主控不支持该声音平台操作。');
    }
  }
}
