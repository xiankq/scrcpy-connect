import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as application;
import 'package:scrcpy_connect/pages/startup_error/startup_error_page.dart';
import 'package:scrcpy_connect/bootstrap/app_dependencies.dart';
import 'package:scrcpy_connect/services/platform/application_diagnostics.dart';

class _IsolatedPaths extends PathProviderPlatform {
  _IsolatedPaths(this.root);
  final Directory root;

  @override
  Future<String> getApplicationSupportPath() async => '${root.path}/support';

  @override
  Future<String> getTemporaryPath() async => '${root.path}/temporary';
}

/// 运行正常 main 与启动流程，使用真实打包的 ADB 和 Rust；仅替换支持目录和临时目录提供方以保留用户数据。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
      // 测试启动器可能已创建绑定，复用它并截取实际根图层，避免二次初始化绑定。
      final view = binding.renderViews.single;
      final layer = view.debugLayer! as OffsetLayer;
      await tester.runAsync(() async {
        final image = await layer.toImage(view.paintBounds);
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
            await (await applicationDiagnostics()).close();
          } finally {
            PathProviderPlatform.instance = originalPaths;
            await root.delete(recursive: true);
          }
        }
      });
    }
  });
}
