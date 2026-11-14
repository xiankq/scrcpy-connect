import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

void main() {
  testWidgets('toolbar glass does not add a clipped drop shadow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: GlassPreferences(
          reduceTransparency: true,
          child: Scaffold(
            body: GlassToolbarGroup(
              children: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
              ],
            ),
          ),
        ),
      ),
    );

    final glass = tester.widget<Glass>(find.byType(Glass));
    expect(glass.showShadow, isFalse);
    expect(tester.takeException(), isNull);
  });
}
