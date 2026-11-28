import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

void main() {
  testWidgets('输入弹窗支持大字、键盘提交和取消', (tester) async {
    String? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await askText(context, title: '设备名称', initial: '旧名称');
      }),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
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

  testWidgets('抽屉保留大字滚动、动作结果与遮罩关闭', (tester) async {
    String? result;
    await tester.pumpWidget(
      _host((context) async {
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

  testWidgets('长内容抽屉先停在低处，拖动标题栏升高，继续下拉关闭', (tester) async {
    await tester.pumpWidget(
      _host((context) {
        showAppModalSheet<void>(
          context: context,
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader(title: '选择'),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [for (var i = 0; i < 40; i++) Text('选项 $i')],
                ),
              ),
            ],
          ),
        );
      }),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final compact = tester.getSize(find.byType(BottomSheet)).height;

    await tester.drag(find.text('选择'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(BottomSheet)).height,
      greaterThan(compact),
    );

    await tester.drag(find.text('选择'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).height, compact);

    await tester.drag(find.text('选择'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文字反馈和 Tooltip 显示提示文字', (tester) async {
    await tester.pumpWidget(
      _host((context) {
        feedback(context, '保存完成');
      }),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('保存完成'), findsOneWidget);
    await tester.longPress(find.byTooltip('操作说明'));
    await tester.pumpAndSettle();
    expect(find.text('操作说明'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏键盘和安全区内可编辑、切换辅助偏好并提交', (tester) async {
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
      _host((context) async {
        result = await askText(context, title: '修改被控设备名称', label: '此名称只在本机显示');
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
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, '保留输入与焦点');
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统减少动态独立开启时内容抽屉不滑动', (tester) async {
    await tester.pumpWidget(
      _host((context) {
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

Widget _host(
  void Function(BuildContext) open, {
  ValueNotifier<bool>? preferences,
  bool reduceMotion = false,
}) => MaterialApp(
  theme: ConnectTokens.theme(Brightness.light),
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
