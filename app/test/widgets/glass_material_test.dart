import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

void main() {
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
