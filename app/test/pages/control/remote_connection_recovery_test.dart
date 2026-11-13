import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/models/device_disconnect_requested.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/video_stop_requested.dart';
import 'package:scrcpy_connect/pages/control/remote_connection_recovery.dart';

void main() {
  test('只有已查看的整机画面可在原设备离线后消费一次重连意图', () {
    final recovery = RemoteConnectionRecovery();
    void observe(DeviceConnectionStatus status, {bool phoneScreen = true}) {
      recovery.acceptEvent(
        DeviceListChanged([
          DeviceSnapshot(
            id: 'device',
            name: 'Phone',
            status: status,
            autoReconnect: true,
          ),
        ]).toApplicationEvent(),
        deviceId: 'device',
        sessionId: 'session',
        phoneScreen: phoneScreen,
      );
    }

    observe(.offline);
    observe(.connected);
    expect(recovery.take(), isFalse);
    recovery.viewed();
    observe(.offline, phoneScreen: false);
    observe(.connected, phoneScreen: false);
    expect(recovery.take(), isFalse);
    observe(.offline);
    expect(recovery.pending, isTrue);
    expect(recovery.take(), isFalse);
    observe(.connected);
    expect(recovery.take(), isTrue);
    expect(recovery.take(), isFalse);
  });

  for (final stop in <AppEvent>[
    const VideoStopRequested('session'),
    const DeviceDisconnectRequested('device'),
  ]) {
    test('${stop.type} 作废恢复，迟到连接不能撤销停止', () {
      final recovery = RemoteConnectionRecovery()..viewed();
      bool accept(AppEvent event) => recovery.acceptEvent(
        event.toApplicationEvent(),
        deviceId: 'device',
        sessionId: 'session',
        phoneScreen: true,
      );
      accept(
        DeviceListChanged([
          const DeviceSnapshot(
            id: 'device',
            name: 'Phone',
            status: .offline,
            autoReconnect: true,
          ),
        ]),
      );
      expect(recovery.pending, isTrue);
      expect(accept(const VideoStopRequested('other')), isFalse);
      expect(accept(const DeviceDisconnectRequested('other')), isFalse);
      expect(recovery.pending, isTrue);
      expect(accept(stop), isTrue);
      accept(
        DeviceListChanged([
          const DeviceSnapshot(
            id: 'device',
            name: 'Phone',
            status: .connected,
            autoReconnect: true,
          ),
        ]),
      );
      recovery.defer();
      expect(recovery.pending, isFalse);
      expect(recovery.take(), isFalse);
    });
  }
}
