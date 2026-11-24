import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preference_codec.dart';
import 'package:scrcpy_connect/core/settings/preference_schema.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

void main() {
  test('各平台默认档位与用户选择独立保存', () {
    expect(platformGlassEffects(TargetPlatform.macOS), GlassEffects.premium);
    expect(platformGlassEffects(TargetPlatform.iOS), GlassEffects.premium);
    expect(platformGlassEffects(TargetPlatform.windows), GlassEffects.off);
    expect(platformGlassEffects(TargetPlatform.linux), GlassEffects.standard);
    expect(platformGlassEffects(TargetPlatform.android), GlassEffects.standard);
    expect(PreferenceCodec.decode({}).glassEffects, GlassEffects.automatic);
    for (final mode in GlassEffects.values) {
      final patch = PreferenceChanges(glassEffects: mode);
      final schema = PreferenceSchema(defaults: const {});
      final persisted = schema.merge(
        schema.defaults,
        PreferenceCodec.encodeChanges(patch),
      );
      expect(PreferenceCodec.decode(persisted).glassEffects, mode);
    }
  });

  testWidgets('Windows 默认实体面，用户可以切到标准，辅助偏好优先', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    Future<void> show(GlassEffects mode, {bool reduce = false}) =>
        tester.pumpWidget(
          MaterialApp(
            home: GlassPreferences(
              effects: mode,
              reduceTransparency: reduce,
              child: Builder(
                builder: (context) {
                  final quality = GlassMaterial.quality(context);
                  return Text('${quality.name}:${opaqueGlass(context)}');
                },
              ),
            ),
          ),
        );
    await show(GlassEffects.automatic);
    expect(find.text('minimal:true'), findsOneWidget);
    await show(GlassEffects.standard);
    expect(find.text('standard:false'), findsOneWidget);
    await show(GlassEffects.standard, reduce: true);
    expect(find.text('minimal:true'), findsOneWidget);
  });

  test('clear disables blur and retains refraction in both themes', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final mode in Brightness.values) {
      final regular = Glass.optics(brightness: mode);
      final clear = Glass.optics(brightness: mode, variant: GlassVariant.clear);
      expect(regular.frost, greaterThan(0));
      expect(clear.frost, 0);
      expect(clear.blur, 0);
      expect(clear.bodyShade, 0);
      expect(clear.saturation, 1);
      expect(clear.lensModel, liquid.GlassLensModel.paraxial);
      expect(clear.refractiveIndex, regular.refractiveIndex);
    }
  });
}
