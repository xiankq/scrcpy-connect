import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'support/test_controller.dart';
import 'support/router_test_app.dart';

import 'package:scrcpy_connect/pages/activities/activities_page.dart';
import 'package:scrcpy_connect/pages/add_device/add_device_page.dart';
import 'package:scrcpy_connect/pages/appearance/appearance_page.dart';
import 'package:scrcpy_connect/pages/apps/apps_page.dart';
import 'package:scrcpy_connect/pages/background/background_page.dart';
import 'package:scrcpy_connect/pages/calls/calls_page.dart';
import 'package:scrcpy_connect/pages/capabilities/capabilities_page.dart';
import 'package:scrcpy_connect/pages/connection_form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/data_preferences/data_preferences_page.dart';
import 'package:scrcpy_connect/pages/device_connection_preferences/device_connection_preferences_page.dart';
import 'package:scrcpy_connect/pages/device_details/device_details_page.dart';
import 'package:scrcpy_connect/pages/device_workspace/device_workspace_page.dart';
import 'package:scrcpy_connect/pages/devices/devices_page.dart';
import 'package:scrcpy_connect/pages/diagnostics/diagnostics_page.dart';
import 'package:scrcpy_connect/pages/discovery/discovery_page.dart';
import 'package:scrcpy_connect/pages/document_export/document_export_page.dart';
import 'package:scrcpy_connect/pages/document_import/document_import_page.dart';
import 'package:scrcpy_connect/pages/file_details/file_details_page.dart';
import 'package:scrcpy_connect/pages/file_search/file_search_page.dart';
import 'package:scrcpy_connect/pages/files/files_page.dart';
import 'package:scrcpy_connect/pages/gallery/gallery_page.dart';
import 'package:scrcpy_connect/pages/incoming_share/incoming_share_page.dart';
import 'package:scrcpy_connect/pages/media_cache/media_cache_page.dart';
import 'package:scrcpy_connect/pages/media_preview/media_preview_page.dart';
import 'package:scrcpy_connect/pages/notification_reply/notification_reply_page.dart';
import 'package:scrcpy_connect/pages/notifications/notifications_page.dart';
import 'package:scrcpy_connect/pages/qr_pair/qr_pair_page.dart';
import 'package:scrcpy_connect/pages/quality/quality_page.dart';
import 'package:scrcpy_connect/pages/receive_content/receive_content_page.dart';
import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/pages/route_error/route_error_page.dart';
import 'package:scrcpy_connect/pages/session_tools/session_tools_page.dart';
import 'package:scrcpy_connect/pages/sessions/sessions_page.dart';
import 'package:scrcpy_connect/pages/settings/settings_page.dart';
import 'package:scrcpy_connect/pages/share_directory_picker/share_directory_picker_page.dart';
import 'package:scrcpy_connect/pages/startup_error/startup_error_page.dart';
import 'package:scrcpy_connect/pages/transfer_details/transfer_details_page.dart';
import 'package:scrcpy_connect/pages/transfers/transfers_page.dart';
import 'package:scrcpy_connect/pages/usb_guide/usb_guide_page.dart';
import 'package:scrcpy_connect/pages/wireless_guide/wireless_guide_page.dart';

// Every production page is captured directly, with native responses isolated here.
// CONNECT_CAPTURE_DIR=/tmp/connect-ios-review flutter test test/ios_pages_capture_test.dart
const device = <String, dynamic>{
  'id': 'fixture',
  'name': '我的手机',
  'model': 'Pixel 9',
  'status': 'connected',
  'transport': '无线连接',
  'androidVersion': '15',
  'address': '192.168.1.8',
  'apiLevel': 35,
};
const file = <String, dynamic>{
  'name': '旅行清单.pdf',
  'path': '/sdcard/Download/旅行清单.pdf',
  'size': 2468000,
  'mime': 'application/pdf',
  'isDirectory': false,
};
const photo = <String, dynamic>{
  'name': '湖边.jpg',
  'path': '/sdcard/DCIM/湖边.jpg',
  'mime': 'image/jpeg',
  'size': 2840000,
  'isDirectory': false,
};
const session = <String, dynamic>{
  'id': 'screen',
  'sessionId': 'screen',
  'deviceId': 'fixture',
  'name': '手机屏幕',
  'status': 'running',
  'textureId': 1,
  'width': 1080,
  'height': 2400,
};
const task = <String, dynamic>{
  'id': 'transfer',
  'transferId': 'transfer',
  'deviceId': 'fixture',
  'name': '旅行照片',
  'kind': 'directory',
  'status': 'running',
  'direction': 'pull',
  'destinationScope': 'privateCache',
  'deviceName': '我的手机',
  'sourceLabel': '我的手机',
  'destinationLabel': '本机暂存',
  'totalBytes': 24000000,
  'completedBytes': 15600000,
};
const notification = <String, dynamic>{
  'id': 'message',
  'deviceId': 'fixture',
  'appName': '信息',
  'title': '小林',
  'body': '我们下午三点在车站见。',
  'canReply': true,
  'canOpen': true,
  'canDismiss': true,
};

Future<Json> fixtureRequest(String command, [Json params = const {}]) async =>
    switch (command) {
      'devices.list' => {
        'devices': [
          device,
          {'id': 'offline', 'name': '备用手机', 'status': 'offline'},
        ],
      },
      'settings.get' => {'appearance': 'light'},
      'device.info' => device,
      'device.diagnose' => {
        'device': device,
        'connected': true,
        'tcpReachable': true,
        'identityPresent': true,
      },
      'devices.discover' => {
        'devices': [
          {
            'id': 'nearby',
            'name': '客厅手机',
            'kind': 'pairing',
            'address': '192.168.1.9',
            'port': 37000,
          },
        ],
      },
      'apps.list' => {
        'apps': [
          {'name': '信息', 'packageName': 'com.android.messaging'},
          {'name': '相机', 'packageName': 'com.android.camera'},
          {'name': '地图', 'packageName': 'com.google.android.apps.maps'},
        ],
      },
      'files.list' => {
        'path': params['path'],
        'entries': [
          {'name': 'Download', 'path': '/sdcard/Download', 'isDirectory': true},
          file,
        ],
      },
      'files.search.start' || 'files.search.get' => {
        'searchId': 'search',
        'deviceId': 'fixture',
        'path': '/sdcard',
        'status': 'completed',
        'entries': [file],
        'items': [file],
        'query': '旅行',
        'filter': 'all',
        'complete': true,
        'visitedDirectories': 12,
      },
      'media.list' || 'media.scan.get' => {
        'scanId': 'gallery',
        'deviceId': 'fixture',
        'status': 'completed',
        'offset': 0,
        'items': [photo],
        'total': 1,
        'scannedDirectories': 18,
        'issueCount': 0,
      },
      'media.preview' || 'media.thumbnail' =>
        params['path'] == photo['path']
            ? {
                'localPath': File('designs/assets/sample-lake.jpg')
                    .absolute
                    .path,
                'mime': 'image/jpeg',
              }
            : {'reason': '文件尚未完整取回，可保存原文件后查看。'},
      'media.cache.status' => {
        'usedBytes': 560000000,
        'budgetBytes': 2000000000,
        'protectedBytes': 120000000,
        'reclaimableBytes': 440000000,
        'reservedBytes': 24000000,
      },
      'session.list' => {
        'sessions': [session],
      },
      'session.start' || 'session.resume' || 'session.get' => session,
      'notifications.list' => {
        'status': 'available',
        'notifications': [notification],
      },
      'calls.list' => {
        'status': 'available',
        'live': true,
        'controlStatus': 'available',
        'audioStatus': 'limited',
        'calls': [
          {
            'id': 'call',
            'name': '小林',
            'number': '138 0013 8000',
            'state': 'ringing',
            'canAnswer': true,
            'canReject': true,
          },
        ],
      },
      'transfers.list' => {
        'transfers': [task],
      },
      'transfers.get' => task,
      'activities.list' => {
        'activities': [
          {
            'id': 'connected',
            'name': '设备连接',
            'deviceName': '我的手机',
            'status': 'connected',
          },
          {
            'id': 'transfer',
            'name': '照片传输',
            'deviceName': '我的手机',
            'status': 'running',
          },
        ],
      },
      'device.capabilities' => {
        'capabilities': [
          {'id': 'screen', 'name': '手机屏幕', 'status': 'available'},
          {'id': 'files', 'name': '文件管理', 'status': 'available'},
          {
            'id': 'audio',
            'name': '设备声音',
            'status': 'limited',
            'reason': '本机播放将在打开控制页面时检查。',
          },
        ],
      },
      'background.status' => {
        'title': '后台保持已就绪',
        'reason': '系统允许当前设备连接继续运行。',
        'canRequest': false,
      },
      'session.quality.options' => {
        'current': {
          'preset': 'balanced',
          'maxSize': 1920,
          'maxFps': 60,
          'bitRate': 8000000,
          'videoCodec': 'h264',
        },
        'presets': [
          {'id': 'smooth', 'name': '流畅', 'available': true},
          {'id': 'balanced', 'name': '均衡', 'available': true},
          {'id': 'sharp', 'name': '清晰', 'available': true},
        ],
        'codecs': [
          {
            'id': 'h264',
            'name': 'H.264',
            'available': true,
            'targetStatus': 'available',
            'decoderStatus': 'available',
            'encoders': <Json>[],
          },
        ],
        'maxSize': [
          {'label': '1920', 'value': 1920, 'available': true},
        ],
      },
      'devices.pair.qr' => {
        'attemptId': 'qr',
        'status': 'waiting',
        'payload': 'WIFI:T:ADB;S:fixture;P:123456;;',
        'expiresAt':
            DateTime.now()
                .add(const Duration(minutes: 3))
                .millisecondsSinceEpoch ~/
            1000,
      },
      _ => {},
    };

ThemeData captureTheme(Brightness brightness) {
  final theme = ConnectTokens.theme(brightness);
  const family = 'ConnectCaptureCJK';
  ButtonStyle? fontStyle(ButtonStyle? style) => style?.copyWith(
    textStyle: WidgetStatePropertyAll(
      (style.textStyle?.resolve({}) ?? const TextStyle()).copyWith(
        fontFamily: family,
      ),
    ),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: family),
    filledButtonTheme: FilledButtonThemeData(
      style: fontStyle(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: fontStyle(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: fontStyle(theme.textButtonTheme.style),
    ),
  );
}

Map<String, Widget> pageFixtures(AppController controller) => <String, Widget>{
  'activities': ActivitiesPage(controller: controller),
  'add_device': AddDevicePage(controller: controller),
  'appearance': AppearancePage(controller: controller),
  'apps': AppsPage(controller: controller, device: device),
  'background': BackgroundPage(controller: controller),
  'calls': CallsPage(controller: controller, device: device),
  'capabilities': CapabilitiesPage(controller: controller, device: device),
  'connection_form': ConnectionFormPage(controller: controller),
  'data_preferences': DataPreferencesPage(controller: controller),
  'device_connection_preferences': DeviceConnectionPreferencesPage(
    controller: controller,
    device: device,
  ),
  'device_details': DeviceDetailsPage(controller: controller, device: device),
  'device_workspace': DeviceWorkspacePage(
    controller: controller,
    device: device,
  ),
  'devices': Scaffold(body: DevicesPage(controller: controller)),
  'diagnostics': DiagnosticsPage(controller: controller, device: device),
  'discovery': DiscoveryPage(controller: controller),
  'document_export': DocumentExportPage(
    controller: controller,
    localPath: '/tmp/fixture-original.pdf',
    name: '旅行清单.pdf',
    kind: 'file',
  ),
  'document_import': DocumentImportPage(
    controller: controller,
    device: device,
    destination: '/sdcard/Download',
    onSubmitted: () {},
  ),
  'file_details': FileDetailsPage(
    controller: controller,
    device: device,
    file: file,
  ),
  'file_search': FileSearchPage(
    controller: controller,
    device: device,
    initialQuery: '旅行',
  ),
  'file_search_results': FileSearchPage(
    controller: controller,
    device: device,
    initialQuery: '旅行',
  ),
  'files': FilesPage(controller: controller, device: device),
  'gallery': GalleryPage(controller: controller, device: device),
  'incoming_share': IncomingSharePage(
    controller: controller,
    share: const {
      'shareId': 'share',
      'text': '下午三点在车站见。',
      'files': [file],
    },
  ),
  'media_cache': MediaCachePage(controller: controller),
  'media_preview': MediaPreviewPage(
    controller: controller,
    device: device,
    file: photo,
  ),
  'media_preview_unavailable': MediaPreviewPage(
    controller: controller,
    device: device,
    file: file,
  ),
  'notification_reply': NotificationReplyPage(
    controller: controller,
    device: device,
    notification: notification,
  ),
  'notifications': NotificationsPage(controller: controller, device: device),
  'qr_pair': QrPairPage(controller: controller),
  'quality': QualityPage(controller: controller, device: device),
  'receive_content': ReceiveContentPage(controller: controller, task: task),
  'remote': RemotePage(controller: controller, device: device),
  'route_error': RouteErrorPage(message: '设备当前离线，恢复连接后重新打开。', onRetry: () {}),
  'session_tools': SessionToolsPage(controller: controller, device: device),
  'sessions': SessionsPage(controller: controller, device: device),
  'settings': SettingsPage(controller: controller),
  'share_directory_picker': ShareDirectoryPickerPage(
    controller: controller,
    device: device,
    initialPath: '/sdcard',
  ),
  'startup_error': StartupErrorPage(
    error: StateError('无法读取本机设备连接配置'),
    onRetry: () {},
  ),
  'transfer_details': TransferDetailsPage(controller: controller, task: task),
  'transfers': TransfersPage(controller: controller),
  'usb_guide': UsbGuidePage(controller: controller),
  'wireless_guide': WirelessGuidePage(controller: controller),
  'legacy_tcp': ConnectionFormPage(
    controller: controller,
    transport: ConnectionTransport.tcp,
  ),
  'pairing_form': ConnectionFormPage(controller: controller, pairing: true),
  'selected_session_tools': SessionToolsPage(
    controller: controller,
    device: device,
    sessionId: 'screen',
  ),
};

Future<void> waitForPageImages(WidgetTester tester) async {
  final elements = find.byType(Image).evaluate().toList();
  final received = List<bool>.filled(elements.length, false);
  final streams = <(ImageStream, ImageStreamListener)>[];
  Object? failure;
  // Image decoders need both real IO and scheduled Flutter frames. Awaiting the
  // stream in runAsync alone would block the very frame that delivers it.
  await tester.runAsync(() async {
    for (var index = 0; index < elements.length; index++) {
      final element = elements[index];
      final stream = (element.widget as Image).image.resolve(
        createLocalImageConfiguration(element),
      );
      final listener = ImageStreamListener(
        (info, synchronous) {
          received[index] = true;
          info.dispose();
        },
        onError: (Object error, StackTrace? stack) {
          failure = error;
        },
      );
      streams.add((stream, listener));
      stream.addListener(listener);
    }
  });
  try {
    for (
      var attempt = 0;
      attempt < 200 && !received.every((ready) => ready) && failure == null;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(failure, isNull, reason: 'Fixture photo decoding must succeed');
    expect(
      received.every((ready) => ready),
      isTrue,
      reason: 'Each fixture image must deliver its first frame before capture',
    );
  } finally {
    for (final (stream, listener) in streams) {
      stream.removeListener(listener);
    }
  }
  await tester.pump();
}

void main() {
  final output = Platform.environment['CONNECT_CAPTURE_DIR'];
  if (output == null) return;
  testWidgets('capture every product page in light and dark', (tester) async {
    for (final font in [
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final cjk = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (cjk.existsSync()) {
      for (final family in ['Roboto', 'ConnectCaptureCJK', 'Ahem']) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(cjk.readAsBytesSync())),
            ))
            .load();
      }
    }
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final directory = Directory(output);
    await tester.runAsync(() => directory.create(recursive: true));
    for (final brightness in Brightness.values) {
      final controller = createTestController(fixtureRequest);
      await controller.initialize();
      final pages = pageFixtures(controller);
      for (final entry in pages.entries) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: RouterTestApp(
              key: ValueKey('${entry.key}-${brightness.name}'),
              controller: controller,
              theme: captureTheme(brightness),
              home: entry.value,
            ),
          ),
        );
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (entry.key == 'file_search_results') {
          await tester.tap(find.text('搜索'));
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        await waitForPageImages(tester);
        if (entry.key == 'gallery' || entry.key == 'media_preview') {
          final rasters = tester
              .widgetList<RawImage>(find.byType(RawImage))
              .toList();
          expect(
            rasters,
            isNotEmpty,
            reason: '${entry.key}-${brightness.name} must show its real photo',
          );
          expect(
            rasters.every((raster) => raster.image != null),
            isTrue,
            reason:
                '${entry.key}-${brightness.name} must finish image decoding before capture',
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key}-${brightness.name}',
        );
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${directory.path}/${entry.key}-${brightness.name}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      final boundary = GlobalKey();
      controller.settings = {
        ...controller.settings,
        'appearance': brightness.name,
      };
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: TestProviderScope(
            controller: controller,
            child: const ConnectApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${directory.path}/home-${brightness.name}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull, reason: 'home-${brightness.name}');
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      for (final layout in [
        ('narrow', const Size(280, 620)),
        ('landscape', const Size(620, 280)),
      ]) {
        tester.view.physicalSize = layout.$2;
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'home-${layout.$1}-large-text',
        );
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${directory.path}/home-${layout.$1}-large-text-${brightness.name}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(402, 874);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });
}
