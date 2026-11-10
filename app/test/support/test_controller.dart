import 'package:scrcpy_connect/widgets/remote_views.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/router/route_resource_resolver.dart';

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/bootstrap/app_dependencies.dart';
import 'package:scrcpy_connect/models/app_state.dart';

final _containers = Expando<ProviderContainer>();
final _views = Expando<RemoteViews>();

class _TestController extends AppStore {
  void seed(AppState next) {
    state = next;
  }
}

AppStore createTestController(
  ApplicationRequest request, {
  Stream<Json>? events,
  AppState? initialState,
  Future<void> Function()? close,
}) {
  final operationEvents = StreamController<Json>.broadcast(sync: true);
  final incoming = events?.listen(operationEvents.add);
  Future<Json> invoke(String command, [Json params = const {}]) {
    final activity = command == 'activities.stop' ? params['activityId'] : null;
    final session = command == 'session.stop'
        ? params['sessionId']
        : activity is String && activity.startsWith('session:')
        ? activity.substring(8)
        : null;
    final device = ['devices.disconnect', 'devices.forget'].contains(command)
        ? params['deviceId']
        : activity is String && activity.startsWith('connection:')
        ? activity.substring(11)
        : null;
    if (session is String) {
      operationEvents.add({
        'type': 'session.stop.requested',
        'data': {'sessionId': session},
      });
    }
    if (device is String) {
      operationEvents.add({
        'type': 'device.disconnect.requested',
        'deviceId': device,
        'data': <String, dynamic>{},
      });
    }
    return request(command, params);
  }

  final container = ProviderContainer(
    overrides: [
      appDependenciesProvider.overrideWithValue(
        AppDependencies(
          request: invoke,
          events: operationEvents.stream,
          initialState: initialState,
          close: () async {
            await incoming?.cancel();
            await operationEvents.close();
            await close?.call();
          },
          initialize: false,
        ),
      ),
      appStoreProvider.overrideWith(_TestController.new),
      routeResourceResolverProvider.overrideWith(
        (ref) => _FixtureRouteResources(ref.watch(appStoreProvider.notifier)),
      ),
    ],
  );
  final controller = container.read(appStoreProvider.notifier);
  _containers[controller] = container;
  final views = _views[controller] = RemoteViews(controller);
  container.listen(appStoreProvider, (_, _) => views.reconcile());
  return controller;
}

ProviderContainer testContainer(AppStore controller) =>
    _containers[controller] ??
    (throw StateError('Use a scoped test controller.'));

class TestProviderScope extends StatelessWidget {
  const TestProviderScope({
    super.key,
    required this.controller,
    required this.child,
  });
  final AppStore controller;
  final Widget child;
  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: testContainer(controller),
    child: RemoteViewsScope(views: controller.views, child: child),
  );
}

/// 夹具注入仅供测试；生产控件消费生成状态和动作，不能经这些辅助方法修改不可变快照。
extension ControllerFixture on AppStore {
  RemoteViews get views => _views[this]!;
  void dispose() {
    views.dispose();
    testContainer(this).dispose();
  }

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
  int get eventRevision => snapshot().eventRevision;
  bool get loading => snapshot().loading;
  set loading(bool next) =>
      (this as _TestController).seed(snapshot().copyWith(loading: next));
  String? get deviceError => snapshot().deviceError;
  String? get settingsError => snapshot().settingsError;
  String? get audioError => snapshot().audioError;
  String? get focusedDeviceId => snapshot().focusedDeviceId;
  set focusedDeviceId(String? next) => (this as _TestController).seed(
    snapshot().copyWith(focusedDeviceId: () => next),
  );
  String get clipboardState => snapshot().clipboardState;
  String? get clipboardError => snapshot().clipboardError;
  int get clipboardReadCount => snapshot().clipboardReadCount;
  int get clipboardWriteCount => snapshot().clipboardWriteCount;
  int get clipboardSendCount => snapshot().clipboardSendCount;
}

final _recordDevices = Expando<List<Json>>();
void seedRouteDevices(AppStore controller, List<Json> devices) {
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
