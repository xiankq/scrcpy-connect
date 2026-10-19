import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// Public renderer diagnostics only; all surfaces below use design_system.
// ignore: depend_on_referenced_packages
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as liquid;

const _closeKey = ValueKey('glass-close');
const _shareKey = ValueKey('glass-share');
const _toolbarKey = ValueKey('glass-toolbar');
const _panelKey = ValueKey('glass-panel');
const _tabsKey = ValueKey('glass-tabs');
const _sceneMarkerKey = ValueKey('glass-scene-marker');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('production Glass captures live Android shader materials', (
    tester,
  ) async {
    final report = <String, dynamic>{
      'schemaVersion': 1,
      'scope': 'glass-material',
      'platform': Platform.operatingSystem,
      'shaderImageFiltersSupported': ui.ImageFilter.isShaderFilterSupported,
      'shaderProgramsLoaded': false,
      'surfaceConverted': false,
      'functionalAcceptanceComplete': false,
      'opticalCaptureComplete': false,
      'harnessComplete': false,
      // A successful run supplies evidence for review, not a visual verdict.
      'visualReviewRequired': true,
      'visualAcceptanceComplete': false,
      'scenes': <Map<String, dynamic>>[],
      'interactions': <String, dynamic>{},
    };
    binding.reportData = report;
    final previousHitTestSetting = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    final semantics = tester.ensureSemantics();
    try {
      expect(Platform.isAndroid, isTrue, reason: 'Run on an Android device.');
      final supported = ui.ImageFilter.isShaderFilterSupported;
      if (supported) {
        // Wait for the same public shader cache used by production lenses.
        // A bounded real async wait avoids capturing their loading fallback.
        await tester.runAsync(
          () => liquid.LiquidGlassShaders.ensureLoaded().timeout(
            const Duration(seconds: 30),
          ),
        );
      }
      report['shaderProgramsLoaded'] =
          supported && liquid.LiquidGlassShaders.isLoadedFor(true);
      report['liteGlassEnabled'] = liquid.LiquidGlassEngine.liteGlass;
      final harnessKey = GlobalKey<_GlassHarnessState>();
      await tester.pumpWidget(_GlassHarness(key: harnessKey));
      await _frames(tester);
      await binding.convertFlutterSurfaceToImage();
      report['surfaceConverted'] = true;
      await _frames(tester);
      final harness = harnessKey.currentState!;
      final scenes = report['scenes'] as List<Map<String, dynamic>>;
      final interactions = report['interactions'] as Map<String, dynamic>;

      Future<void> capture(String name) async {
        final markerCode = 0xa500 | (scenes.length + 1);
        harness.markScene(name, markerCode);
        await _frames(tester);
        await _rasterizedFrame(tester);
        // Android's screenshot plugin acquires the ImageReader frame before
        // waiting for vsync. Drain that previously acquired image without
        // publishing it, then submit/rasterize another frame for the real PNG.
        await binding.callbackManager.takeScreenshot('$name-image-reader-sync');
        await _rasterizedFrame(tester);
        expect(tester.takeException(), isNull);
        final lensCount = find.byType(liquid.LiquidGlassLens).evaluate().length;
        final liteCount = find.byType(liquid.LiquidGlassLite).evaluate().length;
        final blurCount = find.byType(BackdropFilter).evaluate().length;
        final reduced = harness.reduceTransparency;
        final opticsActive =
            supported &&
            liquid.LiquidGlassShaders.isLoadedFor(true) &&
            !liquid.LiquidGlassEngine.liteGlass &&
            lensCount > 0 &&
            liteCount == 0 &&
            !reduced;
        if (reduced) {
          // Accessibility must remove optics, including loading fallbacks.
          expect(lensCount, 0);
          expect(liteCount, 0);
          expect(blurCount, 0);
        } else if (supported) {
          expect(lensCount, harness.media ? 2 : 4);
          expect(
            opticsActive,
            isTrue,
            reason: 'Shader-capable captures must not be Lite fallback.',
          );
        }
        final view = tester.view;
        final controls = <String, dynamic>{};
        for (final entry in <String, Key>{
          'close': _closeKey,
          'toolbar': _toolbarKey,
          if (!harness.media) 'panel': _panelKey,
          if (!harness.media) 'tabs': _tabsKey,
        }.entries) {
          final rect = tester.getRect(find.byKey(entry.value));
          final logicalSize = view.physicalSize / view.devicePixelRatio;
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(logicalSize.width));
          expect(rect.bottom, lessThanOrEqualTo(logicalSize.height));
          if (entry.key != 'panel') {
            expect(rect.width, greaterThanOrEqualTo(44));
            expect(rect.height, greaterThanOrEqualTo(44));
          }
          controls[entry.key] = <double>[
            rect.left,
            rect.top,
            rect.width,
            rect.height,
          ];
        }
        await binding.takeScreenshot(name);
        final marker = tester.getRect(find.byKey(_sceneMarkerKey));
        scenes.add(<String, dynamic>{
          'name': name,
          'markerCode': markerCode,
          'markerBounds': <double>[
            marker.left,
            marker.top,
            marker.width,
            marker.height,
          ],
          'brightness': harness.brightness.name,
          'background': harness.media ? 'geometric-media' : 'lines-text-checks',
          'variant': harness.media ? 'clear' : 'regular',
          'reduceTransparency': reduced,
          'optics': reduced
              ? 'skipped-reduced-transparency'
              : opticsActive
              ? 'shader'
              : 'fallback-only',
          'lensCount': lensCount,
          'liteCount': liteCount,
          'blurWidgetCount': blurCount,
          'backgroundOffset': harness.scroll.offset,
          'physicalWidth': view.physicalSize.width,
          'physicalHeight': view.physicalSize.height,
          'devicePixelRatio': view.devicePixelRatio,
          'controls': controls,
        });
      }

      await capture('regular-light');
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(_closeKey)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await capture('regular-light-pressed');
      await press.cancel();
      await _frames(tester);
      expect(harness.closeCount, 0);
      interactions['cancelDoesNotActivate'] = true;
      await tester.tap(find.byKey(_closeKey));
      await _frames(tester);
      expect(harness.closeCount, 1);
      interactions['tapAfterCancel'] = true;
      await tester.tap(find.byKey(_shareKey));
      await _frames(tester);
      expect(harness.shareCount, 1);
      interactions['toolbarTap'] = true;
      await tester.tap(find.text('Files'));
      await _frames(tester);
      expect(harness.selectedIndex, 1);
      expect(harness.tabCount, 1);
      interactions['tabSelection'] = true;
      await _scrollBackground(tester, harness);
      interactions['backgroundScrollDistance'] = harness.scroll.offset;
      await capture('regular-light-scrolled');
      await tester.tap(find.byKey(_closeKey));
      await _frames(tester);
      expect(harness.closeCount, 2);
      interactions['tapAfterBackgroundScroll'] = true;

      harness.configure(brightness: Brightness.dark);
      await capture('regular-dark');
      harness.configure(brightness: Brightness.light, media: true);
      await capture('clear-bright');
      await tester.tap(find.byKey(_shareKey));
      await _frames(tester);
      expect(harness.shareCount, 2);
      interactions['clearToolbarTap'] = true;
      harness.configure(brightness: Brightness.dark, media: true);
      await capture('clear-dark');

      harness.configure(brightness: Brightness.light, reduceTransparency: true);
      await capture('reduced-light');
      await _scrollBackground(tester, harness);
      await capture('reduced-light-scrolled');
      await tester.tap(find.byKey(_closeKey));
      await tester.tap(find.byKey(_shareKey));
      await tester.tap(find.text('Files'));
      await _frames(tester);
      expect(harness.closeCount, 3);
      expect(harness.shareCount, 3);
      expect(harness.selectedIndex, 1);
      interactions['reducedControlsOperate'] = true;
      harness.configure(brightness: Brightness.dark, reduceTransparency: true);
      await capture('reduced-dark');
      report['functionalAcceptanceComplete'] = true;
      report['opticalCaptureComplete'] =
          supported &&
          report['shaderProgramsLoaded'] == true &&
          scenes
              .where((scene) => scene['reduceTransparency'] == false)
              .every((scene) => scene['optics'] == 'shader');
      report['harnessComplete'] = true;
      expect(
        supported,
        isTrue,
        reason:
            'Fallback captures are diagnostic; Android Impeller optics '
            'acceptance requires ImageFilter.isShaderFilterSupported.',
      );
      expect(report['opticalCaptureComplete'], isTrue);
    } finally {
      semantics.dispose();
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestSetting;
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

// Bounded pumps: no pumpAndSettle, permanent ticker, or fake shader timers.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

// A framework pump can finish while the raster thread and Android ImageReader
// still hold the preceding scene. Wait for a new raster receipt, then allow
// the platform compositor to present it; endOfFrame alone is insufficient.
Future<void> _rasterizedFrame(WidgetTester tester) async {
  final rasterized = Completer<void>();
  final started = DateTime.now().microsecondsSinceEpoch;
  void onTimings(List<ui.FrameTiming> timings) {
    if (!rasterized.isCompleted &&
        timings.any(
          (timing) =>
              timing.timestampInMicroseconds(
                ui.FramePhase.rasterFinishWallTime,
              ) >=
              started,
        )) {
      rasterized.complete();
    }
  }

  tester.binding.addTimingsCallback(onTimings);
  try {
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.runAsync(() async {
      await rasterized.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  } finally {
    tester.binding.removeTimingsCallback(onTimings);
  }
}

Future<void> _scrollBackground(
  WidgetTester tester,
  _GlassHarnessState harness,
) async {
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  // The open edge strip lies outside the panel and floating controls.
  await tester.timedDragFrom(
    Offset(8, height * .68),
    const Offset(0, -180),
    const Duration(milliseconds: 600),
  );
  await tester.pump(const Duration(milliseconds: 600));
  expect(harness.scroll.offset, greaterThan(100));
}

class _GlassHarness extends StatefulWidget {
  const _GlassHarness({super.key});

  @override
  State<_GlassHarness> createState() => _GlassHarnessState();
}

class _GlassHarnessState extends State<_GlassHarness> {
  final scroll = ScrollController();
  Brightness brightness = Brightness.light;
  bool media = false;
  bool reduceTransparency = false;
  int selectedIndex = 0;
  int closeCount = 0;
  int shareCount = 0;
  int tabCount = 0;
  String sceneName = 'initializing';
  int markerCode = 0;

  void markScene(String name, int code) => setState(() {
    sceneName = name;
    markerCode = code;
  });

  void configure({
    required Brightness brightness,
    bool media = false,
    bool reduceTransparency = false,
  }) {
    scroll.jumpTo(0);
    setState(() {
      this.brightness = brightness;
      this.media = media;
      this.reduceTransparency = reduceTransparency;
      selectedIndex = 0;
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ConnectTokens.theme(brightness),
    themeAnimationDuration: Duration.zero,
    home: GlassPreferences(
      reduceTransparency: reduceTransparency,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final mediaColor = media ? Colors.white : null;
            final variant = media ? GlassVariant.clear : GlassVariant.regular;
            return Stack(
              fit: StackFit.expand,
              children: [
                SingleChildScrollView(
                  controller: scroll,
                  physics: const ClampingScrollPhysics(),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight * 3),
                    painter: _BackdropPainter(
                      dark: brightness == Brightness.dark,
                      media: media,
                    ),
                  ),
                ),
                SafeArea(
                  minimum: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GlassIconButton(
                            key: _closeKey,
                            icon: const Icon(Icons.close),
                            tooltip: 'Close test control',
                            variant: variant,
                            color: mediaColor,
                            onPressed: () => setState(() => closeCount++),
                          ),
                          GlassToolbarGroup(
                            key: _toolbarKey,
                            variant: variant,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.zoom_in),
                                color: mediaColor,
                                tooltip: 'Zoom test control',
                                onPressed: () {},
                              ),
                              IconButton(
                                key: _shareKey,
                                icon: const Icon(Icons.ios_share),
                                color: mediaColor,
                                tooltip: 'Share test control',
                                onPressed: () => setState(() => shareCount++),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: media
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: Glass(
                                    key: _panelKey,
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          'Regular material',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 12),
                                        const Text('Aa 0123456789'),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Fine lines move behind '
                                          'this fixed optical sample.',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      if (!media)
                        GlassTabBar(
                          key: _tabsKey,
                          destinations: const [
                            GlassDestination(
                              icon: Icons.devices,
                              label: 'Devices',
                            ),
                            GlassDestination(
                              icon: Icons.folder,
                              label: 'Files',
                            ),
                            GlassDestination(
                              icon: Icons.settings,
                              label: 'Settings',
                            ),
                          ],
                          selectedIndex: selectedIndex,
                          onSelected: (index) => setState(() {
                            selectedIndex = index;
                            tabCount++;
                          }),
                        ),
                    ],
                  ),
                ),
                // Opaque diagnostic stamp is deliberately outside every lens.
                // Its pixels let the host reject stale or mislabeled PNGs.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: SafeArea(
                      bottom: false,
                      child: Center(
                        child: ColoredBox(
                          color: Colors.white,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                sceneName,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  height: 1.2,
                                ),
                              ),
                              SizedBox(
                                key: _sceneMarkerKey,
                                width: 96,
                                height: 6,
                                child: Row(
                                  children: List.generate(
                                    16,
                                    (bit) => Expanded(
                                      child: ColoredBox(
                                        color:
                                            markerCode & (1 << (15 - bit)) == 0
                                            ? Colors.black
                                            : Colors.white,
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

// Deliberately diagnostic artwork, never a product asset or screen.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({required this.dark, required this.media});
  final bool dark;
  final bool media;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    canvas.drawColor(
      media
          ? (dark ? const Color(0xFF132031) : const Color(0xFFF0DEAE))
          : (dark ? const Color(0xFF222222) : const Color(0xFFF4F4F4)),
      BlendMode.src,
    );
    for (var y = 0.0; y < size.height; y += 24) {
      if (media) {
        paint.color = [
          const Color(0xFF007AFF),
          const Color(0xFFFF9500),
          const Color(0xFFFF3B30),
          const Color(0xFF34C759),
        ][(y ~/ 96) % 4];
        canvas.drawCircle(Offset(size.width * .6, y + 48), 68, paint);
        canvas.drawRect(Rect.fromLTWH(8, y + 8, 92, 12), paint);
      } else {
        paint
          ..color = dark ? const Color(0xFF777777) : const Color(0xFF999999)
          ..strokeWidth = 1;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        for (var x = 0.0; x < size.width; x += 24) {
          if ((x ~/ 24 + y ~/ 24).isEven) {
            paint.color = dark
                ? const Color(0xFFDDDDDD)
                : const Color(0xFF333333);
            canvas.drawRect(Rect.fromLTWH(x, y, 12, 12), paint);
          }
        }
      }
      if (y % 96 == 0) {
        final text = TextPainter(
          text: TextSpan(
            text: 'Aa 0123456789  —  ${y.toInt()}',
            style: TextStyle(
              color: dark ? Colors.white : Colors.black,
              fontSize: 14,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width - 32);
        text.paint(canvas, Offset(16, y + 28));
        text.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.media != media;
}
