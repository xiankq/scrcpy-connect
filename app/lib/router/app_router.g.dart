// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'app_router.dart';

// **************************************************************************
// GoRouterGenerator
// **************************************************************************

List<RouteBase> get $appRoutes => [
  $rootRoute,
  $homeShellRoute,
  $routeErrorRoute,
  $transferCenterRoute,
  $settingsPageRoute,
  $addDeviceRoute,
  $wirelessGuideRoute,
  $connectionFormRoute,
  $discoveryRoute,
  $usbGuideRoute,
  $qrPairRoute,
  $workspaceRoute,
  $deviceDetailsRoute,
  $deviceConnectionRoute,
  $capabilitiesRoute,
  $diagnosticsRoute,
  $filesRoute,
  $fileDetailsRoute,
  $fileSearchRoute,
  $appsRoute,
  $galleryRoute,
  $mediaPreviewRoute,
  $notificationsRoute,
  $notificationReplyRoute,
  $callsRoute,
  $deviceDataRoute,
  $qualityRoute,
  $sessionToolsRoute,
  $sessionsRoute,
  $remoteRoute,
  $remoteAppRoute,
  $remoteSessionRoute,
  $transferDetailsRoute,
  $documentExportRoute,
  $receiveContentRoute,
  $documentImportRoute,
  $incomingShareRoute,
  $shareDirectoryRoute,
  $appearanceRoute,
  $backgroundRoute,
  $activitiesRoute,
  $dataPreferencesRoute,
  $mediaCacheRoute,
  $deviceActivitiesRoute,
  $adbIdentityRoute,
  $deviceIdentityRoute,
  $deviceIpRoute,
];

RouteBase get $rootRoute => GoRouteData.$route(
  path: '/',
  hasOverriddenOnExit: false,
  factory: $RootRoute._fromState,
);

mixin $RootRoute on GoRouteData {
  static RootRoute _fromState(GoRouterState state) => const RootRoute();

  @override
  String get location => GoRouteData.$location('/');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $homeShellRoute => StatefulShellRouteData.$route(
  restorationScopeId: HomeShellRoute.$restorationScopeId,
  factory: $HomeShellRouteExtension._fromState,
  branches: [
    StatefulShellBranchData.$branch(
      restorationScopeId: DevicesBranch.$restorationScopeId,
      routes: [
        GoRouteData.$route(
          path: '/devices',
          name: 'devices',
          hasOverriddenOnExit: false,
          factory: $DevicesRoute._fromState,
        ),
      ],
    ),
    StatefulShellBranchData.$branch(
      restorationScopeId: TransfersBranch.$restorationScopeId,
      routes: [
        GoRouteData.$route(
          path: '/transfers',
          name: 'transfers',
          hasOverriddenOnExit: false,
          factory: $TransfersRoute._fromState,
        ),
      ],
    ),
    StatefulShellBranchData.$branch(
      restorationScopeId: SettingsBranch.$restorationScopeId,
      routes: [
        GoRouteData.$route(
          path: '/settings',
          name: 'settings',
          hasOverriddenOnExit: false,
          factory: $SettingsRoute._fromState,
        ),
      ],
    ),
  ],
);

extension $HomeShellRouteExtension on HomeShellRoute {
  static HomeShellRoute _fromState(GoRouterState state) =>
      const HomeShellRoute();
}

mixin $DevicesRoute on GoRouteData {
  static DevicesRoute _fromState(GoRouterState state) => const DevicesRoute();

  @override
  String get location => GoRouteData.$location('/devices');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $TransfersRoute on GoRouteData {
  static TransfersRoute _fromState(GoRouterState state) =>
      const TransfersRoute();

  @override
  String get location => GoRouteData.$location('/transfers');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $SettingsRoute on GoRouteData {
  static SettingsRoute _fromState(GoRouterState state) => const SettingsRoute();

  @override
  String get location => GoRouteData.$location('/settings');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $routeErrorRoute => GoRouteData.$route(
  path: '/unavailable',
  name: 'route-error',
  hasOverriddenOnExit: false,
  parentNavigatorKey: RouteErrorRoute.$parentNavigatorKey,
  factory: $RouteErrorRoute._fromState,
);

mixin $RouteErrorRoute on GoRouteData {
  static RouteErrorRoute _fromState(GoRouterState state) => RouteErrorRoute(
    reason: state.uri.queryParameters['reason'] ?? 'missing-record',
  );

  RouteErrorRoute get _self => this as RouteErrorRoute;

  @override
  String get location => GoRouteData.$location(
    '/unavailable',
    queryParams: {if (_self.reason != 'missing-record') 'reason': _self.reason},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $transferCenterRoute => GoRouteData.$route(
  path: '/activity/transfers',
  name: 'transfer-center',
  hasOverriddenOnExit: false,
  parentNavigatorKey: TransferCenterRoute.$parentNavigatorKey,
  factory: $TransferCenterRoute._fromState,
);

mixin $TransferCenterRoute on GoRouteData {
  static TransferCenterRoute _fromState(GoRouterState state) =>
      const TransferCenterRoute();

  @override
  String get location => GoRouteData.$location('/activity/transfers');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $settingsPageRoute => GoRouteData.$route(
  path: '/preferences',
  name: 'settings-page',
  hasOverriddenOnExit: false,
  parentNavigatorKey: SettingsPageRoute.$parentNavigatorKey,
  factory: $SettingsPageRoute._fromState,
);

mixin $SettingsPageRoute on GoRouteData {
  static SettingsPageRoute _fromState(GoRouterState state) =>
      const SettingsPageRoute();

  @override
  String get location => GoRouteData.$location('/preferences');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $addDeviceRoute => GoRouteData.$route(
  path: '/connection/add',
  name: 'add-device',
  hasOverriddenOnExit: false,
  parentNavigatorKey: AddDeviceRoute.$parentNavigatorKey,
  factory: $AddDeviceRoute._fromState,
);

mixin $AddDeviceRoute on GoRouteData {
  static AddDeviceRoute _fromState(GoRouterState state) =>
      AddDeviceRoute(deviceId: state.uri.queryParameters['device-id']);

  AddDeviceRoute get _self => this as AddDeviceRoute;

  @override
  String get location => GoRouteData.$location(
    '/connection/add',
    queryParams: {if (_self.deviceId != null) 'device-id': _self.deviceId},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $wirelessGuideRoute => GoRouteData.$route(
  path: '/connection/wireless',
  name: 'wireless-guide',
  hasOverriddenOnExit: false,
  parentNavigatorKey: WirelessGuideRoute.$parentNavigatorKey,
  factory: $WirelessGuideRoute._fromState,
);

mixin $WirelessGuideRoute on GoRouteData {
  static WirelessGuideRoute _fromState(GoRouterState state) =>
      WirelessGuideRoute(
        deviceId: state.uri.queryParameters['device-id'],
        address: state.uri.queryParameters['address'] ?? '',
      );

  WirelessGuideRoute get _self => this as WirelessGuideRoute;

  @override
  String get location => GoRouteData.$location(
    '/connection/wireless',
    queryParams: {
      if (_self.deviceId != null) 'device-id': _self.deviceId,
      if (_self.address != '') 'address': _self.address,
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $connectionFormRoute => GoRouteData.$route(
  path: '/connection/form',
  name: 'connection-form',
  hasOverriddenOnExit: false,
  parentNavigatorKey: ConnectionFormRoute.$parentNavigatorKey,
  factory: $ConnectionFormRoute._fromState,
);

mixin $ConnectionFormRoute on GoRouteData {
  static ConnectionFormRoute _fromState(GoRouterState state) =>
      ConnectionFormRoute(
        deviceId: state.uri.queryParameters['device-id'],
        address: state.uri.queryParameters['address'] ?? '',
        port: state.uri.queryParameters['port'] ?? '',
        pairing:
            _$convertMapValue(
              'pairing',
              state.uri.queryParameters,
              _$boolConverter,
            ) ??
            false,
        transport: _$convertMapValue(
          'transport',
          state.uri.queryParameters,
          _$ConnectionTransportEnumMap._$fromName,
        ),
      );

  ConnectionFormRoute get _self => this as ConnectionFormRoute;

  @override
  String get location => GoRouteData.$location(
    '/connection/form',
    queryParams: {
      if (_self.deviceId != null) 'device-id': _self.deviceId,
      if (_self.address != '') 'address': _self.address,
      if (_self.port != '') 'port': _self.port,
      if (_self.pairing != false) 'pairing': _self.pairing.toString(),
      if (_self.transport != null)
        'transport': _$ConnectionTransportEnumMap[_self.transport!],
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

const _$ConnectionTransportEnumMap = {
  ConnectionTransport.tls: 'tls',
  ConnectionTransport.tcp: 'tcp',
};

T? _$convertMapValue<T>(
  String key,
  Map<String, String> map,
  T? Function(String) converter,
) {
  final value = map[key];
  return value == null ? null : converter(value);
}

bool _$boolConverter(String value) {
  switch (value) {
    case 'true':
      return true;
    case 'false':
      return false;
    default:
      throw UnsupportedError('Cannot convert "$value" into a bool.');
  }
}

extension<T extends Enum> on Map<T, String> {
  T? _$fromName(String? value) =>
      entries.where((element) => element.value == value).firstOrNull?.key;
}

RouteBase get $discoveryRoute => GoRouteData.$route(
  path: '/connection/discovery',
  name: 'discovery',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DiscoveryRoute.$parentNavigatorKey,
  factory: $DiscoveryRoute._fromState,
);

mixin $DiscoveryRoute on GoRouteData {
  static DiscoveryRoute _fromState(GoRouterState state) => DiscoveryRoute(
    selection:
        _$convertMapValue(
          'selection',
          state.uri.queryParameters,
          _$boolConverter,
        ) ??
        false,
  );

  DiscoveryRoute get _self => this as DiscoveryRoute;

  @override
  String get location => GoRouteData.$location(
    '/connection/discovery',
    queryParams: {
      if (_self.selection != false) 'selection': _self.selection.toString(),
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $usbGuideRoute => GoRouteData.$route(
  path: '/connection/usb',
  name: 'usb-guide',
  hasOverriddenOnExit: false,
  parentNavigatorKey: UsbGuideRoute.$parentNavigatorKey,
  factory: $UsbGuideRoute._fromState,
);

mixin $UsbGuideRoute on GoRouteData {
  static UsbGuideRoute _fromState(GoRouterState state) =>
      UsbGuideRoute(deviceId: state.uri.queryParameters['device-id']);

  UsbGuideRoute get _self => this as UsbGuideRoute;

  @override
  String get location => GoRouteData.$location(
    '/connection/usb',
    queryParams: {if (_self.deviceId != null) 'device-id': _self.deviceId},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $qrPairRoute => GoRouteData.$route(
  path: '/connection/qr',
  name: 'qr-pair',
  hasOverriddenOnExit: false,
  parentNavigatorKey: QrPairRoute.$parentNavigatorKey,
  factory: $QrPairRoute._fromState,
);

mixin $QrPairRoute on GoRouteData {
  static QrPairRoute _fromState(GoRouterState state) => const QrPairRoute();

  @override
  String get location => GoRouteData.$location('/connection/qr');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $workspaceRoute => GoRouteData.$route(
  path: '/devices/:deviceId',
  name: 'workspace',
  hasOverriddenOnExit: false,
  parentNavigatorKey: WorkspaceRoute.$parentNavigatorKey,
  factory: $WorkspaceRoute._fromState,
);

mixin $WorkspaceRoute on GoRouteData {
  static WorkspaceRoute _fromState(GoRouterState state) =>
      WorkspaceRoute(deviceId: state.pathParameters['deviceId']!);

  WorkspaceRoute get _self => this as WorkspaceRoute;

  @override
  String get location =>
      GoRouteData.$location('/devices/${Uri.encodeComponent(_self.deviceId)}');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $deviceDetailsRoute => GoRouteData.$route(
  path: '/devices/:deviceId/details',
  name: 'device-details',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DeviceDetailsRoute.$parentNavigatorKey,
  factory: $DeviceDetailsRoute._fromState,
);

mixin $DeviceDetailsRoute on GoRouteData {
  static DeviceDetailsRoute _fromState(GoRouterState state) =>
      DeviceDetailsRoute(deviceId: state.pathParameters['deviceId']!);

  DeviceDetailsRoute get _self => this as DeviceDetailsRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/details',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $deviceConnectionRoute => GoRouteData.$route(
  path: '/devices/:deviceId/connection',
  name: 'device-connection',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DeviceConnectionRoute.$parentNavigatorKey,
  factory: $DeviceConnectionRoute._fromState,
);

mixin $DeviceConnectionRoute on GoRouteData {
  static DeviceConnectionRoute _fromState(GoRouterState state) =>
      DeviceConnectionRoute(deviceId: state.pathParameters['deviceId']!);

  DeviceConnectionRoute get _self => this as DeviceConnectionRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/connection',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $capabilitiesRoute => GoRouteData.$route(
  path: '/devices/:deviceId/capabilities',
  name: 'capabilities',
  hasOverriddenOnExit: false,
  parentNavigatorKey: CapabilitiesRoute.$parentNavigatorKey,
  factory: $CapabilitiesRoute._fromState,
);

mixin $CapabilitiesRoute on GoRouteData {
  static CapabilitiesRoute _fromState(GoRouterState state) =>
      CapabilitiesRoute(deviceId: state.pathParameters['deviceId']!);

  CapabilitiesRoute get _self => this as CapabilitiesRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/capabilities',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $diagnosticsRoute => GoRouteData.$route(
  path: '/devices/:deviceId/diagnostics',
  name: 'diagnostics',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DiagnosticsRoute.$parentNavigatorKey,
  factory: $DiagnosticsRoute._fromState,
);

mixin $DiagnosticsRoute on GoRouteData {
  static DiagnosticsRoute _fromState(GoRouterState state) =>
      DiagnosticsRoute(deviceId: state.pathParameters['deviceId']!);

  DiagnosticsRoute get _self => this as DiagnosticsRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/diagnostics',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $filesRoute => GoRouteData.$route(
  path: '/devices/:deviceId/files',
  name: 'files',
  hasOverriddenOnExit: false,
  parentNavigatorKey: FilesRoute.$parentNavigatorKey,
  factory: $FilesRoute._fromState,
);

mixin $FilesRoute on GoRouteData {
  static FilesRoute _fromState(GoRouterState state) => FilesRoute(
    deviceId: state.pathParameters['deviceId']!,
    path: state.uri.queryParameters['path'] ?? '/sdcard',
  );

  FilesRoute get _self => this as FilesRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/files',
    queryParams: {if (_self.path != '/sdcard') 'path': _self.path},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $fileDetailsRoute => GoRouteData.$route(
  path: '/devices/:deviceId/file',
  name: 'file-details',
  hasOverriddenOnExit: false,
  parentNavigatorKey: FileDetailsRoute.$parentNavigatorKey,
  factory: $FileDetailsRoute._fromState,
);

mixin $FileDetailsRoute on GoRouteData {
  static FileDetailsRoute _fromState(GoRouterState state) => FileDetailsRoute(
    deviceId: state.pathParameters['deviceId']!,
    path: state.uri.queryParameters['path'] ?? '',
  );

  FileDetailsRoute get _self => this as FileDetailsRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/file',
    queryParams: {if (_self.path != '') 'path': _self.path},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $fileSearchRoute => GoRouteData.$route(
  path: '/devices/:deviceId/file-search',
  name: 'file-search',
  hasOverriddenOnExit: false,
  parentNavigatorKey: FileSearchRoute.$parentNavigatorKey,
  factory: $FileSearchRoute._fromState,
);

mixin $FileSearchRoute on GoRouteData {
  static FileSearchRoute _fromState(GoRouterState state) => FileSearchRoute(
    deviceId: state.pathParameters['deviceId']!,
    path: state.uri.queryParameters['path'] ?? '/sdcard',
    query: state.uri.queryParameters['query'] ?? '',
  );

  FileSearchRoute get _self => this as FileSearchRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/file-search',
    queryParams: {
      if (_self.path != '/sdcard') 'path': _self.path,
      if (_self.query != '') 'query': _self.query,
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $appsRoute => GoRouteData.$route(
  path: '/devices/:deviceId/apps',
  name: 'apps',
  hasOverriddenOnExit: false,
  parentNavigatorKey: AppsRoute.$parentNavigatorKey,
  factory: $AppsRoute._fromState,
);

mixin $AppsRoute on GoRouteData {
  static AppsRoute _fromState(GoRouterState state) =>
      AppsRoute(deviceId: state.pathParameters['deviceId']!);

  AppsRoute get _self => this as AppsRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/apps',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $galleryRoute => GoRouteData.$route(
  path: '/devices/:deviceId/gallery',
  name: 'gallery',
  hasOverriddenOnExit: false,
  parentNavigatorKey: GalleryRoute.$parentNavigatorKey,
  factory: $GalleryRoute._fromState,
);

mixin $GalleryRoute on GoRouteData {
  static GalleryRoute _fromState(GoRouterState state) =>
      GalleryRoute(deviceId: state.pathParameters['deviceId']!);

  GalleryRoute get _self => this as GalleryRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/gallery',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $mediaPreviewRoute => GoRouteData.$route(
  path: '/devices/:deviceId/media',
  name: 'media-preview',
  hasOverriddenOnExit: false,
  parentNavigatorKey: MediaPreviewRoute.$parentNavigatorKey,
  factory: $MediaPreviewRoute._fromState,
);

mixin $MediaPreviewRoute on GoRouteData {
  static MediaPreviewRoute _fromState(GoRouterState state) => MediaPreviewRoute(
    deviceId: state.pathParameters['deviceId']!,
    path: state.uri.queryParameters['path'] ?? '',
  );

  MediaPreviewRoute get _self => this as MediaPreviewRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/media',
    queryParams: {if (_self.path != '') 'path': _self.path},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $notificationsRoute => GoRouteData.$route(
  path: '/devices/:deviceId/notifications',
  name: 'notifications',
  hasOverriddenOnExit: false,
  parentNavigatorKey: NotificationsRoute.$parentNavigatorKey,
  factory: $NotificationsRoute._fromState,
);

mixin $NotificationsRoute on GoRouteData {
  static NotificationsRoute _fromState(GoRouterState state) =>
      NotificationsRoute(deviceId: state.pathParameters['deviceId']!);

  NotificationsRoute get _self => this as NotificationsRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/notifications',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $notificationReplyRoute => GoRouteData.$route(
  path: '/devices/:deviceId/notifications/:notificationId/reply',
  name: 'notification-reply',
  hasOverriddenOnExit: false,
  parentNavigatorKey: NotificationReplyRoute.$parentNavigatorKey,
  factory: $NotificationReplyRoute._fromState,
);

mixin $NotificationReplyRoute on GoRouteData {
  static NotificationReplyRoute _fromState(GoRouterState state) =>
      NotificationReplyRoute(
        deviceId: state.pathParameters['deviceId']!,
        notificationId: state.pathParameters['notificationId']!,
      );

  NotificationReplyRoute get _self => this as NotificationReplyRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/notifications/${Uri.encodeComponent(_self.notificationId)}/reply',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $callsRoute => GoRouteData.$route(
  path: '/devices/:deviceId/calls',
  name: 'calls',
  hasOverriddenOnExit: false,
  parentNavigatorKey: CallsRoute.$parentNavigatorKey,
  factory: $CallsRoute._fromState,
);

mixin $CallsRoute on GoRouteData {
  static CallsRoute _fromState(GoRouterState state) =>
      CallsRoute(deviceId: state.pathParameters['deviceId']!);

  CallsRoute get _self => this as CallsRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/calls',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $deviceDataRoute => GoRouteData.$route(
  path: '/devices/:deviceId/data',
  name: 'device-data',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DeviceDataRoute.$parentNavigatorKey,
  factory: $DeviceDataRoute._fromState,
);

mixin $DeviceDataRoute on GoRouteData {
  static DeviceDataRoute _fromState(GoRouterState state) =>
      DeviceDataRoute(deviceId: state.pathParameters['deviceId']!);

  DeviceDataRoute get _self => this as DeviceDataRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/data',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $qualityRoute => GoRouteData.$route(
  path: '/devices/:deviceId/quality',
  name: 'quality',
  hasOverriddenOnExit: false,
  parentNavigatorKey: QualityRoute.$parentNavigatorKey,
  factory: $QualityRoute._fromState,
);

mixin $QualityRoute on GoRouteData {
  static QualityRoute _fromState(GoRouterState state) =>
      QualityRoute(deviceId: state.pathParameters['deviceId']!);

  QualityRoute get _self => this as QualityRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/quality',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $sessionToolsRoute => GoRouteData.$route(
  path: '/devices/:deviceId/tools',
  name: 'session-tools',
  hasOverriddenOnExit: false,
  parentNavigatorKey: SessionToolsRoute.$parentNavigatorKey,
  factory: $SessionToolsRoute._fromState,
);

mixin $SessionToolsRoute on GoRouteData {
  static SessionToolsRoute _fromState(GoRouterState state) => SessionToolsRoute(
    deviceId: state.pathParameters['deviceId']!,
    sessionId: state.uri.queryParameters['session-id'],
  );

  SessionToolsRoute get _self => this as SessionToolsRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/tools',
    queryParams: {if (_self.sessionId != null) 'session-id': _self.sessionId},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $sessionsRoute => GoRouteData.$route(
  path: '/devices/:deviceId/sessions',
  name: 'sessions',
  hasOverriddenOnExit: false,
  parentNavigatorKey: SessionsRoute.$parentNavigatorKey,
  factory: $SessionsRoute._fromState,
);

mixin $SessionsRoute on GoRouteData {
  static SessionsRoute _fromState(GoRouterState state) =>
      SessionsRoute(deviceId: state.pathParameters['deviceId']!);

  SessionsRoute get _self => this as SessionsRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/sessions',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $remoteRoute => GoRouteData.$route(
  path: '/devices/:deviceId/remote',
  name: 'remote',
  hasOverriddenOnExit: false,
  parentNavigatorKey: RemoteRoute.$parentNavigatorKey,
  factory: $RemoteRoute._fromState,
);

mixin $RemoteRoute on GoRouteData {
  static RemoteRoute _fromState(GoRouterState state) => RemoteRoute(
    deviceId: state.pathParameters['deviceId']!,
    keyboard:
        _$convertMapValue(
          'keyboard',
          state.uri.queryParameters,
          _$boolConverter,
        ) ??
        false,
    $extra: state.extra as Object?,
  );

  RemoteRoute get _self => this as RemoteRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/remote',
    queryParams: {
      if (_self.keyboard != false) 'keyboard': _self.keyboard.toString(),
    },
  );

  @override
  void go(BuildContext context) => context.go(location, extra: _self.$extra);

  @override
  Future<T?> push<T>(BuildContext context) =>
      context.push<T>(location, extra: _self.$extra);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location, extra: _self.$extra);

  @override
  void replace(BuildContext context) =>
      context.replace(location, extra: _self.$extra);
}

RouteBase get $remoteAppRoute => GoRouteData.$route(
  path: '/devices/:deviceId/apps/:packageName/remote',
  name: 'remote-app',
  hasOverriddenOnExit: false,
  parentNavigatorKey: RemoteAppRoute.$parentNavigatorKey,
  factory: $RemoteAppRoute._fromState,
);

mixin $RemoteAppRoute on GoRouteData {
  static RemoteAppRoute _fromState(GoRouterState state) => RemoteAppRoute(
    deviceId: state.pathParameters['deviceId']!,
    packageName: state.pathParameters['packageName']!,
    keyboard:
        _$convertMapValue(
          'keyboard',
          state.uri.queryParameters,
          _$boolConverter,
        ) ??
        false,
    $extra: state.extra as Object?,
  );

  RemoteAppRoute get _self => this as RemoteAppRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/apps/${Uri.encodeComponent(_self.packageName)}/remote',
    queryParams: {
      if (_self.keyboard != false) 'keyboard': _self.keyboard.toString(),
    },
  );

  @override
  void go(BuildContext context) => context.go(location, extra: _self.$extra);

  @override
  Future<T?> push<T>(BuildContext context) =>
      context.push<T>(location, extra: _self.$extra);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location, extra: _self.$extra);

  @override
  void replace(BuildContext context) =>
      context.replace(location, extra: _self.$extra);
}

RouteBase get $remoteSessionRoute => GoRouteData.$route(
  path: '/devices/:deviceId/sessions/:sessionId',
  name: 'remote-session',
  hasOverriddenOnExit: false,
  parentNavigatorKey: RemoteSessionRoute.$parentNavigatorKey,
  factory: $RemoteSessionRoute._fromState,
);

mixin $RemoteSessionRoute on GoRouteData {
  static RemoteSessionRoute _fromState(GoRouterState state) =>
      RemoteSessionRoute(
        deviceId: state.pathParameters['deviceId']!,
        sessionId: state.pathParameters['sessionId']!,
        keyboard:
            _$convertMapValue(
              'keyboard',
              state.uri.queryParameters,
              _$boolConverter,
            ) ??
            false,
        $extra: state.extra as RemoteControlIntent?,
      );

  RemoteSessionRoute get _self => this as RemoteSessionRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/sessions/${Uri.encodeComponent(_self.sessionId)}',
    queryParams: {
      if (_self.keyboard != false) 'keyboard': _self.keyboard.toString(),
    },
  );

  @override
  void go(BuildContext context) => context.go(location, extra: _self.$extra);

  @override
  Future<T?> push<T>(BuildContext context) =>
      context.push<T>(location, extra: _self.$extra);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location, extra: _self.$extra);

  @override
  void replace(BuildContext context) =>
      context.replace(location, extra: _self.$extra);
}

RouteBase get $transferDetailsRoute => GoRouteData.$route(
  path: '/transfers/:taskId',
  name: 'transfer-details',
  hasOverriddenOnExit: false,
  parentNavigatorKey: TransferDetailsRoute.$parentNavigatorKey,
  factory: $TransferDetailsRoute._fromState,
);

mixin $TransferDetailsRoute on GoRouteData {
  static TransferDetailsRoute _fromState(GoRouterState state) =>
      TransferDetailsRoute(taskId: state.pathParameters['taskId']!);

  TransferDetailsRoute get _self => this as TransferDetailsRoute;

  @override
  String get location =>
      GoRouteData.$location('/transfers/${Uri.encodeComponent(_self.taskId)}');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $documentExportRoute => GoRouteData.$route(
  path: '/transfers/:taskId/export',
  name: 'document-export',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DocumentExportRoute.$parentNavigatorKey,
  factory: $DocumentExportRoute._fromState,
);

mixin $DocumentExportRoute on GoRouteData {
  static DocumentExportRoute _fromState(GoRouterState state) =>
      DocumentExportRoute(
        taskId: state.pathParameters['taskId']!,
        partial:
            _$convertMapValue(
              'partial',
              state.uri.queryParameters,
              _$boolConverter,
            ) ??
            false,
      );

  DocumentExportRoute get _self => this as DocumentExportRoute;

  @override
  String get location => GoRouteData.$location(
    '/transfers/${Uri.encodeComponent(_self.taskId)}/export',
    queryParams: {
      if (_self.partial != false) 'partial': _self.partial.toString(),
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $receiveContentRoute => GoRouteData.$route(
  path: '/transfers/:taskId/receive',
  name: 'receive-content',
  hasOverriddenOnExit: false,
  parentNavigatorKey: ReceiveContentRoute.$parentNavigatorKey,
  factory: $ReceiveContentRoute._fromState,
);

mixin $ReceiveContentRoute on GoRouteData {
  static ReceiveContentRoute _fromState(GoRouterState state) =>
      ReceiveContentRoute(
        taskId: state.pathParameters['taskId']!,
        share:
            _$convertMapValue(
              'share',
              state.uri.queryParameters,
              _$boolConverter,
            ) ??
            false,
      );

  ReceiveContentRoute get _self => this as ReceiveContentRoute;

  @override
  String get location => GoRouteData.$location(
    '/transfers/${Uri.encodeComponent(_self.taskId)}/receive',
    queryParams: {if (_self.share != false) 'share': _self.share.toString()},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $documentImportRoute => GoRouteData.$route(
  path: '/devices/:deviceId/documents/import',
  name: 'document-import',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DocumentImportRoute.$parentNavigatorKey,
  factory: $DocumentImportRoute._fromState,
);

mixin $DocumentImportRoute on GoRouteData {
  static DocumentImportRoute _fromState(GoRouterState state) =>
      DocumentImportRoute(
        deviceId: state.pathParameters['deviceId']!,
        destination:
            state.uri.queryParameters['destination'] ?? '/sdcard/Download',
      );

  DocumentImportRoute get _self => this as DocumentImportRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/documents/import',
    queryParams: {
      if (_self.destination != '/sdcard/Download')
        'destination': _self.destination,
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $incomingShareRoute => GoRouteData.$route(
  path: '/sharing/:shareId',
  name: 'incoming-share',
  hasOverriddenOnExit: false,
  parentNavigatorKey: IncomingShareRoute.$parentNavigatorKey,
  factory: $IncomingShareRoute._fromState,
);

mixin $IncomingShareRoute on GoRouteData {
  static IncomingShareRoute _fromState(GoRouterState state) =>
      IncomingShareRoute(shareId: state.pathParameters['shareId']!);

  IncomingShareRoute get _self => this as IncomingShareRoute;

  @override
  String get location =>
      GoRouteData.$location('/sharing/${Uri.encodeComponent(_self.shareId)}');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $shareDirectoryRoute => GoRouteData.$route(
  path: '/devices/:deviceId/share-directory',
  name: 'share-directory',
  hasOverriddenOnExit: false,
  parentNavigatorKey: ShareDirectoryRoute.$parentNavigatorKey,
  factory: $ShareDirectoryRoute._fromState,
);

mixin $ShareDirectoryRoute on GoRouteData {
  static ShareDirectoryRoute _fromState(GoRouterState state) =>
      ShareDirectoryRoute(
        deviceId: state.pathParameters['deviceId']!,
        path: state.uri.queryParameters['path'] ?? '/sdcard',
      );

  ShareDirectoryRoute get _self => this as ShareDirectoryRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/share-directory',
    queryParams: {if (_self.path != '/sdcard') 'path': _self.path},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $appearanceRoute => GoRouteData.$route(
  path: '/settings/appearance',
  name: 'appearance',
  hasOverriddenOnExit: false,
  parentNavigatorKey: AppearanceRoute.$parentNavigatorKey,
  factory: $AppearanceRoute._fromState,
);

mixin $AppearanceRoute on GoRouteData {
  static AppearanceRoute _fromState(GoRouterState state) =>
      const AppearanceRoute();

  @override
  String get location => GoRouteData.$location('/settings/appearance');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $backgroundRoute => GoRouteData.$route(
  path: '/settings/background',
  name: 'background',
  hasOverriddenOnExit: false,
  parentNavigatorKey: BackgroundRoute.$parentNavigatorKey,
  factory: $BackgroundRoute._fromState,
);

mixin $BackgroundRoute on GoRouteData {
  static BackgroundRoute _fromState(GoRouterState state) =>
      const BackgroundRoute();

  @override
  String get location => GoRouteData.$location('/settings/background');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $activitiesRoute => GoRouteData.$route(
  path: '/settings/activities',
  name: 'activities',
  hasOverriddenOnExit: false,
  parentNavigatorKey: ActivitiesRoute.$parentNavigatorKey,
  factory: $ActivitiesRoute._fromState,
);

mixin $ActivitiesRoute on GoRouteData {
  static ActivitiesRoute _fromState(GoRouterState state) =>
      const ActivitiesRoute();

  @override
  String get location => GoRouteData.$location('/settings/activities');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $dataPreferencesRoute => GoRouteData.$route(
  path: '/settings/data',
  name: 'data-preferences',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DataPreferencesRoute.$parentNavigatorKey,
  factory: $DataPreferencesRoute._fromState,
);

mixin $DataPreferencesRoute on GoRouteData {
  static DataPreferencesRoute _fromState(GoRouterState state) =>
      const DataPreferencesRoute();

  @override
  String get location => GoRouteData.$location('/settings/data');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $mediaCacheRoute => GoRouteData.$route(
  path: '/settings/media-cache',
  name: 'media-cache',
  hasOverriddenOnExit: false,
  parentNavigatorKey: MediaCacheRoute.$parentNavigatorKey,
  factory: $MediaCacheRoute._fromState,
);

mixin $MediaCacheRoute on GoRouteData {
  static MediaCacheRoute _fromState(GoRouterState state) =>
      const MediaCacheRoute();

  @override
  String get location => GoRouteData.$location('/settings/media-cache');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $deviceActivitiesRoute => GoRouteData.$route(
  path: '/devices/:deviceId/activities',
  name: 'device-activities',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DeviceActivitiesRoute.$parentNavigatorKey,
  factory: $DeviceActivitiesRoute._fromState,
);

mixin $DeviceActivitiesRoute on GoRouteData {
  static DeviceActivitiesRoute _fromState(GoRouterState state) =>
      DeviceActivitiesRoute(deviceId: state.pathParameters['deviceId']!);

  DeviceActivitiesRoute get _self => this as DeviceActivitiesRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/activities',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $adbIdentityRoute => GoRouteData.$route(
  path: '/settings/adb-key',
  name: 'adb-key',
  hasOverriddenOnExit: false,
  parentNavigatorKey: AdbIdentityRoute.$parentNavigatorKey,
  factory: $AdbIdentityRoute._fromState,
);

mixin $AdbIdentityRoute on GoRouteData {
  static AdbIdentityRoute _fromState(GoRouterState state) =>
      const AdbIdentityRoute();

  @override
  String get location => GoRouteData.$location('/settings/adb-key');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $deviceIdentityRoute => GoRouteData.$route(
  path: '/devices/:deviceId/adb-key',
  name: 'device-adb-key',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DeviceIdentityRoute.$parentNavigatorKey,
  factory: $DeviceIdentityRoute._fromState,
);

mixin $DeviceIdentityRoute on GoRouteData {
  static DeviceIdentityRoute _fromState(GoRouterState state) =>
      DeviceIdentityRoute(deviceId: state.pathParameters['deviceId']!);

  DeviceIdentityRoute get _self => this as DeviceIdentityRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/adb-key',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $deviceIpRoute => GoRouteData.$route(
  path: '/devices/:deviceId/convert-ip',
  name: 'device-convert-ip',
  hasOverriddenOnExit: false,
  parentNavigatorKey: DeviceIpRoute.$parentNavigatorKey,
  factory: $DeviceIpRoute._fromState,
);

mixin $DeviceIpRoute on GoRouteData {
  static DeviceIpRoute _fromState(GoRouterState state) =>
      DeviceIpRoute(deviceId: state.pathParameters['deviceId']!);

  DeviceIpRoute get _self => this as DeviceIpRoute;

  @override
  String get location => GoRouteData.$location(
    '/devices/${Uri.encodeComponent(_self.deviceId)}/convert-ip',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}
