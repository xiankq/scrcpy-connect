import 'package:freezed_annotation/freezed_annotation.dart';

part 'video_screenshot.freezed.dart';

/// 当前渲染代次实际取回的 PNG；文件仍是应用暂存，保存与分享由文档能力执行。
@freezed
abstract class VideoScreenshot with _$VideoScreenshot {
  const factory VideoScreenshot({
    required String sessionId,
    required String deviceId,
    required int generation,
    required String localPath,
    required int width,
    required int height,
    required bool scaled,
    required bool paused,
  }) = _VideoScreenshot;
}

abstract interface class VideoScreenshots {
  Future<VideoScreenshot> captureScreenshot(String sessionId);
}
