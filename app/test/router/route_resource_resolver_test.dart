import 'dart:async';

import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/share_inbox_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/router/route_resource_resolver_provider.dart';

void main() {
  test('设备路由只需设备能力；换源拒绝旧回执，重试读取当前来源', () async {
    final previous = _Devices();
    final current = _Devices();
    final container = ProviderContainer(
      overrides: [deviceReaderProvider.overrideWithValue(previous)],
    );
    addTearDown(container.dispose);
    final resources = container.read(routeResourceResolverProvider);
    final reading = resources.device('device');
    final rejected = expectLater(
      reading,
      throwsA(_failure('route_source_changed')),
    );
    container.updateOverrides([
      deviceReaderProvider.overrideWithValue(current),
    ]);
    previous.reads.single.complete(
      const DeviceSnapshot(id: 'device', name: 'old'),
    );
    await rejected;
    final retry = resources.device('device');
    current.reads.single.complete(
      const DeviceSnapshot(id: 'device', name: 'new'),
    );
    expect((await retry).name, 'new');
  });

  test('路由读取在 scope 释放后不能交付旧资源', () async {
    final devices = _Devices();
    final container = ProviderContainer(
      overrides: [deviceReaderProvider.overrideWithValue(devices)],
    );
    final reading = container
        .read(routeResourceResolverProvider)
        .device('device');
    final rejected = expectLater(
      reading,
      throwsA(_failure('route_source_changed')),
    );
    container.dispose();
    devices.reads.single.complete(
      const DeviceSnapshot(id: 'device', name: 'old'),
    );
    await rejected;
  });

  test('同会话标识但异设备或已停止的资源不能打开控制页面', () async {
    final videos = _Videos();
    final container = ProviderContainer(
      overrides: [videoSessionsProvider.overrideWithValue(videos)],
    );
    addTearDown(container.dispose);
    final resources = container.read(routeResourceResolverProvider);
    videos.views = [_view('other', .streaming), _view('device', .stopped)];
    await expectLater(
      resources.session('device', 'session'),
      throwsA(_failure('missing_session')),
    );
    videos.views = [_view('device', .streaming)];
    expect((await resources.session('device', 'session')).deviceId, 'device');
  });

  test('分享深链经过队列所有者，迟到快照不能重新打开已经消费的分享', () async {
    final shares = _Shares();
    final container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(_Session()),
        incomingSharesProvider.overrideWithValue(shares),
      ],
    );
    addTearDown(container.dispose);
    final resources = container.read(routeResourceResolverProvider);
    expect((await resources.share('share')).shareId, 'share');
    await container.read(shareInboxProvider.notifier).consume('share');
    await expectLater(
      resources.share('share'),
      throwsA(_failure('missing_share')),
    );
    expect(shares.consumed, ['share']);
  });
}

Matcher _failure(String code) =>
    isA<RequestFailure>().having((error) => error.code, 'code', code);

class _Devices implements DeviceReader {
  final reads = <Completer<DeviceSnapshot>>[];
  @override
  Future<DeviceSnapshot> readDevice(String id) {
    final result = Completer<DeviceSnapshot>();
    reads.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Videos implements VideoSessions {
  List<VideoSessionView> views = [];
  @override
  Future<List<VideoSessionView>> readVideoSessions({String? deviceId}) async =>
      views;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

VideoSessionView _view(String deviceId, VideoSessionStatus status) =>
    VideoSessionView(
      session: VideoSessionSnapshot(
        sessionId: 'session',
        deviceId: deviceId,
        name: 'Screen',
        kind: .screen,
        status: status,
      ),
      wake: KeepAwakeSnapshot(deviceId: deviceId),
    );

class _Shares implements IncomingShares {
  final consumed = <String>[];
  @override
  Future<List<IncomingShare>> readIncomingShares() async => [
    const IncomingShare(shareId: 'share', status: .ready),
  ];
  @override
  Future<void> consumeShare(String id) async => consumed.add(id);
}

class _Session implements AppSession {
  @override
  final initialState = AppState();
  @override
  Stream<RuntimeEvent> get events => const Stream.empty();
  @override
  bool get initialize => false;
  @override
  Future<void> Function()? get close => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
