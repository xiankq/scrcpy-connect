/// Product defaults belong to the Dart host. Native storage preserves explicit
/// choices and fills only missing keys from the supplied initialization seed.
const applicationSettings = <String, Object?>{
  'appearance': 'light',
  'backgroundConnection': true,
  'backgroundKeepAlive': true,
  'notificationAlerts': true,
  'callAlerts': true,
  'adbBurstMode': false,
  'deviceSettings': <String, Object?>{},
  'qualityPreset': 'balanced',
  'maxSize': 1280,
  'maxFps': 60,
  'videoBitRate': 8000000,
  'videoCodec': 'h264',
  'videoEncoder': null,
  'deviceQuality': <String, Object?>{},
};
