import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/platform/platform_window_host.dart';
import 'package:scrcpy_connect/core/platform/window_launch_route.dart';

void main() {
  test('encodes and decodes a second-engine launch route', () {
    final route = independentWindowLaunchRoute(
      deviceId: 'device/a',
      packageName: 'com.example.app',
      sessionId: 'session-a',
    );
    expect(decodeIndependentWindowLaunchRoute(route), {
      'deviceId': 'device/a',
      'packageName': 'com.example.app',
      'sessionId': 'session-a',
    });
  });

  test('accepts only a host-confirmed native window', () async {
    Map<String, dynamic>? received;
    final host = PlatformWindowHost(
      request: (command, params) async {
        received = params;
        return {'supported': true, 'windowId': 'window-b'};
      },
    );
    final receipt = await host.open(
      deviceId: 'device-a',
      packageName: 'com.example.app',
      sessionId: 'session-a',
    );
    expect(receipt.opened, isTrue);
    expect(receipt.windowId, 'window-b');
    expect(received?['initialRoute'], contains('/__independent_remote'));
  });

  test('falls back explicitly when a host cannot create a window', () async {
    final host = PlatformWindowHost(
      request: (command, params) async => {'reason': '仅支持同页分栏'},
    );
    final receipt = await host.open(
      deviceId: 'device-a',
      packageName: 'com.example.app',
      sessionId: 'session-a',
    );
    expect(receipt.opened, isFalse);
    expect(receipt.reason, '仅支持同页分栏');
  });

  test(
    'missing native channel is a visible fallback, not a false success',
    () async {
      final host = PlatformWindowHost(
        request: (command, params) => throw MissingPluginException(command),
      );
      final receipt = await host.open(
        deviceId: 'device-a',
        packageName: 'com.example.app',
        sessionId: 'session-a',
      );
      expect(receipt.opened, isFalse);
      expect(receipt.reason, contains('未提供'));
    },
  );
}
