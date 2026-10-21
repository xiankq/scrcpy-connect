# Visual comparison captures

`pages.json` contains the current scoped Pencil/Flutter pairs for the affected pages. It records the
source viewport, crops and known content differences; local state boards are not
stretched into page references. Export Pencil PNGs through the object API at 1×.

For a repeatable 402×874/DPR1 software layout capture, run from `app/`:

```sh
DESIGN_REFINEMENT_CAPTURE_DIR=/tmp/connect-design/flutter \
  flutter test --no-pub test/design_refinement_capture_test.dart
```

The opt-in test uses production pages and theme with an isolated controller,
loads a declared Noto CJK font and the real app icon, and writes `layout.json`.
It reserves the 54/34px safe areas without painting fake system bars. It does
not prove native behavior or GPU optics; capture those from the running app in
a separate directory. Local component boards and alternate scroll/mode states
are listed as unmatched with explicit reasons, never stretched into full pages.

Capture the changed production pages from the running app into a new system
temporary directory. Record device, viewport, safe areas, theme and fixture
identity. The old all-page screenshot tests and their shared fixtures have been
removed; existing capture archives remain readable.

From the repository root:

```sh
dart tool/visual_parity/compare.dart \
  --pencil-dir /tmp/connect-design/pencil \
  --flutter-dir /tmp/connect-design/flutter \
  --output /tmp/connect-design/comparison
```

Inputs must match their configured dimensions and crops. The tool does not
resize, align or pad images. It produces side-by-side images, RGB differences
and input hashes. Optional historical `layout-contract.json` geometry is attached
only when its screenshot hash matches; otherwise it is marked stale/unavailable.

`completed` means comparison finished. It does not establish content or visual
acceptance. Review typography, safe areas, occlusion and scroll reachability on
the actual changed screen. For native materials and overlays, use the retained
`app/integration_test/glass_chrome_test.dart` device capture. See the
[design fidelity record](../../docs/implementation/design-fidelity.md).
