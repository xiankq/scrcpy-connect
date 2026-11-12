import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preference_codec.dart';

/// 与应用默认值共用的远程捕获基础设置。
Map<String, Object?> get defaultVideoQuality =>
    PreferenceCodec.encodeQuality(VideoQualityPreferences.defaults);

/// 原生执行器收到具体媒体参数前先解析产品选项；原生探测与会话准入仍保留独立核验。
class VideoQualityPolicy {
  static void validateSettings(Map<String, dynamic> changes) {
    void validate(Map<Object?, Object?> values) {
      if (values.containsKey('qualityPreset') &&
          !presets.containsKey(values['qualityPreset'])) {
        throw const RequestFailure('invalid_argument', '画质预设无效。');
      }
    }

    validate(changes);
    final devices = changes['deviceQuality'];
    if (devices is Map) {
      for (final quality in devices.values.whereType<Map<Object?, Object?>>()) {
        validate(quality);
      }
    }
  }

  static VideoQuality resolveQuality(
    Preferences settings,
    String? deviceId, [
    VideoQualityPatch patch = const VideoQualityPatch(),
  ]) {
    final inherited = VideoQualityPreferences.defaults
        .merge(settings.quality)
        .merge(
          settings.deviceQuality[deviceId] ?? const VideoQualityPreferences(),
        );
    final selected = switch (patch.preset) {
      .smooth => presets['smooth'],
      .balanced => presets['balanced'],
      .clear => presets['clear'],
      null => null,
    };
    final quality = VideoQuality(
      preset:
          patch.preset ??
          VideoQualityPreset.values
              .where((item) => item.name == inherited.qualityPreset?.name)
              .firstOrNull,
      maxSize: patch.maxSize ?? selected?.maxSize ?? inherited.maxSize!,
      maxFps: patch.maxFps ?? selected?.maxFps ?? inherited.maxFps!,
      bitRate:
          patch.bitRate ?? selected?.videoBitRate ?? inherited.videoBitRate!,
      codec: patch.codec ?? inherited.videoCodec!,
      encoder: patch.encoder == null
          ? inherited.videoEncoder?.name
          : patch.encoder!.name,
    );
    if (quality.maxSize < 320 ||
        quality.maxSize > 4096 ||
        quality.maxFps < 1 ||
        quality.maxFps > 120 ||
        quality.bitRate < 500000 ||
        quality.bitRate > 50000000) {
      throw const RequestFailure('invalid_argument', '画质参数超出有效范围。');
    }
    final encoder = quality.encoder;
    if (encoder != null &&
        (encoder.isEmpty ||
            encoder.length > 256 ||
            !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(encoder))) {
      throw const RequestFailure('invalid_argument', '视频编码器名称无效。');
    }
    return quality;
  }

  static const presets = {
    'smooth': (maxSize: 720, maxFps: 30, videoBitRate: 2000000),
    'balanced': (maxSize: 1280, maxFps: 60, videoBitRate: 4000000),
    'clear': (maxSize: 1920, maxFps: 60, videoBitRate: 12000000),
  };

  /// 保持现有事件快照的字段；业务调用直接使用 VideoQuality。
  static Map<String, dynamic> current(VideoQuality quality) => {
    ...quality.toJson(),
    'preset': quality.preset?.name,
    'bitRate': quality.bitRate,
    'codec': quality.codec.name,
    'audio': false,
  };
}
