import 'package:freezed_annotation/freezed_annotation.dart';

part 'preferences.freezed.dart';

enum Appearance { light, dark, system }

enum GlassEffects { automatic, premium, standard, off }

enum FileViewMode { grid, list }

enum FileSortKey { name, size, modified, type }

enum AppOpenMode { phone, window }

enum VideoCodec { h264, h265, av1, vp8, vp9 }

enum ScreenAspectRatio {
  original('original'),
  automatic('auto'),
  portrait('9:16'),
  photo('3:4'),
  square('1:1'),
  landscape('16:9'),
  custom('custom');

  const ScreenAspectRatio(this.wire);
  final String wire;
}

/// 未提供的字段继续继承全局画质。可空值的记录区分“继承”与“明确自动”。
@freezed
class VideoQualityPreferences with _$VideoQualityPreferences {
  const VideoQualityPreferences({
    this.qualityPreset,
    this.maxSize,
    this.maxFps,
    this.videoBitRate,
    this.videoCodec,
    this.videoEncoder,
  });

  static const defaults = VideoQualityPreferences(
    qualityPreset: (name: 'balanced'),
    maxSize: 720,
    maxFps: 60,
    videoBitRate: 4000000,
    videoCodec: VideoCodec.h264,
    videoEncoder: (name: null),
  );

  final ({String? name})? qualityPreset;
  final int? maxSize;
  final int? maxFps;
  final int? videoBitRate;
  final VideoCodec? videoCodec;
  final ({String? name})? videoEncoder;

  VideoQualityPreferences merge(VideoQualityPreferences patch) => copyWith(
    qualityPreset: patch.qualityPreset ?? qualityPreset,
    maxSize: patch.maxSize ?? maxSize,
    maxFps: patch.maxFps ?? maxFps,
    videoBitRate: patch.videoBitRate ?? videoBitRate,
    videoCodec: patch.videoCodec ?? videoCodec,
    videoEncoder: patch.videoEncoder ?? videoEncoder,
  );
}

typedef FavoriteDeviceApp = ({String packageName, String name, int? userId});

@freezed
class DevicePreferences with _$DevicePreferences {
  const DevicePreferences({
    this.clipboardSync,
    this.showNavigationBar,
    this.wakeOnConnect,
    this.lockOnClose,
    this.stayAwake,
    this.remoteAspectRatio,
    this.remoteCustomRatio,
    this.favoriteApps,
  });

  final bool? clipboardSync;
  final bool? showNavigationBar;
  final bool? wakeOnConnect;
  final bool? lockOnClose;
  final bool? stayAwake;
  final ScreenAspectRatio? remoteAspectRatio;
  final String? remoteCustomRatio;
  final List<FavoriteDeviceApp>? favoriteApps;

  DevicePreferences merge(DevicePreferences patch) => copyWith(
    clipboardSync: patch.clipboardSync ?? clipboardSync,
    showNavigationBar: patch.showNavigationBar ?? showNavigationBar,
    wakeOnConnect: patch.wakeOnConnect ?? wakeOnConnect,
    lockOnClose: patch.lockOnClose ?? lockOnClose,
    stayAwake: patch.stayAwake ?? stayAwake,
    remoteAspectRatio: patch.remoteAspectRatio ?? remoteAspectRatio,
    remoteCustomRatio: patch.remoteCustomRatio ?? remoteCustomRatio,
    favoriteApps: patch.favoriteApps ?? favoriteApps,
  );
}

@freezed
class Preferences with _$Preferences {
  Preferences({
    this.appearance = Appearance.system,
    this.glassEffects = GlassEffects.automatic,
    this.backgroundKeepAlive = true,
    this.notificationAlerts = false,
    this.callAlerts = false,
    this.adbBurstMode = true,
    this.fileViewMode = FileViewMode.grid,
    this.fileSortKey = FileSortKey.name,
    this.fileSortAscending = true,
    this.quality = VideoQualityPreferences.defaults,
    Map<String, DevicePreferences> deviceSettings = const {},
    Map<String, Map<String, AppOpenMode>> appOpenModes = const {},
    Map<String, VideoQualityPreferences> deviceQuality = const {},
  }) : deviceSettings = Map.unmodifiable(deviceSettings),
       appOpenModes = Map.unmodifiable({
         for (final entry in appOpenModes.entries)
           entry.key: Map<String, AppOpenMode>.unmodifiable(entry.value),
       }),
       deviceQuality = Map.unmodifiable(deviceQuality);

  final Appearance appearance;
  final GlassEffects glassEffects;
  final bool backgroundKeepAlive;
  final bool notificationAlerts;
  final bool callAlerts;
  final bool adbBurstMode;
  final FileViewMode fileViewMode;
  final FileSortKey fileSortKey;
  final bool fileSortAscending;
  final VideoQualityPreferences quality;
  final Map<String, DevicePreferences> deviceSettings;
  final Map<String, Map<String, AppOpenMode>> appOpenModes;
  final Map<String, VideoQualityPreferences> deviceQuality;

  Preferences apply(PreferenceChanges patch) => copyWith(
    appearance: patch.appearance ?? appearance,
    glassEffects: patch.glassEffects ?? glassEffects,
    backgroundKeepAlive: patch.backgroundKeepAlive ?? backgroundKeepAlive,
    notificationAlerts: patch.notificationAlerts ?? notificationAlerts,
    callAlerts: patch.callAlerts ?? callAlerts,
    adbBurstMode: patch.adbBurstMode ?? adbBurstMode,
    fileViewMode: patch.fileViewMode ?? fileViewMode,
    fileSortKey: patch.fileSortKey ?? fileSortKey,
    fileSortAscending: patch.fileSortAscending ?? fileSortAscending,
    quality: quality.merge(patch.quality),
    deviceSettings: patch.deviceSettings ?? deviceSettings,
    appOpenModes: patch.appOpenModes ?? appOpenModes,
    deviceQuality: patch.deviceQuality ?? deviceQuality,
  );
}

/// 集合字段替换该集合；单设备合并由偏好状态所有者使用最新值构造。
@freezed
class PreferenceChanges with _$PreferenceChanges {
  PreferenceChanges({
    this.appearance,
    this.glassEffects,
    this.backgroundKeepAlive,
    this.notificationAlerts,
    this.callAlerts,
    this.adbBurstMode,
    this.fileViewMode,
    this.fileSortKey,
    this.fileSortAscending,
    this.quality = const VideoQualityPreferences(),
    Map<String, DevicePreferences>? deviceSettings,
    Map<String, Map<String, AppOpenMode>>? appOpenModes,
    Map<String, VideoQualityPreferences>? deviceQuality,
  }) : deviceSettings = deviceSettings == null
           ? null
           : Map.unmodifiable(deviceSettings),
       appOpenModes = appOpenModes == null
           ? null
           : Map.unmodifiable({
               for (final entry in appOpenModes.entries)
                 entry.key: Map<String, AppOpenMode>.unmodifiable(entry.value),
             }),
       deviceQuality = deviceQuality == null
           ? null
           : Map.unmodifiable(deviceQuality);

  final Appearance? appearance;
  final GlassEffects? glassEffects;
  final bool? backgroundKeepAlive;
  final bool? notificationAlerts;
  final bool? callAlerts;
  final bool? adbBurstMode;
  final FileViewMode? fileViewMode;
  final FileSortKey? fileSortKey;
  final bool? fileSortAscending;
  final VideoQualityPreferences quality;
  final Map<String, DevicePreferences>? deviceSettings;
  final Map<String, Map<String, AppOpenMode>>? appOpenModes;
  final Map<String, VideoQualityPreferences>? deviceQuality;
}
