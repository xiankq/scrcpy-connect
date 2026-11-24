import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/platform/platform_window_host.dart';
import 'package:scrcpy_connect/core/platform/window_launch_route.dart';

void main() {
  test('an independent route only carries its issued window identity', () {
    final route = independentWindowLaunchRoute('window/id');
    expect(decodeIndependentWindowLaunchRoute(route), 'window/id');
    expect(decodeIndependentWindowLaunchRoute('/devices'), isNull);
    expect(decodeIndependentWindowLaunchRoute('/__independent_remote'), isNull);
  });

  test('the host must confirm the exact identity it opened', () async {
    Map<String, dynamic>? received;
    final host = PlatformWindowHost(
      request: (command, params) async {
        expect(command, 'window.openIndependent');
        received = params;
        return {'supported': true, 'windowId': params['windowId']};
      },
    );
    final receipt = await host.open(
      windowId: 'window-a',
      title: 'Pixel · 手机屏幕',
      aspectRatio: .45,
    );
    expect(receipt.opened, isTrue);
    expect(receipt.windowId, 'window-a');
    expect(received?['initialRoute'], independentWindowLaunchRoute('window-a'));
    expect(received?['aspectRatio'], .45);

    final mismatched = PlatformWindowHost(
      request: (_, _) async => {'supported': true, 'windowId': 'another'},
    );
    expect(
      (await mismatched.open(windowId: 'window-a', title: 'Pixel')).opened,
      isFalse,
    );
  });

  test('an unavailable host falls back to the inline page', () async {
    final host = PlatformWindowHost(
      request: (command, params) => throw MissingPluginException(command),
    );
    final receipt = await host.open(windowId: 'window-a', title: 'Pixel');
    expect(receipt.opened, isFalse);
    expect(receipt.reason, contains('未提供'));
  });
}
