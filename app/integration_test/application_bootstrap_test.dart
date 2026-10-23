import 'dart:io';
import 'dart:ui' as ui;

import 'package:device_runtime/src/native_runtime.dart';
import 'package:device_runtime/src/rust/api.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as application;
import 'package:scrcpy_connect/pages/startup_error/startup_error_page.dart';
import 'package:scrcpy_connect/services/app_dependencies.dart';
import 'package:scrcpy_connect/services/application_diagnostics.dart';

class _IsolatedPaths extends PathProviderPlatform {
  _IsolatedPaths(this.root);
  final Directory root;

  @override
  Future<String> getApplicationSupportPath() async => '${root.path}/support';

  @override
  Future<String> getTemporaryPath() async => '${root.path}/temporary';
}

class _BootstrapBinding extends IntegrationTestWidgetsFlutterBinding {
  final captureKey = GlobalKey();

  @override
  Widget wrapWithDefaultView(Widget rootWidget) => super.wrapWithDefaultView(
    RepaintBoundary(key: captureKey, child: rootWidget),
  );
}

/// Runs the normal main/bootstrap with real packaged ADB and Rust. Only the
/// support/temp directory provider is replaced, preserving user data.
void main() {
  final binding = _BootstrapBinding();
  testWidgets('normal application main opens its interface and media cache', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'application-bootstrap-',
    );
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _IsolatedPaths(root);
    AppDependencies? dependencies;
    try {
      await tester.runAsync(application.main);
      await tester.pump();
      expect(find.byType(StartupErrorPage), findsNothing);
      expect(find.byType(ConnectApp), findsOneWidget);
      final context = tester.element(find.byType(ConnectApp));
      dependencies = ProviderScope.containerOf(context)
          .read(appDependenciesProvider);
      await tester.runAsync(() async {
        final status = await dependencies!.request('media.cache.status');
        expect(status, isA<Map<String, dynamic>>());
      });
      await tester.pump(const Duration(seconds: 1));
      final boundary =
          binding.captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final capture = Directory(
            Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
                '${Directory.systemTemp.path}/application-bootstrap',
          );
          await capture.create(recursive: true);
          await File('${capture.path}/main.png').writeAsBytes(
            png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
            flush: true,
          );
          binding.reportData = {
            'applicationBootstrap': {
              'platform': Platform.operatingSystem,
              'mainEntry': true,
              'startupError': false,
              'cacheStatusReadable': true,
              'width': image.width,
              'height': image.height,
            },
          };
        } finally {
          image.dispose();
        }
      });
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        try {
          await dependencies?.close?.call();
        } finally {
          try {
            await core.shutdown();
          } finally {
            try {
              await shutdownNativeAdb();
              await (await applicationDiagnostics()).close();
            } finally {
              PathProviderPlatform.instance = originalPaths;
              await root.delete(recursive: true);
            }
          }
        }
      });
    }
  });
}
