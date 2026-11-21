import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/pages/gallery/preview/media_preview_page.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  testWidgets('图片取回和系统分享位于底栏，画面可切换原尺寸', (tester) async {
    final content = _Content();
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
    final retrieve = find.widgetWithText(TextButton, '取回文件');
    expect(retrieve, findsOneWidget);
    expect(
      tester.getCenter(retrieve).dy,
      greaterThan(tester.getCenter(find.text('test.png')).dy),
    );
    content.response.complete(const CachedContent(path: '/test.png'));
    await tester.pump();

    final viewer = find.byType(InteractiveViewer);
    expect(tester.widget<InteractiveViewer>(viewer).constrained, isTrue);
    await tester.tap(find.widgetWithText(TextButton, '原尺寸'));
    await tester.pump();
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
