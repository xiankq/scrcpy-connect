import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_navigation_bar.dart';

void main() {
  testWidgets('三个按键按读屏标签触发对应的手机导航，禁用时都不可点', (tester) async {
    final pressed = <String>[];
    Future<void> show({required bool enabled}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: RemoteNavigationBar(
            enabled: enabled,
            onBack: () => pressed.add('back'),
            onHome: () => pressed.add('home'),
            onRecent: () => pressed.add('recent'),
          ),
        ),
      ),
    );

    await show(enabled: true);
    for (final label in ['返回', '主屏幕', '最近任务']) {
      await tester.tap(find.byTooltip(label));
    }
    expect(pressed, ['back', 'home', 'recent']);

    await show(enabled: false);
    for (final label in ['返回', '主屏幕', '最近任务']) {
      final button = find.ancestor(
        of: find.byTooltip(label),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(button).onPressed, isNull);
    }
  });
}
