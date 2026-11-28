import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/pages/gallery/preview/media_preview_page.dart';
import 'package:scrcpy_connect/pages/gallery/preview/widgets/media_preview_toolbar.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/content/cached_file_image.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';

void main() {
  testWidgets('Duo 照片返回键移到侧边栏起点，画面仍可点击', (tester) async {
    var backTaps = 0;
    var mediaTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: Scaffold(
          body: liquid.GlassVerticalBar(
            data: const liquid.GlassVerticalBarData(
              edge: liquid.GlassVerticalBarEdge.trailing,
              width: 84,
              top: 120,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => mediaTaps++,
                ),
                MediaPreviewToolbar(
                  title: 'test.png',
                  onBack: () => backTaps++,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final back = find.byType(GlassToolbarIconButton);
    expect(tester.getTopLeft(back).dy, 120);
    expect(tester.getCenter(find.text('test.png')).dy, lessThan(120));
    await tester.tap(back);
    await tester.tapAt(const Offset(400, 400));
    expect(backTaps, 1);
    expect(mediaTaps, 1);
  });

  testWidgets('图片取回和系统分享位于底栏，画面可切换原尺寸', (tester) async {
    final content = _Content();
    final decoded = Completer<ImageInfo>();
    final image = CachedFileImage(File('/test.png'));
    final cache = PaintingBinding.instance.imageCache;
    cache.putIfAbsent(
      image,
      () => OneFrameImageStreamCompleter(decoded.future),
    );
    addTearDown(() => cache.evict(image));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [contentReaderProvider.overrideWithValue(content)],
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: const MediaPreviewPage(
            device: DeviceSnapshot(id: 'test'),
            file: FileCatalogEntry(
              name: 'test.png',
              path: '/test.png',
              mime: 'image/png',
            ),
          ),
        ),
      ),
    );
    final retrieve = find.widgetWithText(TextButton, '取回原件');
    expect(retrieve, findsOneWidget);
    expect(
      tester.getCenter(retrieve).dy,
      greaterThan(tester.getCenter(find.text('test.png')).dy),
    );
    content.response.complete(const CachedContent(path: '/test.png'));
    await tester.pump();

    final viewer = find.byType(InteractiveViewer);
    final loader = find.byType(ContentLoadingIndicator);
    final viewport = find.byType(Scaffold);
    expect(tester.getCenter(loader), tester.getCenter(viewport));
    expect(viewer, findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '原尺寸'));
    await tester.pump();
    expect(tester.getCenter(loader), tester.getCenter(viewport));
    expect(viewer, findsNothing);

    final frame = await tester.runAsync(
      () => createTestImage(width: 16, height: 32, cache: false),
    );
    decoded.complete(ImageInfo(image: frame!));
    await tester.pumpAndSettle();
    expect(loader, findsNothing);
    expect(tester.widget<InteractiveViewer>(viewer).constrained, isFalse);
    await tester.tap(find.widgetWithText(TextButton, '适合屏幕'));
    await tester.pump();
    expect(tester.widget<InteractiveViewer>(viewer).constrained, isTrue);
  });
}

class _Content implements ContentReader {
  final response = Completer<CachedContent>();

  @override
  Future<CachedContent> preview({
    required String deviceId,
    required String path,
  }) => response.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
