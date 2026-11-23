import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/content/content_cache.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';

void main() {
  testWidgets(
    '系统确认取消后可以直接重开，已交接才要求核对接收应用',
    variant: const TargetPlatformVariant({TargetPlatform.android}),
    (tester) async {
      var launches = 0;
      final messenger = tester.binding.defaultBinaryMessenger;
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'share');
        return ++launches == 2 ? 'fixture.receiver' : '';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentCacheControlProvider.overrideWithValue(_Cache()),
            contentReaderProvider.overrideWithValue(_Reader()),
            transferCacheLeaseProvider.overrideWithValue((_) async => 'lease'),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SystemFileShareForm(
                localPath: '/sample.txt',
                name: 'sample.txt',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, '系统分享'));
      await tester.pumpAndSettle();
      expect(find.text('已关闭系统分享，原文件暂存仍保留。'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);

      final retry = find.widgetWithText(FilledButton, '再次系统分享');
      expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(launches, 2);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(tester.widget<FilledButton>(retry).onPressed, isNull);
    },
  );
}

class _Reader extends Fake implements ContentReader {}

class _Cache implements ContentCacheControl {
  @override
  Future<bool> retain(String path, {bool ifManaged = false}) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
