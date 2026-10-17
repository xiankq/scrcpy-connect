import 'test_controller.dart';

import 'package:scrcpy_connect/router/route_observers.dart';

import 'package:scrcpy_connect/pages/add_device/add_device_page.dart';
import 'package:scrcpy_connect/pages/apps/apps_page.dart';
import 'package:scrcpy_connect/pages/calls/calls_page.dart';
import 'package:scrcpy_connect/pages/device_details/device_details_page.dart';
import 'package:scrcpy_connect/pages/device_workspace/device_workspace_page.dart';
import 'package:scrcpy_connect/pages/document_import/document_import_page.dart';
import 'package:scrcpy_connect/pages/file_details/file_details_page.dart';
import 'package:scrcpy_connect/pages/files/files_page.dart';
import 'package:scrcpy_connect/pages/gallery/gallery_page.dart';
import 'package:scrcpy_connect/pages/media_preview/media_preview_page.dart';
import 'package:scrcpy_connect/pages/notification_reply/notification_reply_page.dart';
import 'package:scrcpy_connect/pages/notifications/notifications_page.dart';
import 'package:scrcpy_connect/pages/quality/quality_page.dart';
import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/pages/sessions/sessions_page.dart';
import 'package:scrcpy_connect/pages/share_directory_picker/share_directory_picker_page.dart';
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
    child: MaterialApp.router(routerConfig: router, theme: widget.theme),
  );
}

Json? _homeDevice(Widget page) => switch (page) {
  DeviceWorkspacePage p => p.device,
  DeviceDetailsPage p => p.device,
  FilesPage p => p.device,
  FileDetailsPage p => p.device,
  AppsPage p => p.device,
  GalleryPage p => p.device,
  MediaPreviewPage p => p.device,
  NotificationsPage p => p.device,
  NotificationReplyPage p => p.device,
  CallsPage p => p.device,
  QualityPage p => p.device,
  RemotePage p => p.device,
  SessionsPage p => p.device,
  ShareDirectoryPickerPage p => p.device,
  DocumentImportPage p => p.device,
  _ => null,
};
