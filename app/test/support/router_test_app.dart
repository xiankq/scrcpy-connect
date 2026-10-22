import 'test_controller.dart';

import 'package:scrcpy_connect/router/route_observers.dart';

import 'package:scrcpy_connect/pages/connection/index/connection_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/apps/devices_workspace_apps_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/calls/devices_workspace_calls_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/import/devices_workspace_files_import_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/details/devices_workspace_files_details_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/index/devices_workspace_gallery_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/devices_workspace_gallery_preview_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/directory_picker/devices_workspace_files_directory_picker_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A test entry route for focused page tests. Production routes still rebuild
/// their own pages; only explicit test device fixtures bypass native lookups.
class RouterTestApp extends StatefulWidget {
  const RouterTestApp({
    super.key,
    required this.controller,
    required this.home,
    this.theme,
    this.devices = const [],
  });
  final AppController controller;
  final Widget home;
  final ThemeData? theme;
  final List<Json> devices;
  @override
  State<RouterTestApp> createState() => _RouterTestAppState();
}

class _RouterTestAppState extends State<RouterTestApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.loading = false;
    seedRouteDevices(widget.controller, [
      ...widget.devices,
      ?_homeDevice(widget.home),
      ...widget.controller.devices,
      if (widget.home case AddDevicePage(initialDevice: final device?)) device,
    ]);
    GoRouter.optionURLReflectsImperativeAPIs = true;
  }

  late final root = GlobalKey<NavigatorState>();
  late final router = GoRouter(
    navigatorKey: root,
    observers: [sessionRouteObserver],
    initialLocation: '/test',
    routes: [
      ...typedRoutes(root),
      GoRoute(path: '/test', builder: (_, state) => widget.home),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TestProviderScope(
    controller: widget.controller,
    child: MaterialApp.router(
      routerConfig: router,
      theme: widget.theme,
      debugShowCheckedModeBanner: false,
    ),
  );
}

Json? _homeDevice(Widget page) => switch (page) {
  DeviceWorkspacePage p => p.device,
  FilesPage p => p.device,
  FileDetailsPage p => p.device,
  AppsPage p => p.device,
  GalleryPage p => p.device,
  MediaPreviewPage p => p.device,
  NotificationsPage p => p.device,
  CallsPage p => p.device,
  QualityPage p => p.device,
  RemotePage p => p.device,
  ShareDirectoryPickerPage p => p.device,
  DocumentImportPage p => p.device,
  _ => null,
};
