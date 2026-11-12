import 'remote_control.dart';

typedef VideoDisplaySize = ({int width, int height});

abstract interface class VideoDisplayControl {
  Future<void> resizeDisplay(ControlTarget target, VideoDisplaySize size);
}
