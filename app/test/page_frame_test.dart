import 'package:scrcpy_connect/styles/theme.dart';
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
  final controller = createTestController((command, params) async => {});
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
}
