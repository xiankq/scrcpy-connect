import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/audio_platform.dart';

/// 为直接混音的宿主登记本机焦点租约，不将租约当作系统焦点证明。
/// 原生输出创建仍须确认实际系统音频设备。
class AudioFocusService implements AudioPlatform {
  AudioFocusService({this.backgroundPlaybackSupported = true});

  final bool backgroundPlaybackSupported;
  int _nextEpoch = 0;
  final _leases = <String, int>{};

  void _checkOwner(String owner) {
    if (owner.isEmpty) {
      throw const RequestFailure('invalid_argument', '缺少声音输出所有者。');
    }
  }

  @override
  Future<AudioFocusResult> acquireFocus(String ownerId) async {
    _checkOwner(ownerId);
    final epoch = _leases.putIfAbsent(ownerId, () => ++_nextEpoch);
    return AudioFocusResult(granted: true, epoch: epoch);
  }

  @override
  Future<bool> releaseFocus(String ownerId, int epoch) async {
    _checkOwner(ownerId);
    final matches = _leases[ownerId] == epoch;
    if (matches) _leases.remove(ownerId);
    return matches;
  }

  @override
  Future<AudioBackgroundState> setBackground(
    String ownerId,
    bool enabled,
  ) async {
    _checkOwner(ownerId);
    return AudioBackgroundState(
      supported: backgroundPlaybackSupported,
      ready: !enabled || backgroundPlaybackSupported,
    );
  }
}
