import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:scrcpy_connect/router/route_resource_resolver.dart';

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/application/app_dependencies.dart';
import 'package:scrcpy_connect/application/app_state.dart';

final _containers = Expando<ProviderContainer>();

class _TestController extends AppController {
  void seed(AppState next) {
    state = next;
  }
}

AppController createTestController(
  ApplicationRequest request, {
  Stream<Json>? events,
  AppState? initialState,
  Future<void> Function()? close,
}) {
  final container = ProviderContainer(
    overrides: [
      appDependenciesProvider.overrideWithValue(
        AppDependencies(
          request: request,
          events: events ?? const Stream<Json>.empty(),
          initialState: initialState,
          close: close,
          initialize: false,
        ),
      ),
      appControllerProvider.overrideWith(_TestController.new),
      routeResourceResolverProvider.overrideWith(
        (ref) =>
            _FixtureRouteResources(ref.watch(appControllerProvider.notifier)),
      ),
    ],
  );
  final controller = container.read(appControllerProvider.notifier);
  _containers[controller] = container;
  return controller;
}

ProviderContainer testContainer(AppController controller) =>
    _containers[controller] ??
    (throw StateError('Use a scoped test controller.'));

class TestProviderScope extends StatelessWidget {
  const TestProviderScope({
    super.key,
    required this.controller,
    required this.child,
  });
  final AppController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: testContainer(controller),
    child: child,
  );
}

/// 夹具注入仅供测试；生产控件消费生成状态和动作，不能经这些辅助方法修改不可变快照。
extension ControllerFixture on AppController {
  void dispose() => testContainer(this).dispose();
  void queueTestShare(Json share) {
    pendingShares = [...pendingShares, share];
  }

  List<Json> get devices => snapshot().devices;
  set devices(List<Json> next) =>
      (this as _TestController).seed(snapshot().copyWith(devices: next));
  Json get settings => snapshot().settings;
  set settings(Json next) =>
      (this as _TestController).seed(snapshot().copyWith(settings: next));
  List<Json> get pendingShares => snapshot().pendingShares;
  set pendingShares(List<Json> next) =>
      (this as _TestController).seed(snapshot().copyWith(pendingShares: next));
  Json? get lastEvent => snapshot().lastEvent;
  set lastEvent(Json? next) => (this as _TestController).seed(
    snapshot().copyWith(lastEvent: () => next),
  );
  int get eventRevision => snapshot().eventRevision;
  set eventRevision(int next) =>
      (this as _TestController).seed(snapshot().copyWith(eventRevision: next));
  bool get loading => snapshot().loading;
  set loading(bool next) =>
      (this as _TestController).seed(snapshot().copyWith(loading: next));
  String? get deviceError => snapshot().deviceError;
  set deviceError(String? next) => (this as _TestController).seed(
    snapshot().copyWith(deviceError: () => next),
  );
  String? get settingsError => snapshot().settingsError;
  set settingsError(String? next) => (this as _TestController).seed(
    snapshot().copyWith(settingsError: () => next),
  );
  String? get audioError => snapshot().audioError;
  set audioError(String? next) => (this as _TestController).seed(
    snapshot().copyWith(audioError: () => next),
  );
  String? get focusedDeviceId => snapshot().focusedDeviceId;
  set focusedDeviceId(String? next) => (this as _TestController).seed(
    snapshot().copyWith(focusedDeviceId: () => next),
  );
  String get clipboardState => snapshot().clipboardState;
  set clipboardState(String next) =>
      (this as _TestController).seed(snapshot().copyWith(clipboardState: next));
  String? get clipboardError => snapshot().clipboardError;
  set clipboardError(String? next) => (this as _TestController).seed(
    snapshot().copyWith(clipboardError: () => next),
  );
  int get clipboardReadCount => snapshot().clipboardReadCount;
  set clipboardReadCount(int next) => (this as _TestController).seed(
    snapshot().copyWith(clipboardReadCount: next),
  );
  int get clipboardWriteCount => snapshot().clipboardWriteCount;
  set clipboardWriteCount(int next) => (this as _TestController).seed(
    snapshot().copyWith(clipboardWriteCount: next),
  );
  int get clipboardSendCount => snapshot().clipboardSendCount;
  set clipboardSendCount(int next) => (this as _TestController).seed(
    snapshot().copyWith(clipboardSendCount: next),
  );
}

final _recordDevices = Expando<List<Json>>();
void seedRouteDevices(AppController controller, List<Json> devices) {
  _recordDevices[controller] = devices;
}

class _FixtureRouteResources extends RouteResourceResolver {
  _FixtureRouteResources(super.controller);
  @override
  Future<Json> device(String id) async {
    if (_recordDevices[controller] == null) return super.device(id);
    final fixture = (_recordDevices[controller] ?? <Json>[])
        .where((d) => d['id'] == id)
        .firstOrNull;
    final current = controller
        .snapshot()
        .devices
        .where((d) => d['id'] == id)
        .firstOrNull;
    return fixture ?? current ?? await super.device(id);
  }

  @override
  Future<Json> share(String id) async {
    if (_recordDevices[controller] == null) return super.share(id);
    final pending = controller
        .snapshot()
        .pendingShares
        .where((s) => s['shareId'] == id)
        .firstOrNull;
    return pending ?? await super.share(id);
  }
}
