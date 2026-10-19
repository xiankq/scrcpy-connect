import 'support/router_test_app.dart';
import 'support/test_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/devices/details/diagnostics/devices_details_diagnostics_page.dart';

void main() {
  const device = <String, dynamic>{
    'id': 'phone',
    'name': '测试手机',
    'address': '192.0.2.1',
    'port': 5555,
    'transport': 'tls',
    'status': 'offline',
  };

  testWidgets(
    'Rust diagnosis fields explain reachability and authorization separately',
    (tester) async {
      var checks = 0;
      final current = <String, dynamic>{
        ...device,
        'address': '192.0.2.2',
        'port': 37001,
        'status': 'unauthorized',
        'reason': '被控手机已撤销本机授权。',
      };
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        expect(command, 'device.diagnose');
        expect(params, {'deviceId': 'phone'});
        checks++;
        // Matches Runtime::diagnose, which has no checks/message fields.
        return {
          'deviceId': 'phone',
          'device': current,
          'connected': false,
          'tcpReachable': true,
          'usbBackendAvailable': true,
          'wirelessProperties': null,
          'identityPresent': true,
          'tlsProvider': 'experimental provider detail',
          'notes': ['配对端口与连接端口不同。'],
        };
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          devices: [device],
          home: DiagnosticsPage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('网络地址可达'), findsOneWidget);
      expect(find.text('需要重新授权'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '重新授权'), findsOneWidget);
      expect(find.text('被控手机已撤销本机授权。'), findsOneWidget);
      expect(find.textContaining('192.0.2.2'), findsOneWidget);
      expect(find.text('配对端口与连接端口不同。'), findsOneWidget);
      expect(find.textContaining('experimental provider'), findsNothing);
      await tester.ensureVisible(find.text('重新检查'));
      await tester.tap(find.text('重新检查'));
      await tester.pumpAndSettle();
      expect(checks, 2);
      await tester.ensureVisible(find.text('编辑地址与端口'));
      await tester.tap(find.text('编辑地址与端口'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionFormPage), findsOneWidget);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[0].controller!.text, '192.0.2.2');
      expect(fields[1].controller!.text, '37001');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'unreachable TCP and unsupported USB provide different next steps',
    (tester) async {
      for (final usb in [false, true]) {
        final current = <String, dynamic>{
          ...device,
          'transport': usb ? 'usb' : 'tls',
        };
        final controller = createTestController(
          (command, [params = const {}]) async => {
            'device': current,
            'connected': false,
            'tcpReachable': usb ? null : false,
            'usbBackendAvailable': false,
            'identityPresent': true,
            'notes': <Object?>[],
          },
        );
        await tester.pumpWidget(
          RouterTestApp(
            key: ValueKey(usb),
            controller: controller,
            home: DiagnosticsPage(controller: controller, device: current),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(usb ? '当前平台无法使用 USB' : '无法访问设备地址'), findsOneWidget);
        expect(find.text('需要重新授权'), findsNothing);
        expect(find.widgetWithText(TextButton, '改用 USB'), findsNothing);
        expect(find.widgetWithText(TextButton, '改用无线连接'), findsOneWidget);
        expect(find.textContaining(usb ? '改用无线连接' : 'VPN'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'missing probe results remain unknown rather than claiming failure or trust',
    (tester) async {
      final controller = createTestController(
        (command, [params = const {}]) async => <String, dynamic>{},
      );
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: DiagnosticsPage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('连接状态尚未确认'), findsOneWidget);
      expect(find.text('网络路径尚未检查'), findsOneWidget);
      expect(find.text('本机授权身份尚未确认'), findsOneWidget);
      expect(find.text('网络地址可达'), findsNothing);
      expect(find.text('需要重新授权'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
