import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart'
    show VideoCodec;

part 'video_capture.freezed.dart';

/// 控制所有者交付的精确捕获；播放器借用这个描述附着一次性原生源。
@freezed
abstract class VideoCapture with _$VideoCapture {
  const factory VideoCapture({
    required String sessionId,
    required String deviceId,
    required String captureRef,
    required int captureGeneration,
    required int generation,
    required String videoSourceId,
    required VideoCodec codec,
    required int width,
    required int height,
  }) = _VideoCapture;
}
