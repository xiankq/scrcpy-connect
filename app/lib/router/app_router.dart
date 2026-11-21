import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/media/video_screenshots.dart';
import 'package:scrcpy_connect/pages/activities/activities_page.dart';
import 'package:scrcpy_connect/pages/apps/device_apps_page.dart';
import 'package:scrcpy_connect/pages/calls/calls_page.dart';
import 'package:scrcpy_connect/pages/control/control_page.dart';
import 'package:scrcpy_connect/pages/control/screenshot/screenshot_page.dart';
import 'package:scrcpy_connect/pages/control/settings/control_settings_page.dart';
import 'package:scrcpy_connect/pages/device_setup/add_device_page.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/connection_form_page.dart';
import 'package:scrcpy_connect/pages/device_setup/discovery/device_discovery_page.dart';
import 'package:scrcpy_connect/pages/device_setup/wireless/wireless_setup_page.dart';
import 'package:scrcpy_connect/pages/devices/connection_settings/device_connection_settings_page.dart';
import 'package:scrcpy_connect/pages/devices/details/device_details_page.dart';
import 'package:scrcpy_connect/pages/devices/devices_page.dart';
import 'package:scrcpy_connect/pages/devices/diagnostics/connection_diagnostics_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/device_management_page.dart';
import 'package:scrcpy_connect/pages/files/details/file_details_page.dart';
import 'package:scrcpy_connect/pages/files/directory_picker/file_directory_picker_page.dart';
import 'package:scrcpy_connect/pages/files/files_page.dart';
import 'package:scrcpy_connect/pages/files/import/document_import_page.dart';
import 'package:scrcpy_connect/pages/files/search/file_search_page.dart';
import 'package:scrcpy_connect/pages/gallery/gallery_page.dart';
import 'package:scrcpy_connect/pages/gallery/preview/media_preview_page.dart';
import 'package:scrcpy_connect/pages/incoming_share/incoming_share_page.dart';
import 'package:scrcpy_connect/pages/notifications/notifications_page.dart';
import 'package:scrcpy_connect/pages/route_error/route_error_page.dart';
import 'package:scrcpy_connect/pages/settings/adb_identity/adb_identity_page.dart';
import 'package:scrcpy_connect/pages/settings/appearance/appearance_page.dart';
import 'package:scrcpy_connect/pages/settings/background/background_page.dart';
import 'package:scrcpy_connect/pages/settings/data_preferences/data_preferences_page.dart';
import 'package:scrcpy_connect/pages/settings/media_cache/media_cache_page.dart';
import 'package:scrcpy_connect/pages/settings/runtime_logs/runtime_logs_page.dart';
import 'package:scrcpy_connect/pages/settings/settings_page.dart';
import 'package:scrcpy_connect/pages/settings/app_updates_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/transfer_details_page.dart';
import 'package:scrcpy_connect/pages/transfers/export/document_export_page.dart';
import 'package:scrcpy_connect/pages/transfers/receive/receive_content_page.dart';
import 'package:scrcpy_connect/pages/transfers/transfers_page.dart';
import 'package:scrcpy_connect/router/models/remote_control_intent.dart';
import 'package:scrcpy_connect/router/models/remote_launch_intent.dart';
import 'package:scrcpy_connect/router/route_observers.dart';
import 'package:scrcpy_connect/router/route_resource_resolver_provider.dart';
import 'package:scrcpy_connect/router/route_resource_view.dart';
import 'package:scrcpy_connect/widgets/navigation_scaffold.dart';
import 'package:scrcpy_connect/widgets/visible_device_focus.dart';

part 'app_router.g.dart';

GlobalKey<NavigatorState> _root = GlobalKey<NavigatorState>();
GlobalKey<NavigatorState> _content = GlobalKey<NavigatorState>();
RouteResourceResolver _resources(BuildContext context) =>
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(routeResourceResolverProvider);

List<RouteBase> typedRoutes(GlobalKey<NavigatorState> root) {
  _root = root;
  _content = GlobalKey<NavigatorState>();
  final routes = $appRoutes;
  // typed routes retain one source of URL/argument truth; only their navigation
  // plane differs. The ordinary plane survives root immersive overlays.
  bool ordinary(RouteBase route) =>
      route is StatefulShellRoute ||
      route is GoRoute && route.parentNavigatorKey == _content;
  return [
    ShellRoute(
      navigatorKey: _content,
      restorationScopeId: 'app-content',
      builder: (context, state, child) =>
          AppNavigationShell(uri: state.uri, child: child),
      routes: routes.where(ordinary).toList(),
    ),
    ...routes.where((route) => !ordinary(route)),
  ];
}

GoRouter createAppRouter({
  String initialLocation = '/devices',
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  GoRouter.optionURLReflectsImperativeAPIs = true;
  final root = navigatorKey ?? GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: root,
    restorationScopeId: 'connect-router',
    observers: [sessionRouteObserver],
    initialLocation: initialLocation,
    routes: typedRoutes(root),
    errorPageBuilder: (context, state) => MaterialPage<void>(
      key: state.pageKey,
      child: const RouteErrorPage(message: '这个位置无法打开，请从设备列表重新选择功能。'),
    ),
  );
}

Page<void> _page(GoRouterState state, Widget child, {String? restorationId}) =>
    MaterialPage<void>(
      key: state.pageKey,
      restorationId: restorationId ?? state.pageKey.value,
      child: child,
    );

abstract class _AppPageRoute extends GoRouteData {
  const _AppPageRoute();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

Widget _deviceRecord(
  BuildContext context,
  GoRouterState state,
  String deviceId,
  String name,
  Widget Function(BuildContext, GoRouterState, DeviceSnapshot) build,
) {
  final identity =
      '$name:$deviceId:${state.pathParameters['sessionId'] ?? ''}:${state.pathParameters['packageName'] ?? ''}';
  return RouteResourceView(
    key: ValueKey('${state.pageKey.value}:$identity'),
    identity: identity,
    preserveContent: ['remote', 'remote-app', 'remote-session'].contains(name),
    load: () => _resources(context).device(deviceId),
    builder: (context, device) =>
        ['remote', 'remote-app', 'remote-session'].contains(name)
        ? build(context, state, device)
        : VisibleDeviceFocus(
            deviceId: AppNavigationShell.isVisible(context) ? device.id : '',
            child: build(context, state, device),
          ),
  );
}

Widget _remoteView(
  BuildContext context,
  GoRouterState state,
  DeviceSnapshot device, {
  Object? intent,
  bool keyboard = false,
  String? packageName,
  VideoSessionView? session,
  RemoteControlIntent? action,
}) {
  if (session == null && intent is! RemoteLaunchIntent) {
    return const RouteErrorPage(message: '请从设备工作台明确打开画面。恢复这个位置不会自动创建新的控制会话。');
  }
  return ControlPage(
    key: ValueKey(
      'remote:${state.pageKey.value}:${device.id}:${state.pathParameters['sessionId'] ?? packageName ?? 'screen'}',
    ),
    device: device,
    existingSession: session,
    packageName: packageName ?? session?.session.packageName,
    requestKeyboard: keyboard,
    initialAction:
        action ?? (intent is RemoteLaunchIntent ? intent.action : null),
  );
}

@TypedGoRoute<RootRoute>(path: '/')
class RootRoute extends GoRouteData with $RootRoute {
  const RootRoute();
  @override
  String redirect(BuildContext context, GoRouterState state) =>
      const DevicesRoute().location;
}

@TypedStatefulShellRoute<HomeShellRoute>(
  branches: [
    TypedStatefulShellBranch<DevicesBranch>(
      routes: [TypedGoRoute<DevicesRoute>(path: '/devices', name: 'devices')],
    ),
    TypedStatefulShellBranch<TransfersBranch>(
      routes: [
        TypedGoRoute<TransfersRoute>(path: '/transfers', name: 'transfers'),
      ],
    ),
    TypedStatefulShellBranch<SettingsBranch>(
      routes: [
        TypedGoRoute<SettingsRoute>(path: '/settings', name: 'settings'),
      ],
    ),
  ],
)
class HomeShellRoute extends StatefulShellRouteData {
  const HomeShellRoute();
  // 三个分支只有入口页；位置及返回链由外层路由恢复，运行中仍由 shell 保留页面。
  // go_router 18.1.4 的分支恢复不会在替换 bucket 时重新注册已有属性。
  @override
  Page<void> pageBuilder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  ) => _page(
    state,
    NavigationScaffold(navigationShell: navigationShell),
    restorationId: 'home-shell-page',
  );
}

class DevicesBranch extends StatefulShellBranchData {
  const DevicesBranch();
}

class TransfersBranch extends StatefulShellBranchData {
  const TransfersBranch();
}

class SettingsBranch extends StatefulShellBranchData {
  const SettingsBranch();
}

class DevicesRoute extends GoRouteData with $DevicesRoute {
  const DevicesRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) => DevicesPage();
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state), restorationId: 'devices-page');
}

class TransfersRoute extends GoRouteData with $TransfersRoute {
  const TransfersRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const TransfersPage(embedded: true);
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state), restorationId: 'transfers-page');
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const SettingsPage(embedded: true);
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state), restorationId: 'settings-page');
}

@TypedGoRoute<RouteErrorRoute>(path: '/unavailable', name: 'route-error')
class RouteErrorRoute extends _AppPageRoute with $RouteErrorRoute {
  const RouteErrorRoute({this.reason = 'missing-record'});
  final String reason;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return RouteErrorPage(
      message: reason == 'missing-session'
          ? '无法识别这个控制会话。请从设备工作台重新选择；不会自动创建新画面。'
          : '页面缺少必要的记录信息，请返回设备列表重新选择。',
    );
  }
}

@TypedGoRoute<TransferCenterRoute>(
  path: '/activity/transfers',
  name: 'transfer-center',
)
class TransferCenterRoute extends _AppPageRoute with $TransferCenterRoute {
  const TransferCenterRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const TransfersPage();
  }
}

@TypedGoRoute<SettingsPageRoute>(path: '/preferences', name: 'settings-page')
class SettingsPageRoute extends _AppPageRoute with $SettingsPageRoute {
  const SettingsPageRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const SettingsPage();
  }
}

@TypedGoRoute<AddDeviceRoute>(path: '/connection/add', name: 'add-device')
class AddDeviceRoute extends _AppPageRoute with $AddDeviceRoute {
  const AddDeviceRoute({this.deviceId});
  final String? deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final resources = _resources(context);
    final id = deviceId;
    return id == null
        ? AddDevicePage()
        : RouteResourceView(
            identity: 'reauthorize:$id',
            load: () => resources.device(id),
            builder: (_, device) => AddDevicePage(initialDevice: device),
          );
  }
}

@TypedGoRoute<WirelessGuideRoute>(
  path: '/connection/wireless',
  name: 'wireless-guide',
)
class WirelessGuideRoute extends _AppPageRoute with $WirelessGuideRoute {
  const WirelessGuideRoute({this.deviceId, this.address = ''});
  final String? deviceId;
  final String address;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final resources = _resources(context);
    final id = deviceId;
    Widget guide([DeviceSnapshot? record]) =>
        AddDevicePage(initialDevice: record, deviceId: id, address: address);
    return id == null
        ? guide()
        : RouteResourceView(
            identity: 'wireless:$id',
            load: () => resources.device(id),
            builder: (_, device) => guide(device),
          );
  }
}

@TypedGoRoute<ConnectionFormRoute>(
  path: '/connection/form',
  name: 'connection-form',
)
class ConnectionFormRoute extends _AppPageRoute with $ConnectionFormRoute {
  const ConnectionFormRoute({
    this.deviceId,
    this.address = '',
    this.port = '',
    this.pairing = false,
    this.transport,
  });
  final String? deviceId;
  final String address;
  final String port;
  final bool pairing;
  final ConnectionTransport? transport;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final resources = _resources(context);
    Widget form([DeviceSnapshot? record]) => AddDevicePage(
      key: state.pageKey,
      initialMode: pairing ? AddDeviceMode.pairing : AddDeviceMode.ip,
      address: address,
      port: port,
      deviceId: deviceId,
      transport: record == null
          ? transport ?? ConnectionTransport.tls
          : connectionTransportForRecord(record) == ConnectionTransport.tls
          ? ConnectionTransport.tls
          : transport ?? ConnectionTransport.tcp,
    );
    final id = deviceId;
    return id == null
        ? form()
        : RouteResourceView(
            identity: 'connection:$id',
            load: () => resources.device(id),
            builder: (_, record) => form(record),
          );
  }
}

@TypedGoRoute<DiscoveryRoute>(path: '/connection/discovery', name: 'discovery')
class DiscoveryRoute extends _AppPageRoute with $DiscoveryRoute {
  const DiscoveryRoute({this.selection = false});
  final bool selection;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return DeviceDiscoveryPage(returnSelection: selection);
  }
}

@TypedGoRoute<UsbGuideRoute>(path: '/connection/usb', name: 'usb-guide')
class UsbGuideRoute extends _AppPageRoute with $UsbGuideRoute {
  const UsbGuideRoute({this.deviceId});
  final String? deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final id = deviceId;
    Widget page([DeviceSnapshot? record]) => AddDevicePage(
      initialMode: AddDeviceMode.usb,
      deviceId: id,
      initialDevice: record,
    );
    if (id == null) return page();
    return _deviceRecord(
      context,
      state,
      id,
      'usb-guide',
      (_, _, record) => page(record),
    );
  }
}

@TypedGoRoute<QrPairRoute>(path: '/connection/qr', name: 'qr-pair')
class QrPairRoute extends _AppPageRoute with $QrPairRoute {
  const QrPairRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return AddDevicePage(initialMode: AddDeviceMode.qr);
  }
}

@TypedGoRoute<WorkspaceRoute>(path: '/devices/:deviceId', name: 'workspace')
class WorkspaceRoute extends _AppPageRoute with $WorkspaceRoute {
  const WorkspaceRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        DevicesPage(initialDevice: device);
    return _deviceRecord(context, state, deviceId, 'workspace', page);
  }
}

@TypedGoRoute<DeviceManagementRoute>(
  path: '/devices/:deviceId/manage',
  name: 'device-management',
)
class DeviceManagementRoute extends _AppPageRoute with $DeviceManagementRoute {
  const DeviceManagementRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) => _deviceRecord(
    context,
    state,
    deviceId,
    'device-management',
    (_, _, device) => DeviceManagementPage(device: device),
  );
}

@TypedGoRoute<DeviceDetailsRoute>(
  path: '/devices/:deviceId/details',
  name: 'device-details',
)
class DeviceDetailsRoute extends _AppPageRoute with $DeviceDetailsRoute {
  const DeviceDetailsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        DeviceDetailsPage(device: device);
    return _deviceRecord(context, state, deviceId, 'device-details', page);
  }
}

@TypedGoRoute<DeviceDataRoute>(
  path: '/devices/:deviceId/data',
  name: 'device-data',
)
class DeviceDataRoute extends GoRouteData with $DeviceDataRoute {
  const DeviceDataRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  String redirect(BuildContext context, GoRouterState state) =>
      DeviceDetailsRoute(deviceId: deviceId).location;
}

@TypedGoRoute<CapabilitiesRoute>(
  path: '/devices/:deviceId/capabilities',
  name: 'capabilities',
)
class CapabilitiesRoute extends GoRouteData with $CapabilitiesRoute {
  const CapabilitiesRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  String redirect(BuildContext context, GoRouterState state) =>
      DiagnosticsRoute(deviceId: deviceId).location;
}

@TypedGoRoute<DeviceConnectionRoute>(
  path: '/devices/:deviceId/connection',
  name: 'device-connection',
)
class DeviceConnectionRoute extends _AppPageRoute with $DeviceConnectionRoute {
  const DeviceConnectionRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        DeviceConnectionSettingsPage(device: device);
    return _deviceRecord(context, state, deviceId, 'device-connection', page);
  }
}

@TypedGoRoute<DiagnosticsRoute>(
  path: '/devices/:deviceId/diagnostics',
  name: 'diagnostics',
)
class DiagnosticsRoute extends _AppPageRoute with $DiagnosticsRoute {
  const DiagnosticsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        ConnectionDiagnosticsPage(device: device);
    return _deviceRecord(context, state, deviceId, 'diagnostics', page);
  }
}

@TypedGoRoute<FilesRoute>(path: '/devices/:deviceId/files', name: 'files')
class FilesRoute extends _AppPageRoute with $FilesRoute {
  const FilesRoute({required this.deviceId, this.path = '/sdcard'});
  final String deviceId;
  final String path;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        FilesPage(
          key: ValueKey('files:${device.id}:$path'),
          device: device,
          initialPath: path,
        );
    return _deviceRecord(context, state, deviceId, 'files', page);
  }
}

@TypedGoRoute<FileDetailsRoute>(
  path: '/devices/:deviceId/file',
  name: 'file-details',
)
class FileDetailsRoute extends _AppPageRoute with $FileDetailsRoute {
  const FileDetailsRoute({required this.deviceId, this.path = ''});
  final String deviceId;
  final String path;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final resources = _resources(context);
    Widget page(
      BuildContext context,
      GoRouterState state,
      DeviceSnapshot device,
    ) {
      return RouteResourceView(
        identity: 'file:${device.id}:$path',
        load: () => resources.file(device.id, path),
        builder: (_, file) => file.mime.startsWith('image/')
            ? MediaPreviewPage(device: device, file: file)
            : FileDetailsPage(device: device, file: file),
      );
    }

    return _deviceRecord(context, state, deviceId, 'file-details', page);
  }
}

@TypedGoRoute<FileSearchRoute>(
  path: '/devices/:deviceId/file-search',
  name: 'file-search',
)
class FileSearchRoute extends _AppPageRoute with $FileSearchRoute {
  const FileSearchRoute({
    required this.deviceId,
    this.path = '/sdcard',
    this.query = '',
  });
  final String deviceId;
  final String path;
  final String query;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(
      BuildContext context,
      GoRouterState state,
      DeviceSnapshot device,
    ) => FileSearchPage(
      key: ValueKey('file-search:${device.id}:$path:$query'),
      device: device,
      initialPath: path,
      initialQuery: query,
    );
    return _deviceRecord(context, state, deviceId, 'file-search', page);
  }
}

@TypedGoRoute<AppsRoute>(path: '/devices/:deviceId/apps', name: 'apps')
class AppsRoute extends _AppPageRoute with $AppsRoute {
  const AppsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        DeviceAppsPage(device: device);
    return _deviceRecord(context, state, deviceId, 'apps', page);
  }
}

@TypedGoRoute<GalleryRoute>(path: '/devices/:deviceId/gallery', name: 'gallery')
class GalleryRoute extends _AppPageRoute with $GalleryRoute {
  const GalleryRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        GalleryPage(device: device);
    return _deviceRecord(context, state, deviceId, 'gallery', page);
  }
}

@TypedGoRoute<MediaPreviewRoute>(
  path: '/devices/:deviceId/media',
  name: 'media-preview',
)
class MediaPreviewRoute extends _AppPageRoute with $MediaPreviewRoute {
  const MediaPreviewRoute({required this.deviceId, this.path = ''});
  final String deviceId;
  final String path;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final resources = _resources(context);
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) {
      return RouteResourceView(
        identity: 'media:${device.id}:$path',
        load: () => resources.file(device.id, path),
        builder: (_, file) => MediaPreviewPage(device: device, file: file),
      );
    }

    return _deviceRecord(context, state, deviceId, 'media-preview', page);
  }
}

@TypedGoRoute<NotificationsRoute>(
  path: '/devices/:deviceId/notifications',
  name: 'notifications',
)
class NotificationsRoute extends _AppPageRoute with $NotificationsRoute {
  const NotificationsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        NotificationsPage(device: device);
    return _deviceRecord(context, state, deviceId, 'notifications', page);
  }
}

@TypedGoRoute<CallsRoute>(path: '/devices/:deviceId/calls', name: 'calls')
class CallsRoute extends _AppPageRoute with $CallsRoute {
  const CallsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        CallsPage(device: device);
    return _deviceRecord(context, state, deviceId, 'calls', page);
  }
}

@TypedGoRoute<QualityRoute>(path: '/devices/:deviceId/quality', name: 'quality')
class QualityRoute extends _AppPageRoute with $QualityRoute {
  const QualityRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        ControlSettingsPage(device: device);
    return _deviceRecord(context, state, deviceId, 'quality', page);
  }
}

@TypedGoRoute<SessionToolsRoute>(
  path: '/devices/:deviceId/tools',
  name: 'session-tools',
)
class SessionToolsRoute extends GoRouteData with $SessionToolsRoute {
  const SessionToolsRoute({required this.deviceId, this.sessionId});
  final String deviceId;
  final String? sessionId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  String redirect(BuildContext context, GoRouterState state) =>
      WorkspaceRoute(deviceId: deviceId).location;
}

@TypedGoRoute<SessionsRoute>(
  path: '/devices/:deviceId/sessions',
  name: 'sessions',
)
class SessionsRoute extends GoRouteData with $SessionsRoute {
  const SessionsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  String redirect(BuildContext context, GoRouterState state) =>
      WorkspaceRoute(deviceId: deviceId).location;
}

@TypedGoRoute<RemoteRoute>(path: '/devices/:deviceId/remote', name: 'remote')
class RemoteRoute extends _AppPageRoute with $RemoteRoute {
  const RemoteRoute({
    required this.deviceId,
    this.keyboard = false,
    this.$extra,
  });
  final String deviceId;
  final bool keyboard;
  final Object? $extra;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(
      BuildContext context,
      GoRouterState state,
      DeviceSnapshot device,
    ) =>
        _remoteView(context, state, device, intent: $extra, keyboard: keyboard);
    return _deviceRecord(context, state, deviceId, 'remote', page);
  }
}

@TypedGoRoute<RemoteAppRoute>(
  path: '/devices/:deviceId/apps/:packageName/remote',
  name: 'remote-app',
)
class RemoteAppRoute extends _AppPageRoute with $RemoteAppRoute {
  const RemoteAppRoute({
    required this.deviceId,
    required this.packageName,
    this.keyboard = false,
    this.$extra,
  });
  final String deviceId;
  final String packageName;
  final bool keyboard;
  final Object? $extra;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(
      BuildContext context,
      GoRouterState state,
      DeviceSnapshot device,
    ) => _remoteView(
      context,
      state,
      device,
      intent: $extra,
      keyboard: keyboard,
      packageName: packageName,
    );
    return _deviceRecord(context, state, deviceId, 'remote-app', page);
  }
}

@TypedGoRoute<RemoteSessionRoute>(
  path: '/devices/:deviceId/sessions/:sessionId',
  name: 'remote-session',
)
class RemoteSessionRoute extends _AppPageRoute with $RemoteSessionRoute {
  const RemoteSessionRoute({
    required this.deviceId,
    required this.sessionId,
    this.keyboard = false,
    this.$extra,
  });
  final String deviceId;
  final String sessionId;
  final bool keyboard;
  final RemoteControlIntent? $extra;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final resources = _resources(context);
    Widget page(
      BuildContext context,
      GoRouterState state,
      DeviceSnapshot device,
    ) {
      final id = sessionId;
      return RouteResourceView(
        identity: 'session:${device.id}:$id',
        load: () => resources.session(device.id, id),
        builder: (context, session) => _remoteView(
          context,
          state,
          device,
          session: session,
          keyboard: keyboard,
          action: $extra,
        ),
      );
    }

    return _deviceRecord(context, state, deviceId, 'remote-session', page);
  }
}

@TypedGoRoute<TransferDetailsRoute>(
  path: '/transfers/:taskId',
  name: 'transfer-details',
)
class TransferDetailsRoute extends _AppPageRoute with $TransferDetailsRoute {
  const TransferDetailsRoute({required this.taskId});
  final String taskId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final resources = _resources(context);
    final id = taskId;
    return RouteResourceView(
      identity: 'transfer:$id',
      load: () => resources.transfer(id),
      builder: (_, task) => TransferDetailsPage(task: task),
    );
  }
}

@TypedGoRoute<ScreenshotRoute>(
  path: '/devices/:deviceId/screenshot',
  name: 'screenshot',
)
class ScreenshotRoute extends _AppPageRoute with $ScreenshotRoute {
  const ScreenshotRoute({required this.deviceId, this.$extra});
  final String deviceId;
  final VideoScreenshot? $extra;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    if ($extra == null) {
      return const RouteErrorPage(message: '本次截图信息已失效，请返回手机画面重新截图。');
    }
    return _deviceRecord(
      context,
      state,
      deviceId,
      'screenshot',
      (context, state, device) =>
          ScreenshotPage(device: device, capture: $extra!),
    );
  }
}

@TypedGoRoute<DocumentExportRoute>(
  path: '/transfers/:taskId/export',
  name: 'document-export',
)
class DocumentExportRoute extends _AppPageRoute with $DocumentExportRoute {
  const DocumentExportRoute({required this.taskId, this.partial = false});
  final String taskId;
  final bool partial;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final resources = _resources(context);
    final id = taskId;
    return RouteResourceView(
      identity: 'export:$id',
      load: () => resources.transfer(id),
      builder: (_, task) {
        final localPath =
            (partial ? task.partialLocalPath : task.localPath) ?? '';
        if ((partial ? task.canExportPartial : task.canExport) != true ||
            localPath.isEmpty) {
          return RouteErrorPage(
            message: task.exportReason ?? '当前任务没有可完整保存的本机内容，请在传输中心核对。',
          );
        }
        return DocumentExportPage(
          transferId: id,
          partial: partial,
          localPath: localPath,
          sourceLabel: task.sourceLabel ?? '被控设备',
          name: task.name,
          kind: task.kind.name,
        );
      },
    );
  }
}

@TypedGoRoute<ReceiveContentRoute>(
  path: '/transfers/:taskId/receive',
  name: 'receive-content',
)
class ReceiveContentRoute extends _AppPageRoute with $ReceiveContentRoute {
  const ReceiveContentRoute({
    required this.taskId,
    this.share = false,
    this.$extra,
  });
  final String taskId;
  final bool share;
  final bool? $extra;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final resources = _resources(context);
    return RouteResourceView(
      identity: 'receive:$taskId:$share:${$extra == true}',
      load: () => resources.transfer(taskId),
      builder: (_, task) => ReceiveContentPage(
        task: task,
        share: share,
        openAfterTransfer: $extra == true,
      ),
    );
  }
}

@TypedGoRoute<DocumentImportRoute>(
  path: '/devices/:deviceId/documents/import',
  name: 'document-import',
)
class DocumentImportRoute extends _AppPageRoute with $DocumentImportRoute {
  const DocumentImportRoute({
    required this.deviceId,
    this.destination = '/sdcard/Download',
  });
  final String deviceId;
  final String destination;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(
      BuildContext context,
      GoRouterState state,
      DeviceSnapshot device,
    ) => DocumentImportPage(
      device: device,
      destination: destination,
      onSubmitted: () {
        final router = GoRouter.of(context);
        if (router.canPop()) router.pop(true);
        const TransferCenterRoute().push<void>(context);
      },
    );
    return _deviceRecord(context, state, deviceId, 'document-import', page);
  }
}

@TypedGoRoute<IncomingShareRoute>(
  path: '/sharing/:shareId',
  name: 'incoming-share',
)
class IncomingShareRoute extends _AppPageRoute with $IncomingShareRoute {
  const IncomingShareRoute({required this.shareId});
  final String shareId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final resources = _resources(context);
    final id = shareId;
    return RouteResourceView(
      identity: 'share:$id',
      load: () => resources.share(id),
      builder: (_, share) => IncomingSharePage(share: share),
    );
  }
}

@TypedGoRoute<ShareDirectoryRoute>(
  path: '/devices/:deviceId/share-directory',
  name: 'share-directory',
)
class ShareDirectoryRoute extends _AppPageRoute with $ShareDirectoryRoute {
  const ShareDirectoryRoute({required this.deviceId, this.path = '/sdcard'});
  final String deviceId;
  final String path;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state, DeviceSnapshot device) =>
        FileDirectoryPickerPage(device: device, initialPath: path);
    return _deviceRecord(context, state, deviceId, 'share-directory', page);
  }
}

@TypedGoRoute<AppUpdatesRoute>(path: '/settings/updates', name: 'app-updates')
class AppUpdatesRoute extends _AppPageRoute with $AppUpdatesRoute {
  const AppUpdatesRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const AppUpdatesPage();
}

@TypedGoRoute<AppearanceRoute>(path: '/settings/appearance', name: 'appearance')
class AppearanceRoute extends _AppPageRoute with $AppearanceRoute {
  const AppearanceRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const AppearancePage();
  }
}

@TypedGoRoute<BackgroundRoute>(path: '/settings/background', name: 'background')
class BackgroundRoute extends _AppPageRoute with $BackgroundRoute {
  const BackgroundRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const BackgroundPage();
  }
}

@TypedGoRoute<ActivitiesRoute>(path: '/settings/activities', name: 'activities')
class ActivitiesRoute extends GoRouteData with $ActivitiesRoute {
  const ActivitiesRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  String? redirect(BuildContext context, GoRouterState state) =>
      const DevicesRoute().location;
}

@TypedGoRoute<DataPreferencesRoute>(
  path: '/settings/data',
  name: 'data-preferences',
)
class DataPreferencesRoute extends _AppPageRoute with $DataPreferencesRoute {
  const DataPreferencesRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const DataPreferencesPage();
  }
}

@TypedGoRoute<MediaCacheRoute>(
  path: '/settings/media-cache',
  name: 'media-cache',
)
class MediaCacheRoute extends _AppPageRoute with $MediaCacheRoute {
  const MediaCacheRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const MediaCachePage();
}

@TypedGoRoute<DeviceActivitiesRoute>(
  path: '/devices/:deviceId/activities',
  name: 'device-activities',
)
class DeviceActivitiesRoute extends _AppPageRoute with $DeviceActivitiesRoute {
  const DeviceActivitiesRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) => _deviceRecord(
    context,
    state,
    deviceId,
    'device-activities',
    (_, _, _) => ActivitiesPage(deviceId: deviceId),
  );
}

@TypedGoRoute<AdbIdentityRoute>(path: '/settings/adb-key', name: 'adb-key')
class AdbIdentityRoute extends _AppPageRoute with $AdbIdentityRoute {
  const AdbIdentityRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const AdbIdentityPage();
}

@TypedGoRoute<DeviceIdentityRoute>(
  path: '/devices/:deviceId/adb-key',
  name: 'device-adb-key',
)
class DeviceIdentityRoute extends GoRouteData with $DeviceIdentityRoute {
  const DeviceIdentityRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  String redirect(BuildContext context, GoRouterState state) =>
      DeviceConnectionRoute(deviceId: deviceId).location;
}

@TypedGoRoute<DeviceIpRoute>(
  path: '/devices/:deviceId/convert-ip',
  name: 'device-convert-ip',
)
class DeviceIpRoute extends _AppPageRoute with $DeviceIpRoute {
  const DeviceIpRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) => _deviceRecord(
    context,
    state,
    deviceId,
    'device-convert-ip',
    (_, _, device) => WirelessSetupPage(device: device),
  );
}

@TypedGoRoute<RuntimeLogsRoute>(path: '/settings/logs', name: 'runtime-logs')
class RuntimeLogsRoute extends _AppPageRoute with $RuntimeLogsRoute {
  const RuntimeLogsRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _content;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const RuntimeLogsPage();
}
