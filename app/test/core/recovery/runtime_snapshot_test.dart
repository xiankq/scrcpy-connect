import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/incoming_share.dart';
import 'package:scrcpy_connect/core/media/models/recovered_video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

void main() {
  test('恢复快照隔离并冻结集合及嵌套分享、输出和唤醒证据', () {
    final devices = [const DeviceSnapshot(id: 'device')];
    final errors = ['original'];
    final timing = {'decode': 1};
    final pending = [const KeepAwakeSnapshot(deviceId: 'device')];
    final sessions = [
      RecoveredVideoSession(
        session: const VideoSessionSnapshot(
          sessionId: 'session',
          deviceId: 'device',
          name: 'Phone',
          kind: .screen,
          status: .streaming,
        ),
        keepAwake: KeepAwakeSnapshot(
          deviceId: 'device',
          pendingCleanup: pending,
        ),
        output: VideoOutputReceipt(
          sessionId: 'session',
          deviceId: 'device',
          relayId: 'relay',
          textureId: 1,
          decodedWidth: 1,
          decodedHeight: 1,
          codec: 'h264',
          generation: 1,
          captureGeneration: 1,
          paused: false,
          decodedReceipts: 1,
          snapshotReceipts: 1,
          startupTimingMs: timing,
        ),
      ),
    ];
    final shares = [
      IncomingShare(shareId: 'share', status: .ready, errors: errors),
    ];
    final snapshot = RuntimeSnapshot(
      sequence: 0,
      settings: Preferences(),
      devices: devices,
      shares: shares,
      sessions: sessions,
    );
    devices.clear();
    errors.clear();
    timing['decode'] = 9;
    pending.clear();
    sessions.clear();
    shares.clear();
    expect(snapshot.devices.single.id, 'device');
    expect(snapshot.shares.single.errors, ['original']);
    expect(snapshot.sessions.single.output!.startupTimingMs['decode'], 1);
    expect(snapshot.sessions.single.keepAwake!.pendingCleanup, hasLength(1));
    expect(() => snapshot.devices.clear(), throwsUnsupportedError);
    expect(() => snapshot.shares.single.errors.clear(), throwsUnsupportedError);
    expect(
      () => snapshot.sessions.single.output!.startupTimingMs.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.sessions.single.keepAwake!.pendingCleanup.clear(),
      throwsUnsupportedError,
    );
  });
}
