/// Opt-in host captures for the pages touched by the October design refinement.
/// Run from app/ with DESIGN_REFINEMENT_CAPTURE_DIR=/tmp/capture flutter test
/// test/design_refinement_capture.dart. This is a capture tool, not a golden
/// approval: production widgets use the host's software/frosted glass fallback.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/connection/index/connection_index_page.dart';
import 'package:scrcpy_connect/pages/devices/details/connection_preferences/devices_details_connection_preferences_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_hero.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

const _size = Size(402, 874);
const _safeArea = EdgeInsets.only(top: 54, bottom: 34);
const _device = <String, dynamic>{
  'id': 'phone',
  'name': '我的手机',
  'model': 'Pixel 9',
  'apiLevel': 35,
  'transport': 'tls',
  'address': '192.168.1.8',
  'port': 37123,
  'status': 'connected',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final outputPath = Platform.environment['DESIGN_REFINEMENT_CAPTURE_DIR'];
  final fontPath =
      Platform.environment['DESIGN_REFINEMENT_CAPTURE_FONT'] ??
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';

  setUpAll(() async {
    if (outputPath == null || outputPath.isEmpty) return;
    // Load declared icon fonts so Lucide glyphs retain their actual shapes.
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    // Widget tests otherwise use Ahem. Register the host CJK font under the
    // framework's test/default families without changing production ThemeData.
    final font = await File(fontPath).readAsBytes();
    for (final family in ['Ahem', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
    }
  });

  testWidgets(
    'capture the affected production pages at their real logical size',
    (tester) async {
      final output = Directory(outputPath!);
      await tester.runAsync(() => output.create(recursive: true));
      tester.view.physicalSize = _size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(
        top: _safeArea.top,
        bottom: _safeArea.bottom,
      );
      tester.view.viewPadding = FakeViewPadding(
        top: _safeArea.top,
        bottom: _safeArea.bottom,
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);

      final iconBytes = await tester.runAsync(
        () =>
            File('../designs/assets/android-settings-api36.png').readAsBytes(),
      );
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final device = {
        ..._device,
        'battery': 78,
        'charging': true,
        'batteryUpdatedAt': now,
      };
      final frames = <Json>[];
      final controllers = <AppController>[];
      final calls = <String>[];
      final captureKey = GlobalKey();
      AppController controller() {
        final next = createTestController((command, [params = const {}]) async {
          calls.add(command);
          return switch (command) {
            'apps.list' => {
              'deviceId': 'phone',
              'source': 'runningTasks',
              'live': true,
              'apps': [
                {
                  'name': '设置',
                  'packageName': 'com.android.settings',
                  'userId': 0,
                  'taskId': 79,
                },
              ],
            },
            'apps.icon' => {
              'deviceId': 'phone',
              'packageName': params['packageName'],
              'userId': 0,
              'mimeType': 'image/png',
              'dataBase64': base64Encode(iconBytes!),
            },
            'identity.device.get' => {
              'scope': 'global',
              'fingerprint': 'fixture:0123456789abcdef0123456789abcdef',
            },
            'devices.pair.qr' => {
              'attemptId': 'capture-only-qr',
              'payload': 'WIFI:T:ADB;S:adb-Interconnect;P:1234567890123456;;',
              'expiresAt': now + 300,
            },
            _ => {},
          };
        });
        next.settings = {
          'qualityPreset': 'balanced',
          'deviceQuality': <String, dynamic>{},
          'deviceSettings': {
            'phone': {'showNavigationBar': true},
          },
        };
        controllers.add(next);
        return next;
      }

      Future<void> mount(AppController current, Widget page) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: RouterTestApp(
              controller: current,
              theme: ConnectTokens.theme(Brightness.light),
              home: page,
              devices: [device],
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Json rect(Finder finder) {
        final box = tester.getRect(finder.first);
        return {
          'x': box.left,
          'y': box.top,
          'width': box.width,
          'height': box.height,
          'intersectsViewport': box.overlaps(Offset.zero & _size),
        };
      }

      Future<void> capture(
        String name, {
        required String pencil,
        required String scope,
      }) async {
        await tester.pumpAndSettle();
        // Decode the actual returned PNG before taking a software frame. The
        // widget-test clock alone does not wait for asynchronous image codecs.
        await tester.runAsync(() async {
          for (final element in find.byType(Image).evaluate()) {
            final image = element.widget as Image;
            await precacheImage(image.image, element);
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        expect(boundary.size, _size);
        final layout = <String, dynamic>{};
        for (final label in [
          '我的手机',
          '添加设备',
          '连接配置',
          '画面设置',
          '已连接',
          '无线调试',
          '均衡',
          '在独立窗口打开',
          '在手机屏幕打开',
          '取消',
          '全局私钥',
          '连接设备',
          '配对并连接',
          '检查连接',
          '重新生成',
          '连接帮助',
        ]) {
          final found = find.text(label);
          if (found.evaluate().isNotEmpty) layout[label] = rect(found);
        }
        if (find.byType(DeviceHero).evaluate().isNotEmpty) {
          layout['DeviceHero'] = rect(find.byType(DeviceHero));
        }
        final fields = find.byType(TextFormField);
        for (var index = 0; index < fields.evaluate().length; index++) {
          layout['TextFormField$index'] = rect(fields.at(index));
        }
        final identity = find.byType(ConnectSelectionField<String>);
        if (identity.evaluate().isNotEmpty) {
          layout['identitySelectionField'] = rect(identity);
        }
        for (final (key, button) in [
          ('primaryOpenAction', find.widgetWithText(FilledButton, '在独立窗口打开')),
          (
            'secondaryOpenAction',
            find.widgetWithText(OutlinedButton, '在手机屏幕打开'),
          ),
        ]) {
          if (button.evaluate().isNotEmpty) layout[key] = rect(button);
        }
        final quality = find.widgetWithText(ActionRow, '画面设置');
        if (quality.evaluate().isNotEmpty) {
          layout['qualityActionRow'] = rect(quality);
        }
        final scroll = [
          for (final state in tester.stateList<ScrollableState>(
            find.byType(Scrollable),
          ))
            {
              'axisDirection': state.axisDirection.name,
              'offset': state.position.pixels,
              'viewport': state.position.viewportDimension,
              'maxScrollExtent': state.position.maxScrollExtent,
            },
        ];
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('${output.path}/$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        frames.add({
          'name': name,
          'pencilReference': pencil,
          'scope': scope,
          'layout': layout,
          'scroll': scroll,
        });
      }

      try {
        final workspaceController = controller();
        await mount(
          workspaceController,
          DeviceWorkspacePage(controller: workspaceController, device: device),
        );
        await capture(
          'workspace-main',
          pencil: 'nqQEb',
          scope: 'Production workspace at scroll origin; includes first card and first fixed setting rows.',
        );
        unawaited(
          openPhoneApp(
            tester.element(find.byType(DeviceWorkspacePage)),
            device,
            {'name': '地图', 'packageName': 'com.google.android.apps.maps'},
          ),
        );
        await capture(
          'app-open-method',
          pencil: 'tch6A',
          scope: 'Actual modal sheet over the workspace; full viewport, no crop or enlargement to match the Pencil component board.',
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        final settingsTitle = find.text('设备设置');
        await Scrollable.ensureVisible(
          tester.element(settingsTitle),
          alignment: .13,
        );
        await tester.pumpAndSettle();
        await capture(
          'workspace-settings',
          pencil: 'YLhiR',
          scope: 'Scrolled production workspace; the Pencil reference is a taller settings detail board. Only the actual 874px viewport is captured.',
        );

        for (final mode in [
          AddDeviceMode.ip,
          AddDeviceMode.pairing,
          AddDeviceMode.usb,
          AddDeviceMode.qr,
        ]) {
          final current = controller();
          await mount(
            current,
            AddDevicePage(controller: current, initialMode: mode),
          );
          await capture(
            'add-${mode.name}',
            pencil: switch (mode) {
              AddDeviceMode.ip => 'OpFKk',
              AddDeviceMode.pairing => 'W3GRn',
              AddDeviceMode.usb => 'OxUaB',
              AddDeviceMode.qr => 'G4CpTk',
            },
            scope:
                'Production unified add form, ${mode.name} selected, draft fields left empty except the real default port; QR comes from the isolated request fixture.',
          );
        }

        final configurationController = controller();
        final record = {...device, 'address': '192.168.31.22'};
        await mount(
          configurationController,
          DeviceConnectionPreferencesPage(
            controller: configurationController,
            device: record,
          ),
        );
        await capture(
          'connection-config-ip',
          pencil: 'q3bM72',
          scope: 'Existing device configuration defaults to its saved IP mode; global identity source is read-only and fingerprint is available by tooltip.',
        );
        await tester.tap(find.text('无线配对码'));
        await tester.pumpAndSettle();
        await capture(
          'connection-config-pairing',
          pencil: 'q3bM72',
          scope: 'The same production configuration form after selecting wireless pairing; read-only saved identity remains in place.',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => File('${output.path}/layout.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'logicalSize': {'width': _size.width, 'height': _size.height},
              'devicePixelRatio': 1,
              'safeArea': {'top': _safeArea.top, 'bottom': _safeArea.bottom},
              'theme': 'ConnectTokens.theme(Brightness.light), unchanged production theme',
              'font': {
                'path': fontPath,
                'registration': 'Host Noto CJK registered as Ahem and Roboto to replace the widget-test font; declared package icon fonts loaded from FontManifest.',
              },
              'evidenceBoundary': 'Host Flutter widget software rasterization; glass uses the declared frosted fallback. System status/navigation content is absent; only safe-area insets are reserved. No AVD, Android build, native host surface, or GPU optical acceptance is implied.',
              'fixture': 'Isolated AppController request fixture, actual checked-in Android settings icon; no request is sent to a device.',
              'commands': calls,
              'frames': frames,
            }),
          ),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final current in controllers) {
          current.dispose();
        }
      }
    },
    skip: outputPath == null || outputPath.isEmpty,
  );
}
