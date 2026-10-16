import 'package:scrcpy_connect/services/app_controller.dart';

String audioStatus(Json? source) => source == null
    ? '声音尚未开启'
    : switch (value(source, 'status')) {
        'playing' => source['muted'] == true ? '正在播放 · 已静音' : '正在播放',
        'starting' => '正在等待设备声音',
        'paused' => '声音已暂停',
        'stopped' => '声音已停止',
        'error' => '当前无法播放',
        _ => '声音状态待核验',
      };
bool audioActive(Json source) =>
    ['playing', 'starting', 'paused'].contains(source['status']);
String audioId(Json source) => value(source, 'sourceId', value(source, 'id'));

String sourceDeviceName(AppController controller, Json source) {
  final devices = controller.snapshot().devices.where(
    (d) => d['id'] == source['deviceId'],
  );
  return devices.isEmpty
      ? value(source, 'deviceName', '被控设备')
      : deviceName(devices.first);
}
