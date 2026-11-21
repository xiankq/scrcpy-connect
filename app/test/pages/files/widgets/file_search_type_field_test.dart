import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/pages/files/search/widgets/file_search_controls.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  testWidgets('compact filter shows its value and opens a choice dialog', (
    tester,
  ) async {
    FileCatalogFilter? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 96,
              child: FileSearchTypeField(
                value: FileCatalogFilter.archives,
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      ),
    );
    final label = find.text('压缩包');
    expect(
      tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
      isFalse,
    );
    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(find.text('文件类型'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('图片'));
    await tester.pumpAndSettle();
    expect(selected, FileCatalogFilter.images);
  });
}
