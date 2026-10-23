# Visual comparison captures

`pages.json` defines Pencil/Flutter pairs, viewports, crops and content differences. Export Pencil PNGs at 1× through the object API; unmatched component/state boards remain unmatched.

For production-page software layout capture at 402×874/DPR1 with 54/34px safe areas, run from `app/`:

```sh
DESIGN_REFINEMENT_CAPTURE_DIR=/tmp/connect-design/flutter \
  flutter test --no-pub test/design_refinement_capture.dart
```

The isolated controller uses the production theme, declared CJK font and app icon, and writes `layout.json`. Native/GPU captures require the running app and a separate temporary directory with device, viewport, safe areas, theme and fixture identity recorded.

From the root:

```sh
dart tool/visual_parity/compare.dart \
  --pencil-dir /tmp/connect-design/pencil \
  --flutter-dir /tmp/connect-design/flutter \
  --output /tmp/connect-design/comparison
```

Inputs must match configured dimensions/crops; the tool never resizes, aligns or pads. It emits paired images, RGB differences and hashes; optional historical geometry applies only to matching screenshot hashes. `completed` means comparison finished, not acceptance. Review actual typography, occlusion and scroll reachability; native material evidence uses `glass_chrome_test.dart` and the [fidelity record](../../docs/implementation/design-fidelity.md).
