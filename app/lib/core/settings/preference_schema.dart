import 'dart:convert';

import 'package:scrcpy_connect/core/settings/models/preferences.dart';

final _defaultPreferences = Preferences();
final preferenceDefaults = Map<String, Object?>.unmodifiable({
  'appearance': _defaultPreferences.appearance.name,
  'backgroundKeepAlive': _defaultPreferences.backgroundKeepAlive,
  'notificationAlerts': _defaultPreferences.notificationAlerts,
  'callAlerts': _defaultPreferences.callAlerts,
  'adbBurstMode': _defaultPreferences.adbBurstMode,
  'fileViewMode': _defaultPreferences.fileViewMode.name,
  'fileSortKey': _defaultPreferences.fileSortKey.name,
  'fileSortAscending': _defaultPreferences.fileSortAscending,
  'deviceSettings': <String, Object?>{},
  'appOpenModes': <String, Object?>{},
  'deviceQuality': <String, Object?>{},
});

const qualityKeys = {
  'qualityPreset',
  'maxSize',
  'maxFps',
  'videoBitRate',
  'videoCodec',
  'videoEncoder',
};
const _retired = {
  'backgroundConnection',
  'backgroundAudio',
  'reduceTransparency',
  'reduceMotion',
  'audioMode',
  'audioDevices',
  'clipboardEnabled',
  'clipboardTarget',
  'clipboardSync',
  'clipboardMode',
  'clipboardDevice',
};

class PreferenceFailure implements Exception {
  const PreferenceFailure(this.code, this.message, [this.details = const {}]);
  final String code, message;
  final Map<String, Object?> details;
  @override
  String toString() => 'PreferenceFailure($code): $message';
}

/// 默认值由应用组合；这里只负责产品偏好的校验、迁移与合并。
final class PreferenceSchema {
  PreferenceSchema({required Map<String, Object?> defaults}) {
    _defaults = _copy({...preferenceDefaults, ...defaults});
    validate(_defaults);
  }
  late final Map<String, Object?> _defaults;
  Map<String, Object?> get defaults => _copy(_defaults);

  Map<String, Object?> validate(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const PreferenceFailure('invalid_argument', '设置必须是对象。');
    }
    final values = Map<String, Object?>.from(value);
    for (final entry in values.entries) {
      final key = entry.key, value = entry.value;
      final valid = switch (key) {
        'appearance' => const ['light', 'dark', 'system'].contains(value),
        'backgroundKeepAlive' ||
        'notificationAlerts' ||
        'callAlerts' ||
        'adbBurstMode' ||
        'fileSortAscending' => value is bool,
        'fileViewMode' => const ['grid', 'list'].contains(value),
        'fileSortKey' => const [
          'name',
          'size',
          'modified',
          'type',
        ].contains(value),
        'deviceSettings' => _devices(value, _deviceSetting),
        'appOpenModes' => _devices(value, _appModes),
        'deviceQuality' => _devices(value, _quality),
        _ => qualityKeys.contains(key) && _qualityValue(key, value),
      };
      if (!valid) {
        throw PreferenceFailure('invalid_argument', '设置值无效：$key', {'key': key});
      }
    }
    return _copy(values);
  }

  Map<String, Object?> merge(Map<String, Object?> current, Object? changes) => {
    ..._copy(current),
    ...validate(changes),
  };

  Map<String, Object?> migrateLegacy(Object? value, {required int version}) {
    if (version != 1 && version != 2 && version != 3) {
      throw const PreferenceFailure('storage_version', '设备记录版本较新，请更新应用。');
    }
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const PreferenceFailure('preferences_corrupt', '旧设置记录损坏。');
    }
    final migrated = _copy(Map<String, Object?>.from(value));
    for (final key in _retired) {
      migrated.remove(key);
    }
    bool formerBalanced(Map<Object?, Object?> quality) =>
        quality['qualityPreset'] == 'balanced' &&
        quality['maxSize'] == 1280 &&
        quality['maxFps'] == 60 &&
        quality['videoBitRate'] == 8000000;
    if (version == 1) {
      if (migrated['adbBurstMode'] == false && formerBalanced(migrated)) {
        migrated['adbBurstMode'] = true;
      }
      if (formerBalanced(migrated)) {
        migrated['videoBitRate'] = 4000000;
      }
      final deviceQuality = migrated['deviceQuality'];
      if (deviceQuality is Map) {
        for (final value in deviceQuality.values) {
          if (value is Map && formerBalanced(value)) {
            value['videoBitRate'] = 4000000;
          }
        }
      }
    }
    return merge(defaults, migrated);
  }

  Map<String, Object?> importSettings(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const PreferenceFailure('invalid_argument', '迁移偏好必须是对象。');
    }
    final imported = _copy(Map<String, Object?>.from(value));
    for (final key in {
      ..._retired,
      'deviceQuality',
      'deviceSettings',
      'appOpenModes',
    }) {
      imported.remove(key);
    }
    // 仅导入文件明确提供的全局字段；现有每设备偏好由其本机记录拥有。
    return validate(imported);
  }
}

Map<String, Object?> _copy(Map<String, Object?> value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

final _uuid = RegExp(
  r'^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$',
);
bool _devices(Object? value, bool Function(Object?) validate) =>
    value is Map &&
    value.length <= 256 &&
    value.entries.every(
      (entry) =>
          entry.key is String &&
          _deviceId(entry.key as String) &&
          validate(entry.value),
    );
bool _appModes(Object? value) =>
    value is Map &&
    value.length <= 512 &&
    value.entries.every(
      (entry) =>
          entry.key is String &&
          (entry.key as String).length <= 255 &&
          RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$')
              .hasMatch(entry.key as String) &&
          const ['phone', 'window'].contains(entry.value),
    );
bool _quality(Object? value) =>
    value is Map &&
    value.entries.every(
      (entry) =>
          entry.key is String &&
          _qualityValue(entry.key as String, entry.value),
    );
bool _qualityValue(String key, Object? value) => switch (key) {
  'qualityPreset' =>
    value == null ||
        (value is String &&
            value.isNotEmpty &&
            utf8.encode(value).length <= 64),
  'videoCodec' => const ['h264', 'h265', 'av1', 'vp8', 'vp9'].contains(value),
  'videoEncoder' =>
    value == null ||
        (value is String &&
            value.isNotEmpty &&
            value.length <= 256 &&
            RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value)),
  'maxSize' => value is int && value >= 320 && value <= 4096,
  'maxFps' => value is int && value >= 1 && value <= 120,
  'videoBitRate' => value is int && value >= 500000 && value <= 50000000,
  _ => false,
};
bool _deviceSetting(Object? value) =>
    value is Map &&
    value.entries.every(
      (entry) => switch (entry.key) {
        'clipboardSync' ||
        'showNavigationBar' ||
        'wakeOnConnect' ||
        'lockOnClose' ||
        'stayAwake' => entry.value is bool,
        'remoteAspectRatio' => const [
          'original',
          'auto',
          '9:16',
          '3:4',
          '1:1',
          '16:9',
          'custom',
        ].contains(entry.value),
        'remoteCustomRatio' => _ratio(entry.value),
        _ => false,
      },
    );
bool _ratio(Object? value) {
  if (value is! String) return false;
  final parts = value.split(':');
  if (parts.length != 2) return false;
  final width = double.tryParse(parts[0]), height = double.tryParse(parts[1]);
  return width != null &&
      height != null &&
      width.isFinite &&
      height.isFinite &&
      width > 0 &&
      height > 0 &&
      width / height >= .2 &&
      width / height <= 5;
}

bool _deviceId(String value) {
  if (value.startsWith('urn:uuid:')) value = value.substring(9);
  if (value.startsWith('{') && value.endsWith('}')) {
    value = value.substring(1, value.length - 1);
  }
  return _uuid.hasMatch(value);
}
