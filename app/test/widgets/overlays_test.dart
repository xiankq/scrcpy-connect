import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness 实体弹窗从位移和缩放连续进入并沿原路径退出', (tester) async {
      await tester.pumpWidget(
        _host(brightness, (context) {
          showAppDialog<void>(context: context, content: const Text('即将开始'));
        }),
      );
      await tester.tap(find.text('打开'));
      await tester.pump();
      final body = find.text('即将开始');
      final initial = tester.getRect(body);
      await tester.pump(const Duration(milliseconds: 80));
      final entering = tester.getRect(body);
      await tester.pumpAndSettle();
      final settled = tester.getRect(body);
      expect(initial.width, lessThan(entering.width));
      expect(entering.width, lessThan(settled.width));
      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(body).width, lessThan(settled.width));
      await tester.pumpAndSettle();
      expect(body, findsNothing);
    });

    testWidgets('$brightness 实体输入弹窗支持大字、键盘提交和取消', (tester) async {
      String? result;
      await tester.pumpWidget(
        _host(brightness, (context) async {
          result = await askText(context, title: '设备名称', initial: '旧名称');
        }),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(
        dialog.backgroundColor,
        ConnectTokens.theme(brightness).dialogTheme.backgroundColor,
      );
      _expectSolid();
      await tester.enterText(find.byType(TextField), ' 新名称 ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, '新名称');
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('取消'));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$brightness 实体抽屉保留大字滚动、动作结果与遮罩关闭', (tester) async {
      String? result;
      await tester.pumpWidget(
        _host(brightness, (context) async {
          result = await showAppModalSheet<String>(
            context: context,
            builder: (context) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 20; i++) Text('检查项目 $i'),
                  TextButton(
                    onPressed: () => Navigator.pop(context, '完成'),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
          );
        }),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(
        sheet.backgroundColor,
        ConnectTokens.theme(brightness).bottomSheetTheme.modalBackgroundColor,
      );
      _expectSolid();
      await tester.ensureVisible(find.text('完成'));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(result, '完成');
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$brightness 文字反馈和 Tooltip 使用实体主题面并保留提示语义', (tester) async {
      await tester.pumpWidget(
        _host(brightness, (context) {
          feedback(context, '保存完成');
        }),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('保存完成'), findsOneWidget);
      final surface = find.descendant(
        of: find.byType(ContentSurface),
        matching: find.byType(Material),
      );
      expect(
        tester.widget<Material>(surface).color,
        ConnectTokens.theme(brightness).colorScheme.surface,
      );
      await tester.longPress(find.byTooltip('操作说明'));
      await tester.pumpAndSettle();
      expect(find.text('操作说明'), findsOneWidget);
      final tooltip = tester.element(find.byType(Tooltip));
      expect(
        (TooltipTheme.of(tooltip).decoration as BoxDecoration).color!.a,
        1,
      );
      final caption = ConnectTokens.theme(brightness).textTheme.bodySmall!;
      final rendered = tester
          .widget<RichText>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is RichText && widget.text.toPlainText() == '操作说明',
            ),
          )
          .text
          .style!;
      expect(rendered.fontSize, caption.fontSize);
      expect(rendered.height, caption.height);
      expect(rendered.fontWeight, caption.fontWeight);
      expect(rendered.letterSpacing, caption.letterSpacing);
      expect(rendered.fontFamily, caption.fontFamily);
      _expectSolid();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$brightness 窄屏键盘和安全区内可编辑、切换辅助偏好并提交', (tester) async {
      final preferences = ValueNotifier(false);
      addTearDown(preferences.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      String? result;
      await tester.pumpWidget(
        _host(brightness, (context) async {
          result = await askText(
            context,
            title: '修改被控设备名称',
            label: '此名称只在本机显示',
          );
        }, preferences: preferences),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保留输入与焦点');
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
      preferences.value = true;
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '保留输入与焦点',
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.ensureVisible(find.text('保存'));
      await tester.pumpAndSettle();
      final action = tester.getRect(find.text('保存'));
      expect(action.top, greaterThanOrEqualTo(24));
      expect(action.bottom, lessThanOrEqualTo(360));
      _expectSolid();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, '保留输入与焦点');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$brightness 系统减少动态独立开启时内容抽屉不滑动', (tester) async {
      await tester.pumpWidget(
        _host(brightness, (context) {
          showAppModalSheet<void>(
            context: context,
            builder: (context) => const SafeArea(
              child: Padding(padding: EdgeInsets.all(24), child: Text('检查范围')),
            ),
          );
        }, reduceMotion: true),
      );
      await tester.tap(find.text('打开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final initial = tester.getTopLeft(find.byType(BottomSheet));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(BottomSheet)), initial);
      await tester.drag(find.byType(BottomSheet), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

void _expectSolid() {
  expect(find.byType(Glass), findsNothing);
  expect(find.byType(BackdropFilter), findsNothing);
  expect(find.byType(ImageFiltered), findsNothing);
}

Widget _host(
  Brightness brightness,
  void Function(BuildContext) open, {
  ValueNotifier<bool>? preferences,
  bool reduceMotion = false,
}) => MaterialApp(
  theme: ConnectTokens.theme(brightness),
  builder: (context, child) {
    Widget configure(bool reduced) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(2),
        highContrast: reduced,
        disableAnimations: reduced,
        reduceMotion: reduceMotion,
      ),
      child: GlassPreferences(reduceTransparency: reduced, child: child!),
    );
    return preferences == null
        ? configure(false)
        : ValueListenableBuilder<bool>(
            valueListenable: preferences,
            builder: (context, reduced, _) => configure(reduced),
          );
  },
  home: Scaffold(
    body: Builder(
      builder: (context) => Column(
        children: [
          TextButton(onPressed: () => open(context), child: const Text('打开')),
          const Tooltip(message: '操作说明', child: Icon(Icons.info)),
        ],
      ),
    ),
  ),
);
