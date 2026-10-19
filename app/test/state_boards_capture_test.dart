import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/usb/connection_usb_page.dart';
import 'package:scrcpy_connect/pages/devices/details/connection_preferences/devices_details_connection_preferences_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/calls/devices_workspace_calls_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/index/devices_workspace_gallery_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/index/transfers_details_index_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'ios_pages_capture_test.dart' as capture;
import 'support/router_test_app.dart';
import 'support/test_controller.dart';

final _device = <String, dynamic>{...capture.device, 'name': 'Pixel 9 Pro'};
const _incoming = <String, dynamic>{
  'id': 'incoming',
  'name': '李明',
  'number': '138 0000 1234',
  'deviceId': 'fixture',
  'state': 'ringing',
  'canAnswer': true,
  'canReject': true,
};
const _active = <String, dynamic>{
  'id': 'active',
  'name': '李明',
  'number': '138 0000 1234',
  'deviceId': 'fixture',
  'state': 'active',
  'canHangup': true,
  'canSetRoute': true,
  'routes': [
    {'id': 'phone', 'name': '被控手机'},
    {'id': 'headset', 'name': '本机耳机'},
  ],
};
Json _calls(List<Json> calls, {bool limited = false}) => {
  'status': limited ? 'limited' : 'available',
  'live': true,
  'controlStatus': 'available',
  'audioStatus': limited ? 'limited' : 'available',
  'audioRoute': limited ? '声音与麦克风继续由被控手机处理' : '声音与收音：本机耳机',
  if (limited) 'reason': '当前可以控制接听和挂断，但本机尚不能收听和收音。',
  'calls': calls,
};
Json _scan(String status, {bool empty = false}) => {
  'scanId': 'board-gallery',
  'deviceId': 'fixture',
  'status': status,
  'offset': 0,
  'items': status == 'scanning' || empty
      ? <Json>[]
      : [
          for (var i = 0; i < 6; i++)
            {
              ...capture.photo,
              'path': '/sdcard/DCIM/湖边$i.jpg',
              'name': '湖边$i.jpg',
            },
        ],
  'total': empty || status == 'scanning' ? 0 : 18,
  if (status == 'partial') 'nextOffset': 6,
  'visitedDirectories': 42,
  'visitedEntries': 1280,
  'currentDirectory': '/sdcard/Download/旅行',
  'scope': {
    'roots': ['/sdcard/DCIM', '/sdcard/Pictures', '/sdcard/Download'],
    'excluded': ['/sdcard/Android/data', '/sdcard/Android/obb'],
  },
  'issueCount': 2,
  'issues': [
    {
      'path': '/sdcard/Android/media/旅行',
      'code': 'permission_denied',
      'reason': '无法读取',
    },
    {
      'path': '/sdcard/Pictures/共享',
      'code': 'permission_denied',
      'reason': '无法读取',
    },
  ],
};

class _StateCase {
  const _StateCase(
    this.name,
    this.node,
    this.page, {
    this.overrides = const {},
    this.prepare,
    this.expected = const [],
    this.note,
  });
  final String name;
  final String node;
  final Widget Function(AppController) page;
  final Map<String, Json> overrides;
  final Future<void> Function(WidgetTester)? prepare;
  final List<String> expected;
  final String? note;
}

Future<void> _frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final output = Platform.environment['CONNECT_STATE_CAPTURE_DIR'];
  if (output == null) return;
  testWidgets(
    'capture remaining source states using production page branches',
    (tester) async {
      for (final font in [
        (
          'packages/lucide_icons_flutter/Lucide',
          'packages/lucide_icons_flutter/assets/lucide.ttf',
        ),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) {
        await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
      }
      final cjk = File(
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      );
      expect(
        cjk.existsSync(),
        isTrue,
        reason: 'State captures require the same native CJK typeface.',
      );
      for (final family in ['Roboto', 'ConnectCaptureCJK', 'Ahem']) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(cjk.readAsBytesSync())),
            ))
            .load();
      }
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });
      final directory = Directory(output);
      await tester.runAsync(() => directory.create(recursive: true));
      final cases = [
        _StateCase(
          'calls-limited',
          'LVKgj',
          (c) => CallsPage(controller: c, device: _device),
          overrides: {
            'calls.list': _calls([_incoming], limited: true),
          },
          expected: ['通话与声音', '接听', '拒接'],
        ),
        _StateCase(
          'calls-active',
          'aLUZD',
          (c) => CallsPage(controller: c, device: _device),
          overrides: {
            'calls.list': _calls([_active]),
          },
          expected: ['挂断', '声音路由'],
          note: 'Runtime has no duration, mute or speaker controls; route capability is explicit.',
        ),
        _StateCase(
          'calls-waiting-same-device',
          'oBEk5',
          (c) => CallsPage(controller: c, device: _device),
          overrides: {
            'calls.list': _calls([
              _active,
              {..._incoming, 'name': '王宁'},
            ]),
          },
          expected: ['李明', '王宁'],
          note: 'Two calls belong to the same requested device. Does not claim to reproduce the source cross-device composition.',
        ),
        _StateCase(
          'remote-resource-busy',
          'HjBtR',
          (c) => RemotePage(controller: c, device: _device),
          overrides: {
            'session.list': {'sessions': <Json>[]},
          },
          expected: ['管理当前活动'],
          note: 'session.start rejects resource_busy; native texture is neither invented nor substituted.',
        ),
        _StateCase(
          'usb-waiting-authorization',
          'ONn92',
          (c) => UsbGuidePage(controller: c),
          overrides: {
            'devices.usb': {
              'connected': false,
              'message': '等待被控手机授权',
              'devices': [
                {'serial': 'Pixel9Pro', 'status': 'unauthorized'},
              ],
            },
          },
          prepare: (t) async {
            await t.tap(find.text('已连接，检查授权'));
            await _frames(t);
          },
          expected: ['等待被控手机授权'],
          note: 'App result after checking; the Android USB permission dialog remains system-owned.',
        ),
        _StateCase(
          'usb-wireless-check',
          'vPWPs',
          (c) => DeviceConnectionPreferencesPage(
            controller: c,
            device: {..._device, 'transport': 'usb'},
          ),
          overrides: {
            'devices.wireless': {'message': 'USB 授权已确认，请核对手机网络地址与连接条件。'},
          },
          prepare: (t) async {
            await t.tap(find.text('检查 USB 转无线'));
            await _frames(t, 2);
          },
          expected: ['USB 授权已确认，请核对手机网络地址与连接条件。'],
          note: 'Actual source is device connection preferences action and feedback, not UsbGuidePage or a synthetic three-step wizard.',
        ),
        _StateCase(
          'transfer-conflict',
          'K950NO',
          (c) => TransferDetailsPage(
            controller: c,
            task: {...capture.task, 'status': 'conflict'},
          ),
          overrides: {
            'transfers.get': {
              ...capture.task,
              'status': 'conflict',
              'canCancel': true,
            },
          },
          expected: ['目标中已有同名内容', '保留两份', '替换目标内容', '跳过此项'],
        ),
        _StateCase(
          'gallery-scanning',
          'KFfP4',
          (c) => GalleryPage(controller: c, device: _device),
          overrides: {'media.list': _scan('scanning')},
          expected: ['正在检查手机中的照片与视频', '停止检查'],
        ),
        _StateCase(
          'gallery-partial',
          'x4oRdN',
          (c) => GalleryPage(controller: c, device: _device),
          overrides: {'media.list': _scan('partial')},
          expected: ['部分目录未能检查', '加载更多'],
        ),
        _StateCase(
          'gallery-cancelled-empty',
          's4p7JF',
          (c) => GalleryPage(controller: c, device: _device),
          overrides: {'media.list': _scan('cancelled', empty: true)},
          expected: ['已停止检查', '已检查范围内没有可显示的内容'],
        ),
        _StateCase(
          'gallery-scope',
          'UwGyp',
          (c) => GalleryPage(controller: c, device: _device),
          overrides: {'media.list': _scan('partial')},
          prepare: (t) async {
            await t.tap(find.text('相册范围与未读项目'));
            await _frames(t);
          },
          expected: ['本次检查范围', '关闭范围'],
        ),
        _StateCase(
          'gallery-multi-select',
          'Wa6hu',
          (c) => GalleryPage(controller: c, device: _device),
          overrides: {'media.list': _scan('partial')},
          prepare: (t) async {
            await t.tap(find.byTooltip('选择照片'));
            await t.pump();
            for (var i = 0; i < 3; i++) {
              await t.tap(find.bySemanticsLabel('湖边$i.jpg'));
              await t.pump();
            }
          },
          expected: ['已选择 3 项', '保存原文件'],
        ),
      ];
      final layouts = <String, Object?>{};
      final timestamp = DateTime.now().toUtc().toIso8601String();
      for (final scenario in cases) {
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          if (scenario.name == 'remote-resource-busy' &&
              command == 'session.start') {
            throw const RequestFailure('resource_busy', '设备资源暂时不足，请管理当前活动后重试。');
          }
          if (command == 'media.thumbnail') {
            return {
              'localPath': File('../designs/assets/sample-lake.jpg')
                  .absolute
                  .path,
              'mime': 'image/jpeg',
            };
          }
          return scenario.overrides[command] ??
              await capture.fixtureRequest(command, params);
        });
        await controller.initialize();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: RouterTestApp(
              key: ValueKey(scenario.name),
              controller: controller,
              theme: capture.captureTheme(Brightness.light),
              home: scenario.page(controller),
            ),
          ),
        );
        await _frames(tester);
        await capture.waitForPageImages(tester);
        await scenario.prepare?.call(tester);
        await capture.waitForPageImages(tester);
        for (final text in scenario.expected) {
          expect(find.text(text), findsWidgets, reason: scenario.name);
        }
        expect(tester.takeException(), isNull, reason: scenario.name);
        final name = '${scenario.name}.png';
        final layout = capture.captureLayout(boundary);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final bytes = data!.buffer.asUint8List();
          await File('${directory.path}/$name').writeAsBytes(bytes);
          image.dispose();
          layouts[name] = {
            'sourceState': scenario.node,
            'projectionNote': scenario.note,
            'screenshotSha256': sha256.convert(bytes).toString(),
            'fixtureOverrides': scenario.overrides,
            'captureScope': 'production page with scoped bridge fixtures and font-only captureTheme',
            ...layout,
          };
          await File('${directory.path}/layout-contract.json').writeAsString(
            '${const JsonEncoder.withIndent('  ').convert({
              'capturedAtUtc': timestamp,
              'viewport': [402, 874],
              'devicePixelRatio': 1,
              'safeArea': {'top': 54, 'bottom': 34},
              'font': cjk.path,
              'materialBackend': 'widget-test-fallback',
              'visualAcceptanceComplete': false,
              'captures': layouts,
            })}\n',
          );
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        controller.dispose();
      }
    },
  );
}
