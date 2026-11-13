/// 本机播放器已经观察到的事实；原生字段只在接入时解码。
sealed class MediaPlayerEvent {
  const MediaPlayerEvent();

  static MediaPlayerEvent? decode(Map<String, dynamic> value) {
    if (value['kind'] == 'failed') {
      return MediaPlayerFailed(
        code: value['code'] as String?,
        stage: value['stage'] as String?,
        reason: value['reason'] as String?,
        nativeError: value['nativeError'] as int?,
      );
    }
    return switch (value['category']) {
      'decoder.audio' || 'decoder.video' => MediaDecoderSelected(
        audio: value['category'] == 'decoder.audio',
        decoderName: value['decoderName'] as String?,
        hardwareAccelerated: value['hardwareAccelerated'] as bool?,
        hardwareVerification: value['hardwareVerification'] as String?,
        backendHardwareFrames: value['backendHardwareFrames'] as bool?,
        runtimeSelectionVerified: value['runtimeSelectionVerified'] == true,
        detail: value['detail'] as String?,
        error: value['error'] as num?,
      ),
      'video.presentation' => VideoPlayerPresented(
        generation: value['generation'] as int,
        textureId: value['textureId'] as int,
        presentedSequence: value['presentedSequence'] as int?,
        presentedFrameCount: value['presentedFrameCount'] as int?,
        presentationPath: value['presentationPath'] as String?,
        platformTexturePrepared: value['platformTexturePrepared'] == true,
        presentedToWidget: value['presentedToWidget'] == true,
      ),
      'video.dimensions' when value['kind'] == 'metadata' =>
        VideoPlayerDimensions(
          generation: value['generation'] as int,
          textureId: value['textureId'] as int,
          width: value['width'] as int,
          height: value['height'] as int,
          frameCount: value['frameCount'] as int,
        ),
      'video.prepare' ||
      'video.texture' when value['kind'] == 'diagnostic' => VideoPlayerTiming(
        stage: value['category'] == 'video.prepare' ? .prepare : .texture,
        elapsedMs: value['elapsedMs'] as int?,
      ),
      _ => null,
    };
  }

  bool get diagnostic => switch (this) {
    MediaDecoderSelected() ||
    VideoPlayerPresented() ||
    VideoPlayerTiming() => true,
    _ => false,
  };

  /// 仅供诊断输出序列化，不参与播放编排。
  Map<String, dynamic> toDiagnosticFields();
}

final class MediaPlayerFailed extends MediaPlayerEvent {
  const MediaPlayerFailed({
    this.code,
    this.stage,
    this.reason,
    this.nativeError,
  });
  final String? code, stage, reason;
  final int? nativeError;
  @override
  Map<String, dynamic> toDiagnosticFields() => {
    'kind': 'failed',
    'code': ?code,
    'stage': ?stage,
    'reason': ?reason,
    'nativeError': ?nativeError,
  };
}

final class MediaDecoderSelected extends MediaPlayerEvent {
  const MediaDecoderSelected({
    required this.audio,
    this.decoderName,
    this.hardwareAccelerated,
    this.hardwareVerification,
    this.backendHardwareFrames,
    this.runtimeSelectionVerified = false,
    this.detail,
    this.error,
  });
  final bool audio, runtimeSelectionVerified;
  final String? decoderName, hardwareVerification, detail;
  final bool? hardwareAccelerated, backendHardwareFrames;
  final num? error;
  @override
  Map<String, dynamic> toDiagnosticFields() => {
    'kind': 'diagnostic',
    'category': audio ? 'decoder.audio' : 'decoder.video',
    'decoderName': ?decoderName,
    'hardwareAccelerated': ?hardwareAccelerated,
    'hardwareVerification': ?hardwareVerification,
    'backendHardwareFrames': ?backendHardwareFrames,
    'runtimeSelectionVerified': runtimeSelectionVerified,
    'detail': ?detail,
    'error': ?error,
  };
}

final class VideoPlayerPresented extends MediaPlayerEvent {
  const VideoPlayerPresented({
    required this.generation,
    required this.textureId,
    this.presentedSequence,
    this.presentedFrameCount,
    this.presentationPath,
    this.platformTexturePrepared = false,
    this.presentedToWidget = false,
  });
  final int generation, textureId;
  final int? presentedSequence, presentedFrameCount;
  final String? presentationPath;
  final bool platformTexturePrepared, presentedToWidget;
  @override
  Map<String, dynamic> toDiagnosticFields() => {
    'kind': 'diagnostic',
    'category': 'video.presentation',
    'generation': generation,
    'textureId': textureId,
    'presentedSequence': ?presentedSequence,
    'presentedFrameCount': ?presentedFrameCount,
    'presentationPath': ?presentationPath,
    'platformTexturePrepared': platformTexturePrepared,
    'presentedToWidget': presentedToWidget,
  };
}

final class VideoPlayerDimensions extends MediaPlayerEvent {
  const VideoPlayerDimensions({
    required this.generation,
    required this.textureId,
    required this.width,
    required this.height,
    required this.frameCount,
  });
  final int generation, textureId, width, height, frameCount;
  @override
  Map<String, dynamic> toDiagnosticFields() => {
    'kind': 'metadata',
    'category': 'video.dimensions',
    'generation': generation,
    'textureId': textureId,
    'width': width,
    'height': height,
    'frameCount': frameCount,
  };
}

enum VideoPlayerTimingStage { prepare, texture }

final class VideoPlayerTiming extends MediaPlayerEvent {
  const VideoPlayerTiming({required this.stage, this.elapsedMs});
  final VideoPlayerTimingStage stage;
  final int? elapsedMs;
  String get diagnosticCategory => switch (stage) {
    .prepare => 'video.prepare',
    .texture => 'video.texture',
  };
  @override
  Map<String, dynamic> toDiagnosticFields() => {
    'kind': 'diagnostic',
    'category': diagnosticCategory,
    'elapsedMs': ?elapsedMs,
  };
}
