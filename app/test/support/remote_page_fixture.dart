import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/app_state.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/remote_control_intent.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';

import 'router_test_app.dart';
import 'test_controller.dart';

class RemotePageFixture {
  RemotePageFixture({this.onRequest, AppState? initialState}) {
    controller = createTestController(
      (command, [params = const {}]) async {
        calls.add((command, params));
        return await onRequest?.call(command, params) ??
            (command == 'session.start' ? pixels : {});
      },
      events: events.stream,
      initialState: initialState,
    );
  }

  static const pixels = <String, dynamic>{
    'sessionId': 'window',
    'deviceId': 'phone',
    'status': 'streaming',
    'textureId': 1,
    'width': 200,
    'height': 400,
    'captureGeneration': 1,
    'generation': 10,
    'firstFrameDecoded': true,
    'evidence': 'media_codec.decodedFrame',
  };
  final FutureOr<Json?> Function(String, Json)? onRequest;
  final events = StreamController<Json>.broadcast(sync: true);
  final calls = <(String, Json)>[];
  late final AppController controller;

  Future<void> show(
    WidgetTester tester, {
    String? packageName,
    RemoteControlIntent? initialAction,
    Widget? home,
    List<Json> devices = const [],
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    });
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        devices: devices,
        home:
            home ??
            RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
              packageName: packageName,
              initialAction: initialAction,
            ),
      ),
    );
  }

  Iterable<Json> commands(String command) =>
      calls.where((call) => call.$1 == command).map((call) => call.$2);
}
