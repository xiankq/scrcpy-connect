import 'package:scrcpy_connect/core/control/models/video_display_size.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';

export 'package:scrcpy_connect/core/control/models/video_display_size.dart';

abstract interface class VideoDisplayControl {
  Future<void> resizeDisplay(ControlTarget target, VideoDisplaySize size);
}
