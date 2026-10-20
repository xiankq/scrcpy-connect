# Visual comparison captures

`pages.json` pairs complete Pencil frames with Flutter captures. It records the
source viewport, crops and known content differences; local state boards are not
stretched into page references. Export Pencil PNGs through the object API at 1×.

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
