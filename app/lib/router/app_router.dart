import 'package:scrcpy_connect/router/remote_control_intent.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/router/route_observers.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/router/route_repository.dart';
import 'package:scrcpy_connect/router/record_route.dart';
import 'package:scrcpy_connect/router/remote_launch_intent.dart';
import 'package:scrcpy_connect/widgets/visible_device_focus.dart';

import 'package:scrcpy_connect/pages/devices/workspace/activities/devices_workspace_activities_page.dart';
import 'package:scrcpy_connect/pages/connection/index/connection_index_page.dart';
import 'package:scrcpy_connect/pages/settings/appearance/settings_appearance_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/apps/devices_workspace_apps_page.dart';
import 'package:scrcpy_connect/pages/settings/background/settings_background_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/calls/devices_workspace_calls_page.dart';
import 'package:scrcpy_connect/pages/devices/details/capabilities/devices_details_capabilities_page.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/settings/data_preferences/settings_data_preferences_page.dart';
import 'package:scrcpy_connect/pages/devices/details/connection_preferences/devices_details_connection_preferences_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/index/devices_index_page.dart';
import 'package:scrcpy_connect/pages/devices/details/diagnostics/devices_details_diagnostics_page.dart';
import 'package:scrcpy_connect/pages/connection/discovery/connection_discovery_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/export/transfers_details_export_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/receive/transfers_details_receive_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/import/devices_workspace_files_import_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/details/devices_workspace_files_details_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/search/devices_workspace_files_search_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/index/devices_workspace_gallery_index_page.dart';
import 'package:scrcpy_connect/pages/home/home_page.dart';
import 'package:scrcpy_connect/pages/incoming_share/incoming_share_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/devices_workspace_gallery_preview_page.dart';
import 'package:scrcpy_connect/pages/settings/media_cache/settings_media_cache_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/reply/devices_workspace_notifications_reply_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/route_error/route_error_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/sessions/tools/devices_workspace_sessions_tools_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/sessions/index/devices_workspace_sessions_index_page.dart';
import 'package:scrcpy_connect/pages/settings/index/settings_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/directory_picker/devices_workspace_files_directory_picker_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/index/transfers_details_index_page.dart';
import 'package:scrcpy_connect/pages/transfers/index/transfers_index_page.dart';

import 'package:scrcpy_connect/pages/settings/adb_identity/settings_adb_identity_page.dart';
import 'package:scrcpy_connect/pages/devices/details/convert_ip/devices_details_convert_ip_page.dart';

part 'app_router.g.dart';

GlobalKey<NavigatorState> _root = GlobalKey<NavigatorState>();
AppController _controller(BuildContext context) => ProviderScope.containerOf(
  context,
  listen: false,
).read(appControllerProvider.notifier);
RouteRepository _records(BuildContext context) => ProviderScope.containerOf(
  context,
  listen: false,
).read(routeRepositoryProvider);

List<RouteBase> typedRoutes(GlobalKey<NavigatorState> root) {
  _root = root;
  return $appRoutes;
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
Widget _deviceRecord(
  BuildContext context,
  GoRouterState state,
  String deviceId,
  String name,
  Widget Function(BuildContext, GoRouterState, Json) build,
) {
  final identity =
      '$name:$deviceId:${state.pathParameters['sessionId'] ?? ''}:${state.pathParameters['packageName'] ?? ''}';
  return RecordRoute(
    key: ValueKey('${state.pageKey.value}:$identity'),
    identity: identity,
    preserveContent: ['remote', 'remote-app', 'remote-session'].contains(name),
    load: () => _records(context).device(deviceId),
    builder: (context, device) =>
        ['remote', 'remote-app', 'remote-session'].contains(name)
        ? build(context, state, device)
        : VisibleDeviceFocus(
            controller: _controller(context),
            deviceId: value(device, 'id'),
            child: build(context, state, device),
          ),
  );
}

Widget _remoteView(
  BuildContext context,
  GoRouterState state,
  Json device, {
  Object? intent,
  bool keyboard = false,
  String? packageName,
  Json? session,
  RemoteControlIntent? action,
}) {
  if (session == null && intent is! RemoteLaunchIntent) {
    return const RouteErrorPage(message: '请从设备工作台明确打开画面。恢复这个位置不会自动创建新的控制会话。');
  }
  return RemotePage(
    key: ValueKey(
      'remote:${state.pageKey.value}:${device['id']}:${state.pathParameters['sessionId'] ?? packageName ?? 'screen'}',
    ),
    controller: _controller(context),
    device: device,
    existingSession: session,
    packageName: packageName,
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
  static const $restorationScopeId = 'home-shell';
  @override
  Page<void> pageBuilder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  ) => _page(
    state,
    HomePage(navigationShell: navigationShell),
    restorationId: 'home-shell-page',
  );
}

class DevicesBranch extends StatefulShellBranchData {
  const DevicesBranch();
  static const $restorationScopeId = 'devices-branch';
}

class TransfersBranch extends StatefulShellBranchData {
  const TransfersBranch();
  static const $restorationScopeId = 'transfers-branch';
}

class SettingsBranch extends StatefulShellBranchData {
  const SettingsBranch();
  static const $restorationScopeId = 'settings-branch';
}

class DevicesRoute extends GoRouteData with $DevicesRoute {
  const DevicesRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      DevicesPage(controller: _controller(context));
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state), restorationId: 'devices-page');
}

class TransfersRoute extends GoRouteData with $TransfersRoute {
  const TransfersRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      TransfersPage(controller: _controller(context), embedded: true);
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state), restorationId: 'transfers-page');
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      SettingsPage(controller: _controller(context), embedded: true);
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state), restorationId: 'settings-page');
}

@TypedGoRoute<RouteErrorRoute>(path: '/unavailable', name: 'route-error')
class RouteErrorRoute extends GoRouteData with $RouteErrorRoute {
  const RouteErrorRoute({this.reason = 'missing-record'});
  final String reason;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext _, GoRouterState state) => RouteErrorPage(
      message: reason == 'missing-session'
          ? '无法识别这个控制会话。请从设备工作台重新选择；不会自动创建新画面。'
          : '页面缺少必要的记录信息，请返回设备列表重新选择。',
    );
    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<TransferCenterRoute>(
  path: '/activity/transfers',
  name: 'transfer-center',
)
class TransferCenterRoute extends GoRouteData with $TransferCenterRoute {
  const TransferCenterRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state) =>
        TransfersPage(controller: controller);
    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<SettingsPageRoute>(path: '/preferences', name: 'settings-page')
class SettingsPageRoute extends GoRouteData with $SettingsPageRoute {
  const SettingsPageRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state) =>
        SettingsPage(controller: controller);
    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<AddDeviceRoute>(path: '/connection/add', name: 'add-device')
class AddDeviceRoute extends GoRouteData with $AddDeviceRoute {
  const AddDeviceRoute({this.deviceId});
  final String? deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    final records = _records(context);
    Widget page(BuildContext _, GoRouterState state) {
      final id = deviceId;
      return id == null
          ? AddDevicePage(controller: controller)
          : RecordRoute(
              identity: 'reauthorize:$id',
              load: () => records.device(id),
              builder: (_, device) =>
                  AddDevicePage(controller: controller, initialDevice: device),
            );
    }

    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<WirelessGuideRoute>(
  path: '/connection/wireless',
  name: 'wireless-guide',
)
class WirelessGuideRoute extends GoRouteData with $WirelessGuideRoute {
  const WirelessGuideRoute({this.deviceId, this.address = ''});
  final String? deviceId;
  final String address;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    final records = _records(context);
    Widget page(BuildContext _, GoRouterState state) {
      final id = deviceId;
      Widget guide([Json? record]) => AddDevicePage(
        initialDevice: record,
        controller: controller,
        deviceId: id,
        address: address,
      );
      return id == null
          ? guide()
          : RecordRoute(
              identity: 'wireless:$id',
              load: () => records.device(id),
              builder: (_, device) => guide(device),
            );
    }

    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<ConnectionFormRoute>(
  path: '/connection/form',
  name: 'connection-form',
)
class ConnectionFormRoute extends GoRouteData with $ConnectionFormRoute {
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
    final controller = _controller(context);
    final records = _records(context);
    Widget page(BuildContext _, GoRouterState state) {
      Widget form([Json? record]) => AddDevicePage(
        key: state.pageKey,
        controller: controller,
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
          : RecordRoute(
              identity: 'connection:$id',
              load: () => records.device(id),
              builder: (_, record) => form(record),
            );
    }

    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<DiscoveryRoute>(path: '/connection/discovery', name: 'discovery')
class DiscoveryRoute extends GoRouteData with $DiscoveryRoute {
  const DiscoveryRoute({this.selection = false});
  final bool selection;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state) =>
        DiscoveryPage(controller: controller, returnSelection: selection);
    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<UsbGuideRoute>(path: '/connection/usb', name: 'usb-guide')
class UsbGuideRoute extends GoRouteData with $UsbGuideRoute {
  const UsbGuideRoute({this.deviceId});
  final String? deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    final id = deviceId;
    Widget page([Json? record]) => AddDevicePage(
      controller: controller,
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

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<QrPairRoute>(path: '/connection/qr', name: 'qr-pair')
class QrPairRoute extends GoRouteData with $QrPairRoute {
  const QrPairRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state) =>
        AddDevicePage(controller: controller, initialMode: AddDeviceMode.qr);
    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<WorkspaceRoute>(path: '/devices/:deviceId', name: 'workspace')
class WorkspaceRoute extends GoRouteData with $WorkspaceRoute {
  const WorkspaceRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        DeviceWorkspacePage(controller: controller, device: device);
    return _deviceRecord(context, state, deviceId, 'workspace', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<DeviceDetailsRoute>(
  path: '/devices/:deviceId/details',
  name: 'device-details',
)
class DeviceDetailsRoute extends GoRouteData with $DeviceDetailsRoute {
  const DeviceDetailsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  String redirect(BuildContext context, GoRouterState state) =>
      WorkspaceRoute(deviceId: deviceId).location;
}

@TypedGoRoute<DeviceConnectionRoute>(
  path: '/devices/:deviceId/connection',
  name: 'device-connection',
)
class DeviceConnectionRoute extends GoRouteData with $DeviceConnectionRoute {
  const DeviceConnectionRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        DeviceConnectionPreferencesPage(controller: controller, device: device);
    return _deviceRecord(context, state, deviceId, 'device-connection', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<CapabilitiesRoute>(
  path: '/devices/:deviceId/capabilities',
  name: 'capabilities',
)
class CapabilitiesRoute extends GoRouteData with $CapabilitiesRoute {
  const CapabilitiesRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        CapabilitiesPage(controller: controller, device: device);
    return _deviceRecord(context, state, deviceId, 'capabilities', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<DiagnosticsRoute>(
  path: '/devices/:deviceId/diagnostics',
  name: 'diagnostics',
)
class DiagnosticsRoute extends GoRouteData with $DiagnosticsRoute {
  const DiagnosticsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        DiagnosticsPage(controller: controller, device: device);
    return _deviceRecord(context, state, deviceId, 'diagnostics', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<FilesRoute>(path: '/devices/:deviceId/files', name: 'files')
class FilesRoute extends GoRouteData with $FilesRoute {
  const FilesRoute({required this.deviceId, this.path = '/sdcard'});
  final String deviceId;
  final String path;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) => FilesPage(
      key: ValueKey('files:${device['id']}:$path'),
      controller: controller,
      device: device,
      initialPath: path,
    );
    return _deviceRecord(context, state, deviceId, 'files', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<FileDetailsRoute>(
  path: '/devices/:deviceId/file',
  name: 'file-details',
)
class FileDetailsRoute extends GoRouteData with $FileDetailsRoute {
  const FileDetailsRoute({required this.deviceId, this.path = ''});
  final String deviceId;
  final String path;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    final records = _records(context);
    Widget page(BuildContext context, GoRouterState state, Json device) {
      return RecordRoute(
        identity: 'file:${device['id']}:$path',
        load: () => records.file(value(device, 'id'), path),
        builder: (_, file) =>
            FileDetailsPage(controller: controller, device: device, file: file),
      );
    }

    return _deviceRecord(context, state, deviceId, 'file-details', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<FileSearchRoute>(
  path: '/devices/:deviceId/file-search',
  name: 'file-search',
)
class FileSearchRoute extends GoRouteData with $FileSearchRoute {
  const FileSearchRoute({
    required this.deviceId,
    this.path = '/sdcard',
    this.query = '',
  });
  final String deviceId;
  final String path;
  final String query;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    Widget page(BuildContext context, GoRouterState state, Json device) =>
        FileSearchPage(
          key: ValueKey('file-search:${device['id']}:$path:$query'),
          controller: _controller(context),
          device: device,
          initialPath: path,
          initialQuery: query,
        );
    return _deviceRecord(context, state, deviceId, 'file-search', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<AppsRoute>(path: '/devices/:deviceId/apps', name: 'apps')
class AppsRoute extends GoRouteData with $AppsRoute {
  const AppsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        AppsPage(controller: controller, device: device);
    return _deviceRecord(context, state, deviceId, 'apps', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<GalleryRoute>(path: '/devices/:deviceId/gallery', name: 'gallery')
class GalleryRoute extends GoRouteData with $GalleryRoute {
  const GalleryRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        GalleryPage(controller: controller, device: device);
    return _deviceRecord(context, state, deviceId, 'gallery', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<MediaPreviewRoute>(
  path: '/devices/:deviceId/media',
  name: 'media-preview',
)
class MediaPreviewRoute extends GoRouteData with $MediaPreviewRoute {
  const MediaPreviewRoute({required this.deviceId, this.path = ''});
  final String deviceId;
  final String path;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    final records = _records(context);
    Widget page(BuildContext _, GoRouterState state, Json device) {
      return RecordRoute(
        identity: 'media:${device['id']}:$path',
        load: () => records.file(value(device, 'id'), path),
        builder: (_, file) => MediaPreviewPage(
          controller: controller,
          device: device,
          file: file,
        ),
      );
    }

    return _deviceRecord(context, state, deviceId, 'media-preview', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<NotificationsRoute>(
  path: '/devices/:deviceId/notifications',
  name: 'notifications',
)
class NotificationsRoute extends GoRouteData with $NotificationsRoute {
  const NotificationsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        NotificationsPage(controller: controller, device: device);
    return _deviceRecord(context, state, deviceId, 'notifications', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<NotificationReplyRoute>(
  path: '/devices/:deviceId/notifications/:notificationId/reply',
  name: 'notification-reply',
)
class NotificationReplyRoute extends GoRouteData with $NotificationReplyRoute {
  const NotificationReplyRoute({
    required this.deviceId,
    required this.notificationId,
  });
  final String deviceId;
  final String notificationId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    final records = _records(context);
    Widget page(BuildContext _, GoRouterState state, Json device) {
      final id = notificationId;
      return RecordRoute(
        identity: 'notification:${device['id']}:$id',
        load: () => records.notificationReply(value(device, 'id'), id),
        builder: (_, notification) => NotificationReplyPage(
          controller: controller,
          device: device,
          notification: notification,
        ),
      );
    }

    return _deviceRecord(context, state, deviceId, 'notification-reply', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<CallsRoute>(path: '/devices/:deviceId/calls', name: 'calls')
class CallsRoute extends GoRouteData with $CallsRoute {
  const CallsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        CallsPage(controller: controller, device: device);
    return _deviceRecord(context, state, deviceId, 'calls', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<QualityRoute>(path: '/devices/:deviceId/quality', name: 'quality')
class QualityRoute extends GoRouteData with $QualityRoute {
  const QualityRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        QualityPage(controller: controller, device: device);
    return _deviceRecord(context, state, deviceId, 'quality', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<SessionToolsRoute>(
  path: '/devices/:deviceId/tools',
  name: 'session-tools',
)
class SessionToolsRoute extends GoRouteData with $SessionToolsRoute {
  const SessionToolsRoute({required this.deviceId, this.sessionId});
  final String deviceId;
  final String? sessionId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        SessionToolsPage(
          controller: controller,
          device: device,
          sessionId: sessionId,
        );
    return _deviceRecord(context, state, deviceId, 'session-tools', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<SessionsRoute>(
  path: '/devices/:deviceId/sessions',
  name: 'sessions',
)
class SessionsRoute extends GoRouteData with $SessionsRoute {
  const SessionsRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        SessionsPage(controller: controller, device: device);
    return _deviceRecord(context, state, deviceId, 'sessions', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<RemoteRoute>(path: '/devices/:deviceId/remote', name: 'remote')
class RemoteRoute extends GoRouteData with $RemoteRoute {
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
    Widget page(BuildContext context, GoRouterState state, Json device) =>
        _remoteView(context, state, device, intent: $extra, keyboard: keyboard);
    return _deviceRecord(context, state, deviceId, 'remote', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<RemoteAppRoute>(
  path: '/devices/:deviceId/apps/:packageName/remote',
  name: 'remote-app',
)
class RemoteAppRoute extends GoRouteData with $RemoteAppRoute {
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
    Widget page(BuildContext context, GoRouterState state, Json device) =>
        _remoteView(
          context,
          state,
          device,
          intent: $extra,
          keyboard: keyboard,
          packageName: packageName,
        );
    return _deviceRecord(context, state, deviceId, 'remote-app', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<RemoteSessionRoute>(
  path: '/devices/:deviceId/sessions/:sessionId',
  name: 'remote-session',
)
class RemoteSessionRoute extends GoRouteData with $RemoteSessionRoute {
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
    final records = _records(context);
    Widget page(BuildContext context, GoRouterState state, Json device) {
      final id = sessionId;
      return RecordRoute(
        identity: 'session:${device['id']}:$id',
        load: () => records.session(value(device, 'id'), id),
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

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<TransferDetailsRoute>(
  path: '/transfers/:taskId',
  name: 'transfer-details',
)
class TransferDetailsRoute extends GoRouteData with $TransferDetailsRoute {
  const TransferDetailsRoute({required this.taskId});
  final String taskId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    final records = _records(context);
    Widget page(BuildContext _, GoRouterState state) {
      final id = taskId;
      return RecordRoute(
        identity: 'transfer:$id',
        load: () => records.transfer(id),
        builder: (_, task) =>
            TransferDetailsPage(controller: controller, task: task),
      );
    }

    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<DocumentExportRoute>(
  path: '/transfers/:taskId/export',
  name: 'document-export',
)
class DocumentExportRoute extends GoRouteData with $DocumentExportRoute {
  const DocumentExportRoute({required this.taskId, this.partial = false});
  final String taskId;
  final bool partial;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    final records = _records(context);
    Widget page(BuildContext _, GoRouterState state) {
      final id = taskId;
      return RecordRoute(
        identity: 'export:$id',
        load: () => records.transfer(id),
        builder: (_, task) {
          final localPath = value(
            task,
            partial ? 'partialLocalPath' : 'localPath',
          );
          if ((partial ? task['canExportPartial'] : task['canExport']) !=
                  true ||
              localPath.isEmpty) {
            return RouteErrorPage(
              message: value(
                task,
                'exportReason',
                '当前任务没有可完整保存的本机内容，请在传输中心核对。',
              ),
            );
          }
          return DocumentExportPage(
            controller: controller,
            transferId: id,
            partial: partial,
            localPath: localPath,
            name: value(task, 'name', '取回的文件'),
            kind: task['kind'] == 'directory' ? 'directory' : 'file',
          );
        },
      );
    }

    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<ReceiveContentRoute>(
  path: '/transfers/:taskId/receive',
  name: 'receive-content',
)
class ReceiveContentRoute extends GoRouteData with $ReceiveContentRoute {
  const ReceiveContentRoute({required this.taskId, this.share = false});
  final String taskId;
  final bool share;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    final records = _records(context);
    return RecordRoute(
      identity: 'receive:$taskId:$share',
      load: () => records.transfer(taskId),
      builder: (_, task) =>
          ReceiveContentPage(controller: controller, task: task, share: share),
    );
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<DocumentImportRoute>(
  path: '/devices/:deviceId/documents/import',
  name: 'document-import',
)
class DocumentImportRoute extends GoRouteData with $DocumentImportRoute {
  const DocumentImportRoute({
    required this.deviceId,
    this.destination = '/sdcard/Download',
  });
  final String deviceId;
  final String destination;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext context, GoRouterState state, Json device) =>
        DocumentImportPage(
          controller: controller,
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

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<IncomingShareRoute>(
  path: '/sharing/:shareId',
  name: 'incoming-share',
)
class IncomingShareRoute extends GoRouteData with $IncomingShareRoute {
  const IncomingShareRoute({required this.shareId});
  final String shareId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    final records = _records(context);
    Widget page(BuildContext _, GoRouterState state) {
      final id = shareId;
      return RecordRoute(
        identity: 'share:$id',
        load: () => records.share(id),
        builder: (_, share) =>
            IncomingSharePage(controller: controller, share: share),
      );
    }

    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<ShareDirectoryRoute>(
  path: '/devices/:deviceId/share-directory',
  name: 'share-directory',
)
class ShareDirectoryRoute extends GoRouteData with $ShareDirectoryRoute {
  const ShareDirectoryRoute({required this.deviceId, this.path = '/sdcard'});
  final String deviceId;
  final String path;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state, Json device) =>
        ShareDirectoryPickerPage(
          controller: controller,
          device: device,
          initialPath: path,
        );
    return _deviceRecord(context, state, deviceId, 'share-directory', page);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<AppearanceRoute>(path: '/settings/appearance', name: 'appearance')
class AppearanceRoute extends GoRouteData with $AppearanceRoute {
  const AppearanceRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state) =>
        AppearancePage(controller: controller);
    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<BackgroundRoute>(path: '/settings/background', name: 'background')
class BackgroundRoute extends GoRouteData with $BackgroundRoute {
  const BackgroundRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state) =>
        BackgroundPage(controller: controller);
    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<ActivitiesRoute>(path: '/settings/activities', name: 'activities')
class ActivitiesRoute extends GoRouteData with $ActivitiesRoute {
  const ActivitiesRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  String? redirect(BuildContext context, GoRouterState state) =>
      const DevicesRoute().location;
}

@TypedGoRoute<DataPreferencesRoute>(
  path: '/settings/data',
  name: 'data-preferences',
)
class DataPreferencesRoute extends GoRouteData with $DataPreferencesRoute {
  const DataPreferencesRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final controller = _controller(context);
    Widget page(BuildContext _, GoRouterState state) =>
        DataPreferencesPage(controller: controller);
    return page(context, state);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<MediaCacheRoute>(
  path: '/settings/media-cache',
  name: 'media-cache',
)
class MediaCacheRoute extends GoRouteData with $MediaCacheRoute {
  const MediaCacheRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      MediaCachePage(controller: _controller(context));
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<DeviceActivitiesRoute>(
  path: '/devices/:deviceId/activities',
  name: 'device-activities',
)
class DeviceActivitiesRoute extends GoRouteData with $DeviceActivitiesRoute {
  const DeviceActivitiesRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) => _deviceRecord(
    context,
    state,
    deviceId,
    'device-activities',
    (_, _, _) =>
        ActivitiesPage(controller: _controller(context), deviceId: deviceId),
  );
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<AdbIdentityRoute>(path: '/settings/adb-key', name: 'adb-key')
class AdbIdentityRoute extends GoRouteData with $AdbIdentityRoute {
  const AdbIdentityRoute();
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      AdbIdentityPage(controller: _controller(context));
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<DeviceIdentityRoute>(
  path: '/devices/:deviceId/adb-key',
  name: 'device-adb-key',
)
class DeviceIdentityRoute extends GoRouteData with $DeviceIdentityRoute {
  const DeviceIdentityRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) => _deviceRecord(
    context,
    state,
    deviceId,
    'device-adb-key',
    (_, _, device) =>
        AdbIdentityPage(controller: _controller(context), device: device),
  );
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}

@TypedGoRoute<DeviceIpRoute>(
  path: '/devices/:deviceId/convert-ip',
  name: 'device-convert-ip',
)
class DeviceIpRoute extends GoRouteData with $DeviceIpRoute {
  const DeviceIpRoute({required this.deviceId});
  final String deviceId;
  static GlobalKey<NavigatorState> get $parentNavigatorKey => _root;
  @override
  Widget build(BuildContext context, GoRouterState state) => _deviceRecord(
    context,
    state,
    deviceId,
    'device-convert-ip',
    (_, _, device) =>
        DeviceConvertIpPage(controller: _controller(context), device: device),
  );
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _page(state, build(context, state));
}
