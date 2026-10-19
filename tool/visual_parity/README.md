# Visual comparison captures

`pages.json` explicitly pairs complete Pencil frames with light Flutter captures.
The `unmatchedCaptures` map explains fixtures without a complete matching source
frame. Local state boards are not stretched into page references. Source PNGs
must be exported through the Pencil object API at 1×; do not read `.pen` as text.

From `app/`, capture the existing page fixtures:

```sh
CONNECT_CAPTURE_DIR=/tmp/connect-design-v3/flutter \
  flutter test --no-pub test/ios_pages_capture_test.dart
```

Then, from the repository root:

```sh
dart tool/visual_parity/compare.dart \
  --pencil-dir /tmp/connect-design-v3/pencil \
  --flutter-dir /tmp/connect-design-v3/flutter \
  --output /tmp/connect-design-v3/comparison
```

Normal host pages compare `[0,54,402,786]` within a 402×874 source: top safe area
54 and bottom safe area 34. Photo preview and remote control explicitly compare
the whole `[0,0,402,874]` viewport, preserving edge controls. Their source system
chrome and illustrative remote/media pixels may differ from the Flutter fixture.
The same physical-phone corner mask is applied to both sources. No image is
resized, aligned automatically or padded to conceal size errors.

Each pair reports its `fixtureContentDifferences`, capture scope, input SHA-256,
pixel diagnostics and both output images. An empty differences list means no
known fixture mismatch was recorded, not that content has been accepted.
`completed` only means every input was compared; `visualAcceptanceComplete` and
`contentAcceptanceComplete` never become true automatically. Full-page fixture
content differences can change vertical flow and must be reviewed alongside
shared component geometry.

The capture writes `capture-contract.json` and `layout-contract.json` beside its
PNGs. Layout instrumentation reads the already laid-out element/render trees;
it does not wrap production controls or change constraints. Each screenshot has
a SHA-256 association with its layout entry. `report.json` includes that entry as
`flutterLayout` only if the hash matches; missing or stale layout is reported
explicitly while image comparison still works with older captures.

`globalBounds` is `[x,y,width,height]` in the uncropped source viewport at DPR 1.
Component IDs and `parentComponent` associate shared components, major controls
and their paragraphs. Text entries record actual paragraph bounds, line boxes,
overflow, text scale and span style values (font family, size, weight, height and
letter spacing). Line boxes are paragraph-local, so add the paragraph origin to
place them on the source image. Font `height` is a line-height multiplier.
Offstage and non-current routes are excluded. Bounds may extend beyond a scroll clip;
`intersectsViewport` is not a paint-visibility or scroll-reachability assertion.

Root devices/transfers/settings and workspace/connection-form captures use the
production router. Other fixtures isolate native dependencies. The screenshot
backend is the widget-test fallback; these artifacts do not establish native
GPU optics, dynamic behavior, actual device capabilities or remote texture
rendering. See the [design fidelity record](../../docs/implementation/design-fidelity.md)
for the verification boundary.
