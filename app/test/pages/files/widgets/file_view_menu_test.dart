import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/pages/files/search/widgets/file_search_controls.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_view_menu.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/glass/glass_action_bar.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

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

    await tester.tap(find.text('视图与排序'));
    await tester.pumpAndSettle();
    expect(find.byType(Glass), findsOneWidget);
    expect(find.byType(AdaptiveGlass), findsNothing);
    await tester.tap(find.text('大小'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('file-search-type-field')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('选择文件类型'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('底栏点「视图与排序」文字在底栏上方打开排序，大字时标签完整', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FileSortKey? sort;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(
              MediaQuery.sizeOf(context).width < 390 ? 2 : 1,
            ),
          ),
          child: child!,
        ),
        home: GlassPreferences(
          reduceTransparency: true,
          child: Scaffold(
            bottomNavigationBar: GlassActionBar(
              actions: [
                const GlassActionBarButton(
                  label: '取回原文件',
                  icon: Icon(LucideIcons.download),
                  onPressed: null,
                ),
                FileViewMenuButton(
                  viewMode: FileViewMode.grid,
                  sortKey: FileSortKey.name,
                  ascending: true,
                  onViewModeChanged: (_) {},
                  onSortKeyChanged: (value) => sort = value,
                  onAscendingChanged: (_) {},
                ),
                GlassActionBarButton(
                  label: '更多',
                  icon: const Icon(LucideIcons.ellipsis),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final trigger = find.text('视图与排序');
    final bar = tester.getRect(find.byType(Glass));
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.text('修改时间'), findsOneWidget);
    final panel = tester.getRect(find.byType(Glass).last);
    expect(panel.bottom, lessThan(bar.top));
    await tester.tap(find.text('大小'));
    await tester.pumpAndSettle();
    expect(sort, FileSortKey.size);
    expect(find.text('修改时间'), findsNothing);

    tester.view.physicalSize = const Size(320, 580);
    await tester.pumpAndSettle();
    expect(
      tester.renderObject<RenderParagraph>(trigger).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
