import 'package:scrcpy_connect/core/media/models/video_screenshot.dart';

export 'package:scrcpy_connect/core/media/models/video_screenshot.dart';

abstract interface class VideoScreenshots {
  Future<VideoScreenshot> captureScreenshot(String sessionId);
}
