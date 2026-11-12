import 'package:scrcpy_connect/core/control/models/video_quality.dart';

export 'package:scrcpy_connect/core/control/models/video_quality.dart';
export 'package:scrcpy_connect/core/settings/models/preferences.dart'
    show VideoCodec;

abstract interface class VideoQualityControl {
  Future<VideoQualityOptions> readVideoQualityOptions(String deviceId);
  Future<VideoQualityApplication> changeVideoQuality(
    String deviceId,
    VideoQualityPatch patch,
  );
}
