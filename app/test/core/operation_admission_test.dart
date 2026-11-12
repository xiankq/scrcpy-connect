import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/control_operations.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/video_display.dart';
import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/devices/device_assessment.dart';
import 'package:scrcpy_connect/core/devices/device_calls.dart';
import 'package:scrcpy_connect/core/devices/device_notifications.dart';
import 'package:scrcpy_connect/core/devices/device_observation.dart';
import 'package:scrcpy_connect/core/devices/device_operations.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_mutations.dart';
import 'package:scrcpy_connect/core/files/file_operations.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner.dart';
import 'package:scrcpy_connect/core/media/media_operations.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_screenshots.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';

Matcher failsWith(String code) => throwsA(
  isA<RequestFailure>().having((failure) => failure.code, 'code', code),
);

void main() {
  test('控制先拒绝无效结构，恢复期间只放行精确会话的释放', () async {
    final capture = _Control();
    final RemoteControl control = ControlOperations(
      sessions: capture,
      isDisposed: () => false,
      isStateUnverified: () => true,
      diagnostics: DiagnosticReporter(null),
    );
    await expectLater(
      control.sendControl(
        const ControlTarget(sessionId: ''),
        const ControlAction.text('x'),
      ),
      failsWith('invalid_argument'),
    );
    await expectLater(
      control.sendControl(
        const ControlTarget(sessionId: 'session'),
        const ControlAction.key(1, action: .up),
      ),
      failsWith('invalid_argument'),
    );
    await expectLater(
      control.sendControl(
        const ControlTarget(sessionId: 'session', captureGeneration: 4),
        const ControlAction.text('x'),
      ),
      failsWith('state_unverified'),
    );
    await expectLater(
      control.sendControl(
        const ControlTarget(deviceId: 'device', captureGeneration: 4),
        const ControlAction.key(1, action: .up),
      ),
      failsWith('state_unverified'),
    );
    await control.sendControl(
      const ControlTarget(sessionId: 'session', captureGeneration: 4),
      const ControlAction.key(1, action: .up),
    );
    await control.sendControl(
      const ControlTarget(sessionId: 'session', captureGeneration: 4),
      const ControlAction.touch(
        (x: 0, y: 0, width: 10, height: 10),
        action: .cancel,
        pointerId: 0,
      ),
    );
    expect(capture.calls, 2);
  });

  test('应用关闭后连输入释放也不进入捕获所有者', () async {
    final capture = _Control();
    final RemoteControl control = ControlOperations(
      sessions: capture,
      isDisposed: () => true,
      isStateUnverified: () => true,
      diagnostics: DiagnosticReporter(null),
    );
    await expectLater(
      control.sendControl(
        const ControlTarget(sessionId: 'session', captureGeneration: 4),
        const ControlAction.key(1, action: .up),
      ),
      failsWith('disposed'),
    );
    expect(capture.calls, 0);
  });

  test('恢复期间阻止文件写入，允许取消，取消信号仍交给原所有者', () async {
    final owner = _Files();
    var closed = false;
    final operations = FileOperations(
      search: () => owner,
      gallery: () => owner,
      directories: () => owner,
      mutations: () => owner,
      transfers: owner,
      isDisposed: () => closed,
      isStateUnverified: () => true,
      diagnostics: DiagnosticReporter(null),
    );
    final FileMutations mutations = operations;
    final FileSearch search = operations;
    final FileDirectories directories = operations;
    await expectLater(
      mutations.createDirectory('', '/new'),
      failsWith('invalid_argument'),
    );
    await expectLater(
      mutations.createDirectory('device', '/new'),
      failsWith('state_unverified'),
    );
    expect(owner.writes, 0);
    await search.cancelSearch((
      deviceId: 'device',
      searchId: 'search',
      path: '/',
    ));
    expect(owner.cancels, 1);
    final cancellation = FileCancellation()..cancel();
    await expectLater(
      directories.readDirectory((
        deviceId: 'device',
        path: '/',
      ), cancellation: cancellation),
      failsWith('cancelled'),
    );
    expect(owner.cancellation, same(cancellation));
    closed = true;
    await expectLater(
      search.cancelSearch((deviceId: 'device', searchId: 'search', path: '/')),
      failsWith('disposed'),
    );
    expect(owner.cancels, 1);
  });

  test('设备观察在恢复期间允许读取，拒绝改变意图；关闭后拒绝读取', () async {
    final owner = _Device();
    var closed = false;
    var borrows = 0;
    final operations = DeviceOperations(
      capabilities: () => throw StateError('观察不应取得能力评估'),
      observation: () {
        borrows++;
        return owner;
      },
      calls: () => throw StateError('观察不应取得通话能力'),
      notifications: () => throw StateError('观察不应取得通知能力'),
      wake: (id, {connectionId}) => throw StateError('不应唤醒设备'),
      isDisposed: () => closed,
      isStateUnverified: () => true,
      diagnostics: DiagnosticReporter(null),
    );
    final DeviceObservation observation = operations;
    expect(await observation.readObservations(), isEmpty);
    await expectLater(
      observation.readObservations(cancellation: AdbCancellation()..cancel()),
      failsWith('cancelled'),
    );
    await expectLater(
      observation.startObservation('device'),
      failsWith('state_unverified'),
    );
    await expectLater(
      operations.wakeDevice('device'),
      failsWith('state_unverified'),
    );
    expect(owner.starts, 0);
    closed = true;
    await expectLater(observation.readObservations(), failsWith('disposed'));
    expect(owner.reads, 1);
    expect(borrows, 1);
  });

  test('恢复期间媒体不能恢复播放，停止必须等待原输出关闭', () async {
    final owner = _Outputs();
    final operations = MediaOperations(
      videos: owner,
      audio: owner,
      screenshots: owner,
      quality: owner,
      resizeDisplayCapture: (_, _) async => fail('不应调整显示'),
      emit: (_) {},
      isDisposed: () => false,
      isStateUnverified: () => true,
      diagnostics: DiagnosticReporter(null),
    );
    final RemoteAudio audio = operations;
    final VideoDisplayControl displays = operations;
    await expectLater(
      audio.resumeAudio(
        const DeviceAudioTarget(deviceId: 'device', sourceId: 'source'),
      ),
      failsWith('state_unverified'),
    );
    await expectLater(
      displays.resizeDisplay(const ControlTarget(sessionId: 'session'), (
        width: 100,
        height: 100,
      )),
      failsWith('state_unverified'),
    );
    var stopped = false;
    final pending = audio
        .stopAudio(
          const DeviceAudioTarget(deviceId: 'device', sourceId: 'source'),
        )
        .then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    owner.closed.complete();
    await pending;
    expect(stopped, isTrue);
  });
}

class _Control implements RemoteControl {
  int calls = 0;
  @override
  Future<ControlReceipt> sendControl(
    ControlTarget target,
    ControlAction action,
  ) async {
    calls++;
    return const ControlReceipt.emptyText();
  }
}

class _Files
    implements
        FileSearch,
        GalleryScanner,
        FileDirectories,
        FileMutations,
        FileTransfers {
  int writes = 0, cancels = 0;
  FileCancellation? cancellation;
  @override
  Future<void> createDirectory(String deviceId, String path) async => writes++;
  @override
  Future<void> cancelSearch(FileSearchTarget target) async => cancels++;
  @override
  Future<FileDirectorySnapshot> readDirectory(
    FileDirectoryTarget target, {
    FileCatalogFilter filter = .all,
    FileDirectorySort sort = .name,
    bool descending = false,
    int offset = 0,
    int limit = 10000,
    FileCancellation? cancellation,
  }) async {
    this.cancellation = cancellation;
    cancellation?.check();
    return FileDirectorySnapshot(deviceId: target.deviceId, path: target.path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Device
    implements
        DeviceAssessment,
        DeviceObservation,
        DeviceCalls,
        DeviceNotifications {
  int reads = 0, starts = 0;
  @override
  Future<List<DeviceObservationSnapshot>> readObservations({
    cancellation,
  }) async {
    reads++;
    return [];
  }

  @override
  Future<DeviceObservationSnapshot> startObservation(
    String deviceId, {
    bool allowStart = true,
    cancellation,
  }) async {
    starts++;
    throw StateError('不应改变观察意图');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Outputs
    implements
        VideoSessions,
        RemoteAudio,
        VideoScreenshots,
        VideoQualityControl {
  final closed = Completer<void>();
  @override
  Future<void> stopAudio(DeviceAudioTarget target) => closed.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
