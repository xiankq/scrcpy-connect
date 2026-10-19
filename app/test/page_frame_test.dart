import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void _viewport(
  WidgetTester tester, {
  Size size = const Size(390, 700),
  double scale = 1,
  double keyboard = 0,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: 24, bottom: keyboard > 0 ? 0 : 34);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _mount(WidgetTester tester, Widget frame) async {
  final controller = createTestController(
    (command, [params = const {}]) async => {},
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    RouterTestApp(
      controller: controller,
      theme: ConnectTokens.theme(Brightness.light),
      home: frame,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToEnd(
  WidgetTester tester,
  ScrollController controller,
) async {
  // A lazy list can refine maxScrollExtent after reaching its estimated end.
  // Keep advancing to the measured end before asserting the last row's inset.
  for (var attempt = 0; attempt < 5; attempt++) {
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    if ((controller.offset - controller.position.maxScrollExtent).abs() < .01) {
      break;
    }
  }
  expect(controller.offset, closeTo(controller.position.maxScrollExtent, .01));
}

List<Widget> _rows({ValueChanged<int>? onTap, int count = 30}) => [
  for (var i = 0; i < count; i++)
    SizedBox(
      key: ValueKey('row-$i'),
      height: 56,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null ? null : () => onTap(i),
        child: ColoredBox(
          color: i.isEven ? Colors.blue : Colors.orange,
          child: Align(alignment: Alignment.centerLeft, child: Text('内容 $i')),
        ),
      ),
    ),
];

void main() {
  testWidgets(
    'transparent header overlays a viewport whose origin remains at zero',
    (tester) async {
      _viewport(tester);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _mount(
        tester,
        PageFrame(
          title: '设置详情',
          child: GroupedListView(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            controller: scroll,
            children: _rows(),
          ),
        ),
      );

      final viewport = tester.getRect(find.byType(ListView));
      final header = tester.getRect(find.byType(AppBar));
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(viewport.top, 0);
      expect(bar.backgroundColor, Colors.transparent);
      expect(bar.surfaceTintColor, Colors.transparent);
      expect(bar.forceMaterialTransparency, isTrue);
      expect(
        tester.getRect(find.byKey(const ValueKey('row-0'))).top,
        closeTo(header.bottom + DesignTokens.spacingMd, .01),
      );

      scroll.jumpTo(header.bottom + DesignTokens.spacingMd);
      await tester.pumpAndSettle();
      final row = tester.getRect(find.byKey(const ValueKey('row-0')));
      expect(row.top, closeTo(viewport.top, .01));
      expect(row.overlaps(header), isTrue);
      expect(tester.getRect(find.byType(ListView)), viewport);
      final protection = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(PageChromeProtection),
          matching: find.byType(DecoratedBox),
        ),
      );
      final gradient =
          (protection.decoration as BoxDecoration).gradient! as LinearGradient;
      final protectionHeight = tester.getSize(
        find.byType(PageChromeProtection),
      ).height;
      expect(protectionHeight, header.height + DesignTokens.spacingLg);
      expect(gradient.stops![1] * protectionHeight, header.height);
      expect(gradient.colors[1].a, DesignTokens.componentScrollEdgeOpacity);
      expect(gradient.colors.last.a, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'header title absorbs taps and forwards vertical drags to content',
    (tester) async {
      _viewport(tester);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final taps = <int>[];
      await _mount(
        tester,
        PageFrame(
          title: '页面标题',
          child: GroupedListView(
            controller: scroll,
            children: _rows(onTap: taps.add),
          ),
        ),
      );
      scroll.jumpTo(150);
      await tester.pumpAndSettle();
      final titlePoint = tester.getCenter(find.text('页面标题'));
      await tester.tapAt(titlePoint);
      await tester.pumpAndSettle();
      expect(
        taps,
        isEmpty,
        reason: 'A header tap must not activate an obscured content row.',
      );
      final before = scroll.offset;
      await tester.dragFrom(titlePoint, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(
        scroll.offset,
        greaterThan(before),
        reason: 'Dragging the noninteractive header title should continue scrolling the underlying viewport.',
      );
      expect(taps, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'header drag ignores the scrollable removed by a loading failure',
    (tester) async {
      _viewport(tester);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var success = true;
      late StateSetter update;
      await _mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return PageFrame(
              title: '实时通知',
              child: success
                  ? GroupedListView(controller: scroll, children: _rows())
                  : const PageChromeBody(child: Center(child: Text('加载失败'))),
            );
          },
        ),
      );
      scroll.jumpTo(100);
      await tester.pumpAndSettle();
      expect(scroll.hasClients, isTrue);
      update(() => success = false);
      await tester.pumpAndSettle();
      expect(scroll.hasClients, isFalse);
      expect(find.byType(Scrollable), findsNothing);
      await tester.dragFrom(
        tester.getCenter(find.text('实时通知')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(find.text('加载失败'), findsOneWidget);
      expect(tester.takeException(), isNull);

      update(() => success = true);
      await tester.pumpAndSettle();
      final before = scroll.offset;
      await tester.dragFrom(
        tester.getCenter(find.text('实时通知')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(before));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the last content item can scroll entirely above floating bottom actions',
    (tester) async {
      _viewport(tester);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var activations = 0;
      await _mount(
        tester,
        PageFrame(
          title: '文件操作',
          bottom: FilledButton(
            onPressed: () => activations++,
            child: const Text('继续'),
          ),
          child: GroupedListView(controller: scroll, children: _rows()),
        ),
      );
      expect(tester.getRect(find.byType(ListView)).top, 0);
      expect(tester.getRect(find.byType(ListView)).bottom, 700);
      await _scrollToEnd(tester, scroll);
      final last = tester.getRect(find.byKey(const ValueKey('row-29')));
      final action = tester.getRect(find.byType(FilledButton));
      expect(
        last.bottom,
        lessThanOrEqualTo(action.top),
        reason:
            'offset=${scroll.offset}, actualMax=${scroll.position.maxScrollExtent}, '
            'padding=${tester.widget<ListView>(find.byType(ListView)).padding}, '
            'chrome=${PageChromePadding.of(tester.element(find.byType(GroupedListView)))}, '
            'last=$last, action=$action',
      );
      expect(find.text('内容 29').hitTestable(), findsOneWidget);
      expect(action.bottom, lessThanOrEqualTo(700 - 34));
      await tester.tap(find.text('继续'));
      expect(activations, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('root title compacts after scroll without moving its viewport', (
    tester,
  ) async {
    _viewport(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _mount(
      tester,
      PageFrame(
        title: '设置',
        root: true,
        child: GroupedListView(controller: scroll, children: _rows()),
      ),
    );
    final viewport = tester.getRect(find.byType(ListView));
    final header = tester.getRect(find.byType(AppBar));
    final expanded = tester.widget<Text>(find.text('设置')).style!.fontSize!;
    scroll.jumpTo(100);
    await tester.pumpAndSettle();
    final compact = tester.widget<Text>(find.text('设置')).style!.fontSize!;
    expect(compact, lessThan(expanded));
    expect(tester.getRect(find.byType(AppBar)), header);
    expect(tester.getRect(find.byType(ListView)), viewport);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('设置')).style!.fontSize, expanded);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow large text and keyboard keep the final field and action usable',
    (tester) async {
      _viewport(tester, size: const Size(280, 620), scale: 2, keyboard: 220);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _mount(
        tester,
        PageFrame(
          title: '连接与已授权设备的详细设置',
          bottom: FilledButton(onPressed: () {}, child: const Text('保存设置')),
          child: GroupedListView(
            controller: scroll,
            children: [
              ..._rows(count: 12),
              const TextField(
                key: ValueKey('final-field'),
                decoration: InputDecoration(labelText: '连接端口'),
              ),
            ],
          ),
        ),
      );
      final action = tester.getRect(find.byType(FilledButton));
      expect(
        action.bottom,
        lessThanOrEqualTo(400),
        reason:
            'The action must remain above the keyboard. '
            'viewport=${tester.getRect(find.byType(ListView))}, '
            'frame=${tester.getRect(find.byType(PageFrame))}, '
            'insets=${MediaQuery.viewInsetsOf(tester.element(find.byType(PageFrame)))}, '
            'action=$action',
      );
      expect(tester.getRect(find.byType(AppBar)).top, 0);
      expect(
        tester.getRect(find.text('连接与已授权设备的详细设置')).top,
        greaterThanOrEqualTo(24),
      );
      await _scrollToEnd(tester, scroll);
      final field = tester.getRect(find.byKey(const ValueKey('final-field')));
      expect(
        field.top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
      );
      expect(field.bottom, lessThanOrEqualTo(action.top));
      await tester.tap(find.byKey(const ValueKey('final-field')));
      await tester.enterText(find.byKey(const ValueKey('final-field')), '5555');
      expect(find.text('5555'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'grouped list adds chrome insets to explicit first and last padding',
    (tester) async {
      _viewport(tester);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: PageChromePadding(
            padding: const EdgeInsets.only(top: 88, bottom: 104),
            showRecovery: false,
            child: GroupedListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
              children: _rows(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(ListView));
      final first = tester.getRect(find.byKey(const ValueKey('row-0')));
      expect(first.top - viewport.top, 88 + 7);
      expect(first.left - viewport.left, 12);
      await _scrollToEnd(tester, scroll);
      final last = tester.getRect(find.byKey(const ValueKey('row-29')));
      expect(viewport.bottom - last.bottom, 104 + 9);
      expect(tester.takeException(), isNull);
    },
  );
}
