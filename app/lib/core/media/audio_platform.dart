import 'package:scrcpy_connect/core/media/models/audio_background_state.dart';
import 'package:scrcpy_connect/core/media/models/audio_focus.dart';

export 'package:scrcpy_connect/core/media/models/audio_background_state.dart';
export 'package:scrcpy_connect/core/media/models/audio_focus.dart';
export 'package:scrcpy_connect/core/media/models/audio_platform_event.dart';

/// 系统焦点或本机混音租约；输出所有者始终携带原 owner 与申请代次释放。
abstract interface class AudioPlatform {
  Future<AudioFocusResult> acquireFocus(String ownerId);
  Future<bool> releaseFocus(String ownerId, int epoch);
  Future<AudioBackgroundState> setBackground(String ownerId, bool enabled);
}
