import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'support/test_controller.dart';
import 'support/router_test_app.dart';

import 'package:scrcpy_connect/pages/settings/activities/settings_activities_page.dart';
import 'package:scrcpy_connect/pages/connection/index/connection_index_page.dart';
import 'package:scrcpy_connect/pages/settings/appearance/settings_appearance_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/apps/devices_workspace_apps_page.dart';
import 'package:scrcpy_connect/pages/settings/background/settings_background_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/calls/devices_workspace_calls_page.dart';
import 'package:scrcpy_connect/pages/devices/details/capabilities/devices_details_capabilities_page.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/settings/data_preferences/settings_data_preferences_page.dart';
import 'package:scrcpy_connect/pages/devices/details/connection_preferences/devices_details_connection_preferences_page.dart';
import 'package:scrcpy_connect/pages/devices/details/index/devices_details_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/index/devices_index_page.dart';
import 'package:scrcpy_connect/pages/devices/details/diagnostics/devices_details_diagnostics_page.dart';
import 'package:scrcpy_connect/pages/connection/discovery/connection_discovery_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/export/transfers_details_export_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/import/devices_workspace_files_import_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/details/devices_workspace_files_details_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/search/devices_workspace_files_search_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/index/devices_workspace_gallery_index_page.dart';
import 'package:scrcpy_connect/pages/incoming_share/incoming_share_page.dart';
import 'package:scrcpy_connect/pages/settings/media_cache/settings_media_cache_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/devices_workspace_gallery_preview_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/reply/devices_workspace_notifications_reply_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/pages/connection/wireless/qr/connection_wireless_qr_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/receive/transfers_details_receive_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/route_error/route_error_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/sessions/tools/devices_workspace_sessions_tools_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/sessions/index/devices_workspace_sessions_index_page.dart';
import 'package:scrcpy_connect/pages/settings/index/settings_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/directory_picker/devices_workspace_files_directory_picker_page.dart';
import 'package:scrcpy_connect/pages/startup_error/startup_error_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/index/transfers_details_index_page.dart';
import 'package:scrcpy_connect/pages/transfers/index/transfers_index_page.dart';
import 'package:scrcpy_connect/pages/connection/usb/connection_usb_page.dart';
import 'package:scrcpy_connect/pages/connection/wireless/index/connection_wireless_index_page.dart';

// Root tabs and parity reference pages use the production app/router. Other
// focused page fixtures isolate native responses without inventing app routes.
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
  'canCancel': true,
};
const qrPayload = 'WIFI:T:ADB;S:fixture;P:123456;;';
const searchPath = '/sdcard/Download';
final partialTask = <String, dynamic>{
  ...task,
  'id': 'partial-transfer',
  'transferId': 'partial-transfer',
  'status': 'partial',
  'canCancel': false,
  'canRestart': true,
  'canExport': false,
  'error': '部分文件未完成，请核对逐项结果。重新传输会从头开始，并重新检查同名内容。',
  'items': [
    {'name': '旅行清单.pdf', 'status': 'completed'},
    {'name': '视频.mp4', 'status': 'failed'},
    {'name': '资料.zip', 'status': 'failed'},
  ],
};
final failedDevice = <String, dynamic>{
  ...device,
  'status': 'offline',
  'transport': 'tls',
  'port': 37123,
  'reason': '当前地址的连接服务没有响应。',
};
final failedDiagnosis = <String, dynamic>{
  'device': failedDevice,
  'connected': false,
  'tcpReachable': false,
  'identityPresent': true,
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
        'path': searchPath,
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
                'localPath': File('../designs/assets/sample-lake.jpg')
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
        'payload': qrPayload,
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
    listTileTheme: theme.listTileTheme.copyWith(
      titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(
        fontFamily: family,
      ),
    ),
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

Map<String, Widget> pageFixtures(
  AppController controller, {
  AppController? diagnosisController,
  AppController? partialTransferController,
}) => <String, Widget>{
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
  'diagnostics_failed': DiagnosticsPage(
    controller: diagnosisController ?? controller,
    device: failedDevice,
  ),
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
    initialPath: searchPath,
    initialQuery: '旅行',
  ),
  'file_search_results': FileSearchPage(
    controller: controller,
    device: device,
    initialPath: searchPath,
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
  'transfer_details': TransferDetailsPage(
    controller: partialTransferController ?? controller,
    task: partialTask,
  ),
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

/// Resolve nested span styles as painted, including foreground Paint overrides.
List<Map<String, Object?>> captureTextStyleRuns(InlineSpan? text) {
  final runs = <Map<String, Object?>>[];
  void visit(InlineSpan value, TextStyle inherited) {
    final style = inherited.merge(value.style);
    if (value is! TextSpan) return;
    if (value.text case final String content) {
      final color =
          style.foreground?.color ?? style.color ?? const Color(0xff000000);
      final argb = color.toARGB32();
      runs.add({
        'text': content,
        'fontFamily': style.fontFamily,
        'fontSize': style.fontSize,
        'fontWeight': style.fontWeight?.value,
        'height': style.height,
        'letterSpacing': style.letterSpacing,
        'colorArgb': argb,
        'colorHex': '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}',
        if (style.foreground?.shader != null) 'foregroundHasShader': true,
      });
    }
    for (final child in value.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  if (text != null) visit(text, const TextStyle());
  return runs;
}

/// Read laid-out widgets without wrapping them or changing their constraints.
/// Bounds are source-image coordinates, before the parity tool's declared crop.
Map<String, Object?> captureLayout(GlobalKey boundary) {
  final components = <Map<String, Object?>>[];
  final paragraphs = <Map<String, Object?>>[];
  final editableTexts = <Map<String, Object?>>[];
  final root = boundary.currentContext! as Element;
  final viewport = Offset.zero & (root.findRenderObject()! as RenderBox).size;
  const tracked = {
    'PageFrame',
    'GroupedListView',
    'GroupedItem',
    'ActionRow',
    'ConnectSwitchRow',
    'SectionTitle',
    'StateNote',
    'ContentPanel',
    'FeatureIcon',
    'ListIconBadge',
    'Glass',
    'GlassTabBar',
    'GlassIconButton',
    'GlassToolbarGroup',
    'ConnectSwitch',
    'DeviceIdentity',
    'DeviceCard',
    'DeviceHero',
    'OriginalFileHeader',
    'AppBar',
    'ListTile',
    'TextField',
    'FilledButton',
    'OutlinedButton',
    'TextButton',
    'IconButton',
    'BackButton',
  };
  List<double> rect(Rect value) => [
    value.left,
    value.top,
    value.width,
    value.height,
  ];
  Map<String, Object?> geometry(RenderBox box) {
    final bounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    return {
      'globalBounds': rect(bounds),
      'intersectsViewport': bounds.overlaps(viewport),
    };
  }

  void visit(Element element, String? owner) {
    final widget = element.widget;
    if (widget is Offstage && widget.offstage) return;
    // Opaque route overlays can retain their preceding route without an
    // Offstage widget. Do not attribute that hidden route's geometry to this PNG.
    if (ModalRoute.of(element)?.isCurrent == false) return;
    final type = widget.runtimeType.toString();
    final render = element.findRenderObject();
    final box = render is RenderBox && render.attached && render.hasSize
        ? render
        : null;
    if (box != null &&
        (tracked.contains(type) || type.startsWith('ChoiceRow<'))) {
      final id = 'component-${components.length}';
      components.add({
        'id': id,
        'type': type,
        'parentComponent': owner,
        if (widget.key != null) 'key': widget.key.toString(),
        if (widget is ListIconBadge)
          'backgroundColorHex':
              '#${widget.backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
        ...geometry(box),
      });
      owner = id;
    }
    // RenderObjectElement avoids recording the same paragraph once per wrapper.
    if (element is RenderObjectElement &&
        render is RenderParagraph &&
        render.attached &&
        render.hasSize) {
      final text = render.text.toPlainText();
      paragraphs.add({
        'text': text,
        'parentComponent': owner,
        ...geometry(render),
        'maxLines': render.maxLines,
        'didExceedMaxLines': render.didExceedMaxLines,
        'textAlign': render.textAlign.name,
        'textScaleAt14': render.textScaler.scale(14) / 14,
        'lineBoxes': [
          for (final line in render.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: text.length),
          ))
            rect(line.toRect()),
        ],
        'styleRuns': captureTextStyleRuns(render.text),
      });
    }
    if (element is RenderObjectElement &&
        render is RenderEditable &&
        render.attached &&
        render.hasSize) {
      final editable = element.findAncestorWidgetOfExactType<EditableText>();
      RenderBox? field;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is! TextField) return true;
        final box = ancestor.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) field = box;
        return false;
      });
      editableTexts.add({
        'text': render.text?.toPlainText() ?? '',
        'value': editable?.controller.text,
        'readOnly': render.readOnly,
        'obscureText': render.obscureText,
        'parentComponent': owner,
        ...geometry(render),
        if (field != null)
          'fieldGlobalBounds': geometry(field!)['globalBounds'],
        'textScaleAt14': render.textScaler.scale(14) / 14,
        'styleRuns': captureTextStyleRuns(render.text),
      });
    }
    element.visitChildren((child) => visit(child, owner));
  }

  visit(root, null);
  return {
    'coordinateSpace': 'uncropped source image; logical pixels at DPR 1',
    'lineBoxCoordinateSpace': 'paragraph-local logical pixels',
    'sourceViewport': [viewport.width, viewport.height],
    'visibilityNote':
        'Offstage and non-current route subtrees excluded. Bounds may extend beyond '
        'scroll clips; intersectsViewport is not a paint-visibility assertion.',
    'components': components,
    'paragraphs': paragraphs,
    'editableTexts': editableTexts,
  };
}

Future<File> loadCaptureFonts() async {
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
      await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(cjk.readAsBytesSync()))))
          .load();
    }
  }
  return cjk;
}

Future<void> captureHomeLandscape(
  WidgetTester tester,
  Directory directory,
  AppController controller,
  Brightness brightness,
) async {
  final boundary = GlobalKey();
  final router = createAppRouter();
  tester.view.physicalSize = const Size(620, 280);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: TestProviderScope(
        controller: controller,
        child: MaterialApp.router(
          routerConfig: router,
          theme: captureTheme(brightness),
          debugShowCheckedModeBanner: false,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${directory.path}/home-landscape-large-text-${brightness.name}.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
  await tester.pumpWidget(const SizedBox());
  router.dispose();
}

void main() {
  final output = Platform.environment['CONNECT_CAPTURE_DIR'];
  if (output == null) return;
  testWidgets('capture home landscape with native sidebar font', (
    tester,
  ) async {
    await loadCaptureFonts();
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final directory = Directory(output);
    await tester.runAsync(() => directory.create(recursive: true));
    for (final brightness in Brightness.values) {
      final controller = createTestController(fixtureRequest);
      await controller.initialize();
      controller.settings = {
        ...controller.settings,
        'appearance': brightness.name,
      };
      await captureHomeLandscape(tester, directory, controller, brightness);
      controller.dispose();
    }
  });
  testWidgets('capture every product page in light and dark', (tester) async {
    final cjk = await loadCaptureFonts();
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    // Match the reference phone viewport. System status text and the home
    // indicator are outside Flutter's content and excluded by parity crops.
    tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });
    final directory = Directory(output);
    final layouts = <String, Object?>{};
    final capturedAtUtc = DateTime.now().toUtc().toIso8601String();
    await tester.runAsync(() => directory.create(recursive: true));
    await tester.runAsync(
      () => File('${directory.path}/capture-contract.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({
          'referenceViewport': [402, 874],
          'capturedAtUtc': capturedAtUtc,
          'layoutContract': 'layout-contract.json',
          'responsiveVariants': [
            {
              'viewport': [280, 620],
              'textScale': 2,
            },
            {
              'viewport': [620, 280],
              'textScale': 2,
            },
          ],
          'largeScreenCaptures': [
            {
              'screenshot': 'devices-tablet-light.png',
              'viewport': [1194, 834],
              'sourceFrame': 'H0TFx',
              'route': const DevicesRoute().location,
              'safeArea': {'top': 0, 'bottom': 0},
            },
            {
              'screenshot': 'device_workspace-desktop-light.png',
              'viewport': [1440, 960],
              'sourceFrame': 'zLBrM',
              'route': const WorkspaceRoute(deviceId: 'fixture').location,
              'safeArea': {'top': 0, 'bottom': 0},
            },
          ],
          'largeScreenTheme': 'Real production router and pages; captureTheme only replaces font families. Geometry, font sizes and weights retain production tokens.',
          'devicePixelRatio': 1,
          'safeArea': {'top': 54, 'bottom': 34},
          'systemChromeRendered': false,
          'materialBackend': 'widget-test-fallback',
          'font': cjk.existsSync() ? cjk.path : 'Flutter test defaults',
          'device': device,
          'fixtureScenarios': {
            'diagnostics_failed': failedDiagnosis,
            'transfer_details': partialTask,
            'receive_content': task,
            'file_search': {'initialPath': searchPath, 'query': '旅行', 'status': 'not-started'},
            'file_search_results': {'initialPath': searchPath, 'query': '旅行', 'status': 'completed'},
            'selected_session_tools': {'sessionId': 'screen'},
            'remote': {'state': 'paused', 'reason': 'renderer receipt unconfirmed', 'nativeTextureSubstituted': false},
            'qr_pair': {'payload': qrPayload, 'errorCorrectionLevel': 'L'},
          },
          'productionRouteCaptures': ['devices', 'transfers', 'settings', 'device_workspace', 'connection_form'],
          'visualAcceptanceComplete': false,
        })}\n',
      ),
    );
    for (final brightness in Brightness.values) {
      final controller = createTestController(fixtureRequest);
      final diagnosisController = createTestController(
        (command, [params = const {}]) async => command == 'device.diagnose'
            ? failedDiagnosis
            : fixtureRequest(command, params),
      );
      final partialTransferController = createTestController(
        (command, [params = const {}]) async =>
            command == 'transfers.get' &&
                params['transferId'] == partialTask['id']
            ? partialTask
            : fixtureRequest(command, params),
      );
      for (final fixtureController in [
        controller,
        diagnosisController,
        partialTransferController,
      ]) {
        await fixtureController.initialize();
        fixtureController.settings = {
          ...fixtureController.settings,
          'appearance': brightness.name,
        };
      }
      final pages = pageFixtures(
        controller,
        diagnosisController: diagnosisController,
        partialTransferController: partialTransferController,
      );
      for (final entry in pages.entries) {
        final boundary = GlobalKey();
        final productionRoute = switch (entry.key) {
          'devices' => const DevicesRoute().location,
          'transfers' => const TransfersRoute().location,
          'settings' => const SettingsRoute().location,
          'device_workspace' => const WorkspaceRoute(
            deviceId: 'fixture',
          ).location,
          'connection_form' => const ConnectionFormRoute().location,
          _ => null,
        };
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: productionRoute == null
                ? RouterTestApp(
                    key: ValueKey('${entry.key}-${brightness.name}'),
                    controller: entry.key == 'diagnostics_failed'
                        ? diagnosisController
                        : entry.key == 'transfer_details'
                        ? partialTransferController
                        : controller,
                    theme: captureTheme(brightness),
                    home: entry.value,
                  )
                : TestProviderScope(
                    controller: controller,
                    child: ConnectApp(
                      key: ValueKey('${entry.key}-${brightness.name}'),
                    ),
                  ),
          ),
        );
        if (productionRoute != null) {
          await tester.pumpAndSettle();
          final context = tester.element(find.byType(GlassTabBar));
          final router = GoRouter.of(context);
          if (['devices', 'transfers', 'settings'].contains(entry.key)) {
            router.go(productionRoute);
          } else {
            // Push over the actual devices tab so back behavior matches use.
            router.push<void>(productionRoute);
          }
          await tester.pumpAndSettle();
          if (['devices', 'transfers', 'settings'].contains(entry.key)) {
            expect(find.byType(GlassTabBar), findsOneWidget);
            expect(find.byType(BackButton), findsNothing);
          }
        }
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
        if (entry.key == 'diagnostics_failed') {
          expect(find.text('设备尚未连接'), findsOneWidget);
          expect(find.text('无法访问设备地址'), findsOneWidget);
          expect(find.text('设备连接正常'), findsNothing);
        }
        if (entry.key == 'transfer_details') {
          expect(find.text('重新传输'), findsOneWidget);
          expect(find.text('旅行清单.pdf'), findsOneWidget);
          expect(find.text('视频.mp4'), findsOneWidget);
          expect(find.text('资料.zip'), findsOneWidget);
        }
        if (entry.key == 'receive_content') {
          expect(find.text('取消本次传输'), findsOneWidget);
        }
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
        final screenshot = '${entry.key}-${brightness.name}.png';
        final layout = captureLayout(boundary);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final bytes = data!.buffer.asUint8List();
          await File('${directory.path}/$screenshot').writeAsBytes(bytes);
          layouts[screenshot] = {
            'screenshot': screenshot,
            'screenshotSha256': sha256.convert(bytes).toString(),
            'brightness': brightness.name,
            'captureScope': productionRoute == null
                ? 'isolated-page-fixture'
                : 'production-router',
            'route': productionRoute,
            ...layout,
          };
          await File('${directory.path}/layout-contract.json').writeAsString(
            '${const JsonEncoder.withIndent('  ').convert({
              'version': 1,
              'capturedAtUtc': capturedAtUtc,
              'referenceViewport': [402, 874],
              'visualAcceptanceComplete': false,
              'captures': layouts,
            })}\n',
          );
          image.dispose();
        });
      }
      if (brightness == Brightness.light) {
        tester.view.padding = const FakeViewPadding();
        tester.view.viewPadding = const FakeViewPadding();
        for (final wide in [
          (
            'devices-tablet-light.png',
            const Size(1194, 834),
            const DevicesRoute().location,
          ),
          (
            'device_workspace-desktop-light.png',
            const Size(1440, 960),
            const WorkspaceRoute(deviceId: 'fixture').location,
          ),
        ]) {
          tester.view.physicalSize = wide.$2;
          final boundary = GlobalKey();
          final router = createAppRouter();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: TestProviderScope(
                controller: controller,
                // Keep production routes, shell and root navigator. Only the
                // capture theme supplies the native CJK family to standalone
                // ListTile styles which otherwise use the test engine font.
                child: MaterialApp.router(
                  key: ValueKey(wide.$1),
                  routerConfig: router,
                  theme: captureTheme(brightness),
                  debugShowCheckedModeBanner: false,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (wide.$3 != const DevicesRoute().location) {
            router.push<void>(wide.$3);
            await tester.pumpAndSettle();
          }
          await waitForPageImages(tester);
          expect(tester.takeException(), isNull, reason: wide.$1);
          final layout = captureLayout(boundary);
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            expect(
              Size(image.width.toDouble(), image.height.toDouble()),
              wide.$2,
            );
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final bytes = data!.buffer.asUint8List();
            await File('${directory.path}/${wide.$1}').writeAsBytes(bytes);
            layouts[wide.$1] = {
              'screenshot': wide.$1,
              'screenshotSha256': sha256.convert(bytes).toString(),
              'brightness': brightness.name,
              'captureScope': 'production-router',
              'appBootstrap': 'createAppRouter with native-font capture theme',
              'safeArea': {'top': 0, 'bottom': 0},
              'route': wide.$3,
              ...layout,
            };
            await File('${directory.path}/layout-contract.json').writeAsString(
              '${const JsonEncoder.withIndent('  ').convert({
                'version': 1,
                'capturedAtUtc': capturedAtUtc,
                'referenceViewport': [402, 874],
                'visualAcceptanceComplete': false,
                'captures': layouts,
              })}\n',
            );
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox());
          router.dispose();
        }
        tester.view.physicalSize = const Size(402, 874);
        tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
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
        if (layout.$1 == 'landscape') {
          await captureHomeLandscape(tester, directory, controller, brightness);
          continue;
        }
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
      diagnosisController.dispose();
      partialTransferController.dispose();
    }
  });
}
