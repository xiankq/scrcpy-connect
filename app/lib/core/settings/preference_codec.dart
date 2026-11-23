import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preference_schema.dart';

/// preferences.json、迁移文件及状态快照的格式适配，不参与偏好编排。
abstract final class PreferenceCodec {
  static Preferences decode(Map<String, Object?> values) {
    final patch = _decodeChanges(values);
    return Preferences().apply(patch);
  }

  static PreferenceChanges decodeChanges(Object? values) =>
      _decodeChanges(PreferenceSchema(defaults: const {}).validate(values));

  static PreferenceChanges _decodeChanges(Map<String, Object?> values) =>
      PreferenceChanges(
        appearance: values['appearance'] == null
            ? null
            : Appearance.values.byName(values['appearance']! as String),
        backgroundKeepAlive: values['backgroundKeepAlive'] as bool?,
        notificationAlerts: values['notificationAlerts'] as bool?,
        callAlerts: values['callAlerts'] as bool?,
        adbBurstMode: values['adbBurstMode'] as bool?,
        fileViewMode: values['fileViewMode'] == null
            ? null
            : FileViewMode.values.byName(values['fileViewMode']! as String),
        fileSortKey: values['fileSortKey'] == null
            ? null
            : FileSortKey.values.byName(values['fileSortKey']! as String),
        fileSortAscending: values['fileSortAscending'] as bool?,
        quality: decodeQuality(values),
        deviceSettings: (values['deviceSettings'] as Map?)?.map(
          (key, value) => MapEntry(
            key as String,
            decodeDevice(Map<String, Object?>.from(value as Map)),
          ),
        ),
        deviceQuality: (values['deviceQuality'] as Map?)?.map(
          (key, value) => MapEntry(
            key as String,
            decodeQuality(Map<String, Object?>.from(value as Map)),
          ),
        ),
        appOpenModes: (values['appOpenModes'] as Map?)?.map(
          (key, value) => MapEntry(
            key as String,
            (value as Map).map(
              (package, mode) => MapEntry(
                package as String,
                AppOpenMode.values.byName(mode as String),
              ),
            ),
          ),
        ),
      );

  static DevicePreferences decodeDevice(Map<String, Object?> values) =>
      DevicePreferences(
        clipboardSync: values['clipboardSync'] as bool?,
        showNavigationBar: values['showNavigationBar'] as bool?,
        wakeOnConnect: values['wakeOnConnect'] as bool?,
        lockOnClose: values['lockOnClose'] as bool?,
        stayAwake: values['stayAwake'] as bool?,
        remoteAspectRatio: values['remoteAspectRatio'] == null
            ? null
            : ScreenAspectRatio.values.singleWhere(
                (ratio) => ratio.wire == values['remoteAspectRatio'],
              ),
        remoteCustomRatio: values['remoteCustomRatio'] as String?,
        favoriteApps: (values['favoriteApps'] as List?)
            ?.map<FavoriteDeviceApp>((entry) {
              final app = entry as Map;
              return (
                packageName: app['packageName'] as String,
                name: app['name'] as String,
                userId: app['userId'] as int?,
              );
            })
            .toList(growable: false),
      );

  static VideoQualityPreferences decodeQuality(Map<String, Object?> values) =>
      VideoQualityPreferences(
        qualityPreset: values.containsKey('qualityPreset')
            ? (name: values['qualityPreset'] as String?)
            : null,
        maxSize: values['maxSize'] as int?,
        maxFps: values['maxFps'] as int?,
        videoBitRate: values['videoBitRate'] as int?,
        videoCodec: values['videoCodec'] == null
            ? null
            : VideoCodec.values.byName(values['videoCodec']! as String),
        videoEncoder: values.containsKey('videoEncoder')
            ? (name: values['videoEncoder'] as String?)
            : null,
      );

  static Map<String, Object?> encode(Preferences values) => encodeChanges(
    PreferenceChanges(
      appearance: values.appearance,
      backgroundKeepAlive: values.backgroundKeepAlive,
      notificationAlerts: values.notificationAlerts,
      callAlerts: values.callAlerts,
      adbBurstMode: values.adbBurstMode,
      fileViewMode: values.fileViewMode,
      fileSortKey: values.fileSortKey,
      fileSortAscending: values.fileSortAscending,
      quality: values.quality,
      deviceSettings: values.deviceSettings,
      appOpenModes: values.appOpenModes,
      deviceQuality: values.deviceQuality,
    ),
  );

  static Map<String, Object?> encodeChanges(PreferenceChanges values) => {
    if (values.appearance case final value?) 'appearance': value.name,
    'backgroundKeepAlive': ?values.backgroundKeepAlive,
    'notificationAlerts': ?values.notificationAlerts,
    'callAlerts': ?values.callAlerts,
    'adbBurstMode': ?values.adbBurstMode,
    if (values.fileViewMode case final value?) 'fileViewMode': value.name,
    if (values.fileSortKey case final value?) 'fileSortKey': value.name,
    'fileSortAscending': ?values.fileSortAscending,
    ...encodeQuality(values.quality),
    if (values.deviceSettings case final devices?)
      'deviceSettings': {
        for (final entry in devices.entries)
          entry.key: encodeDevice(entry.value),
      },
    if (values.deviceQuality case final devices?)
      'deviceQuality': {
        for (final entry in devices.entries)
          entry.key: encodeQuality(entry.value),
      },
    if (values.appOpenModes case final devices?)
      'appOpenModes': {
        for (final entry in devices.entries)
          entry.key: {
            for (final mode in entry.value.entries) mode.key: mode.value.name,
          },
      },
  };

  static Map<String, Object?> encodeDevice(DevicePreferences values) => {
    'clipboardSync': ?values.clipboardSync,
    'showNavigationBar': ?values.showNavigationBar,
    'wakeOnConnect': ?values.wakeOnConnect,
    'lockOnClose': ?values.lockOnClose,
    'stayAwake': ?values.stayAwake,
    if (values.remoteAspectRatio case final value?)
      'remoteAspectRatio': value.wire,
    'remoteCustomRatio': ?values.remoteCustomRatio,
    if (values.favoriteApps case final apps?)
      'favoriteApps': [
        for (final app in apps)
          {
            'packageName': app.packageName,
            'name': app.name,
            'userId': ?app.userId,
          },
      ],
  };

  static Map<String, Object?> encodeQuality(VideoQualityPreferences values) => {
    if (values.qualityPreset case final value?) 'qualityPreset': value.name,
    'maxSize': ?values.maxSize,
    'maxFps': ?values.maxFps,
    'videoBitRate': ?values.videoBitRate,
    if (values.videoCodec case final value?) 'videoCodec': value.name,
    if (values.videoEncoder case final value?) 'videoEncoder': value.name,
  };
}
