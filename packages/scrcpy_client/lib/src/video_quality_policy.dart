import 'package:device_protocol/device_protocol.dart';

/// Baseline remote capture settings, shared with the application's defaults.
const defaultVideoQuality = <String, Object?>{
  'qualityPreset': 'balanced',
  'maxSize': 1280,
  'maxFps': 60,
  'videoBitRate': 4000000,
  'videoCodec': 'h264',
  'videoEncoder': null,
};

/// Resolves product choices before the native executor receives concrete media
/// parameters. Native probing and session admission retain their own checks.
class VideoQualityPolicy {
  static void validateSettings(Map<String, dynamic> changes) {
    void validate(Map<Object?, Object?> values) {
      if (values.containsKey('qualityPreset') &&
          !presets.containsKey(values['qualityPreset'])) {
        throw const InteropException('invalid_argument', '画质预设无效。');
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

  static const keys = [
    'qualityPreset',
    'maxSize',
    'maxFps',
    'videoBitRate',
    'videoCodec',
    'videoEncoder',
  ];
  static const presets = {
    'smooth': (720, 30, 2000000),
    'balanced': (1280, 60, 4000000),
    'clear': (1920, 60, 12000000),
  };

  static Map<String, dynamic> resolve(
    Map<String, dynamic> settings,
    String? deviceId, [
    Map<String, dynamic> patch = const {},
  ]) {
    final overrides = (settings['deviceQuality'] as Map?)?[deviceId] as Map?;
    final result = <String, dynamic>{
      for (final key in keys) key: defaultVideoQuality[key],
      for (final key in keys)
        if (settings.containsKey(key)) key: settings[key],
      if (overrides != null)
        for (final key in keys)
          if (overrides.containsKey(key)) key: overrides[key],
    };
    if (patch.containsKey('preset')) {
      final selected = presets[patch['preset']];
      if (selected == null) {
        throw const InteropException('invalid_argument', '画质预设无效。');
      }
      result.addAll({
        'qualityPreset': patch['preset'],
        'maxSize': selected.$1,
        'maxFps': selected.$2,
        'videoBitRate': selected.$3,
      });
    }
    for (final (key, alias) in [
      ('maxSize', 'maxSize'),
      ('maxFps', 'maxFps'),
      ('videoBitRate', 'bitRate'),
      ('videoCodec', 'codec'),
      ('videoEncoder', 'encoder'),
    ]) {
      if (patch.containsKey(key)) {
        result[key] = patch[key];
      } else if (patch.containsKey(alias)) {
        result[key] = patch[alias];
      }
    }
    if (const [
      'audioMode',
      'audioEnabled',
      'audioCodec',
    ].any(patch.containsKey)) {
      throw const InteropException('invalid_argument', '设备声音设置请使用独立音源设置。');
    }
    return result;
  }

  static Map<String, dynamic> current(Map<String, dynamic> quality) => {
    ...quality,
    'preset': quality['qualityPreset'],
    'bitRate': quality['videoBitRate'],
    'codec': quality['videoCodec'],
    'audio': false,
  };

  static Map<String, dynamic> options(
    Map<String, dynamic> facts,
    Map<String, dynamic> settings,
    String? deviceId,
  ) {
    final available = (facts['probe'] as Map?)?['status'] == 'enumerated';
    List<Map<String, dynamic>> choices(
      List<int> values,
      String Function(int) label,
    ) => [
      for (final value in values)
        {'value': value, 'label': label(value), 'available': available},
    ];
    return {
      ...facts,
      'current': current(resolve(settings, deviceId)),
      'deviceId': deviceId,
      'scope': deviceId == null ? 'global' : 'device',
      'presets': [
        for (final entry in {
          'smooth': '流畅',
          'balanced': '均衡',
          'clear': '清晰',
        }.entries)
          {'id': entry.key, 'name': entry.value, 'available': available},
      ],
      'maxSize': choices([720, 1080, 1280, 1920], (value) => '$value'),
      'maxFps': choices([30, 60], (value) => '$value fps'),
      'bitRate': choices([
        2000000,
        4000000,
        8000000,
        12000000,
      ], (value) => '${value ~/ 1000000} Mbps'),
      'maxSizes': [720, 1080, 1280, 1920],
      'frameRates': [30, 60],
      'audioAvailable': false,
    };
  }
}
