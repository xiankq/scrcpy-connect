import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/pages/files/search/widgets/file_search_controls.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_view_menu.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

void main() {
  testWidgets('file glass menus honor opaque accessibility fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: GlassPreferences(
          reduceTransparency: true,
          child: Scaffold(
            body: Column(
              children: [
                FileSearchTypeField(
                  value: FileCatalogFilter.all,
                  onChanged: (_) {},
                ),
                FileViewMenuButton(
                  viewMode: FileViewMode.grid,
                  sortKey: FileSortKey.name,
                  ascending: true,
                  onViewModeChanged: (_) {},
                  onSortKeyChanged: (_) {},
                  onAscendingChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menus = tester.widgetList<GlassMenu>(find.byType(GlassMenu));
    expect(menus, hasLength(1));
    for (final menu in menus) {
      expect(menu.quality, GlassQuality.minimal);
      expect(menu.settings?.blur, 0);
      expect(
        menu.settings?.glassColor,
        ConnectTokens.theme(Brightness.light).colorScheme.surface,
      );
    }
    await tester.tap(find.byKey(const ValueKey('file-search-type-field')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('文件类型'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
