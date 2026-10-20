import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:scrcpy_connect/pages/devices/workspace/remote/widgets/exit_handle.dart';
import 'package:scrcpy_connect/widgets/media_controls_protection.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// Public renderer diagnostics only; all surfaces below use design_system.
// ignore: depend_on_referenced_packages
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

const _closeKey = ValueKey('glass-close');
const _shareKey = ValueKey('glass-share');
const _toolbarKey = ValueKey('glass-toolbar');
const _panelKey = ValueKey('glass-panel');
const _tabsKey = ValueKey('glass-tabs');
const _menuKey = ValueKey('glass-menu-source');
const _sceneMarkerKey = ValueKey('glass-scene-marker');
const _regularPhotoPath = String.fromEnvironment(
  'CONNECT_GLASS_REGULAR_PHOTO',
  defaultValue:
      '/data/user/0/dev.scrcpyconnect.scrcpy_connect/cache/glass-lake.jpg',
);
const _clearPhotoPath = String.fromEnvironment(
  'CONNECT_GLASS_CLEAR_PHOTO',
  defaultValue:
      '/data/user/0/dev.scrcpyconnect.scrcpy_connect/cache/glass-forest.jpg',
);

void main() {
  final binding = _CleanGlassBinding()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('production Glass captures live Android shader materials', (
    tester,
  ) async {
    final report = <String, dynamic>{
      'schemaVersion': 2,
      'backend': GlassMaterial.backend,
      'backendVersion': GlassMaterial.backendVersion,
      'composition': GlassMaterial.composition,
      'buildMode': kProfileMode
          ? 'profile'
          : kReleaseMode
          ? 'release'
          : 'debug',
      'debugPointerOverlay': false,
      'tooltipsVisible': false,
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
      'motionSamples': <Map<String, dynamic>>[],
      'performance': <Map<String, dynamic>>[],
      'photoSources': <String, dynamic>{},
    };
    binding.reportData = report;
    final previousHitTestSetting = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    final semantics = tester.ensureSemantics();
    try {
      expect(Platform.isAndroid, isTrue, reason: 'Run on an Android device.');
      final supported = ui.ImageFilter.isShaderFilterSupported;
      if (supported) {
        await tester.runAsync(
          () => GlassMaterial.initialize().timeout(const Duration(seconds: 30)),
        );
      }
      report['shaderProgramsLoaded'] = supported && GlassMaterial.isInitialized;
      report['fallbackEnabled'] = !supported;
      binding.setLabel('');
      final harnessKey = GlobalKey<_GlassHarnessState>();
      await tester.pumpWidget(_GlassHarness(key: harnessKey));
      await _frames(tester);
      final harness = harnessKey.currentState!;
      final scenes = report['scenes'] as List<Map<String, dynamic>>;
      final interactions = report['interactions'] as Map<String, dynamic>;

      Future<void> measurePerformance() async {
        // Measure continuous background repaint at real vsync. No screenshot,
        // pump or image decoding is allowed inside these measured windows.
        for (final scenario in [
          ('regular', false, false, false),
          ('clear', true, false, false),
          ('blend', false, false, true),
          ('reduced', false, true, false),
        ]) {
          harness.configure(
            brightness: Brightness.light,
            media: scenario.$2,
            reduceTransparency: scenario.$3,
            blendDemo: scenario.$4,
          );
          await _frames(tester);
          final lensCount = find.byType(liquid.AdaptiveGlass).evaluate().length;
          final liteCount = find
              .byType(liquid.LightweightLiquidGlass)
              .evaluate()
              .length;
          final layerCount = find
              .byType(liquid.LiquidGlassLayer)
              .evaluate()
              .length;
          expect(
            liteCount,
            0,
            reason: 'Performance cannot use a Lite substitute.',
          );
          if (scenario.$3) {
            expect(lensCount, 0);
            expect(layerCount, 0);
          } else {
            expect(
              lensCount,
              scenario.$2
                  ? 2
                  : scenario.$4
                  ? 5
                  : 4,
            );
            expect(
              layerCount,
              1,
              reason: 'Same-plane controls share one refraction pass.',
            );
          }
          final raw = <ui.FrameTiming>[];
          void timing(List<ui.FrameTiming> frames) => raw.addAll(frames);
          binding.addTimingsCallback(timing);
          final paintBefore = harness.backgroundPaints;
          harness.startBackgroundMotion();
          // Warm up shader/ticker work before starting the measured interval.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          final start = DateTime.now().microsecondsSinceEpoch;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 3)),
          );
          final end = DateTime.now().microsecondsSinceEpoch;
          harness.stopBackgroundMotion();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 350)),
          );
          binding.removeTimingsCallback(timing);
          final frames = raw.where((f) {
            final wall = f.timestampInMicroseconds(
              ui.FramePhase.rasterFinishWallTime,
            );
            return wall >= start && wall <= end;
          }).toList();
          expect(
            frames,
            isNotEmpty,
            reason: 'Real raster FrameTimings must arrive.',
          );
          expect(harness.backgroundPaints - paintBefore, greaterThan(2));
          (report['performance'] as List<Map<String, dynamic>>).add({
            'scenario': scenario.$1,
            'renderSurface': 'native',
            'quality': scenario.$3 ? 'opaque' : 'premium',
            if (!scenario.$3)
              'opticalSettings': _opticsReceipt(
                Brightness.light,
                scenario.$2 ? GlassVariant.clear : GlassVariant.regular,
              ),
            'lensCount': lensCount,
            'liteCount': liteCount,
            'layerCount': layerCount,
            'logicalViewport': [
              tester.view.physicalSize.width / tester.view.devicePixelRatio,
              tester.view.physicalSize.height / tester.view.devicePixelRatio,
            ],
            'devicePixelRatio': tester.view.devicePixelRatio,
            'windowStartWallUs': start,
            'windowEndWallUs': end,
            'refreshRateHz': tester.view.display.refreshRate,
            'backgroundPaints': harness.backgroundPaints - paintBefore,
            'screenshotsDuringMeasurement': 0,
            'frames': [
              for (final f in frames)
                {
                  'number': f.frameNumber,
                  'vsyncStartUs': f.timestampInMicroseconds(
                    ui.FramePhase.vsyncStart,
                  ),
                  'buildUs': f.buildDuration.inMicroseconds,
                  'rasterUs': f.rasterDuration.inMicroseconds,
                  'totalUs': f.totalSpan.inMicroseconds,
                },
            ],
          });
        }
      }

      if (const bool.fromEnvironment('CONNECT_GLASS_PERF_ONLY')) {
        report['scope'] = 'glass-performance';
        report['samplingBounds'] = GlassMaterial.samplingBounds;
        await measurePerformance();
        report['nativeSurfaceDuringTiming'] = true;
        report['performanceCaptureComplete'] = true;
        report['harnessComplete'] = true;
        return;
      }

      // Android ImageView capture changes the rendering path. Time the native
      // production surface first; only convert after the measured windows end.
      await measurePerformance();
      report['nativeSurfaceDuringTiming'] = true;
      harness.configure(brightness: Brightness.light);
      await _frames(tester);
      await binding.convertFlutterSurfaceToImage();
      report['surfaceConverted'] = true;
      await _frames(tester);

      Future<void> capture(String name, {bool settle = true}) async {
        final requestedAt = DateTime.now().microsecondsSinceEpoch;
        final markerCode = 0xa500 | (scenes.length + 1);
        harness.markScene(name, markerCode);
        if (settle) await _frames(tester);
        await _rasterizedFrame(tester);
        // Android's screenshot plugin acquires the ImageReader frame before
        // waiting for vsync. Drain that previously acquired image without
        // publishing it, then submit/rasterize another frame for the real PNG.
        await binding.callbackManager.takeScreenshot('$name-image-reader-sync');
        await _rasterizedFrame(tester);
        expect(tester.takeException(), isNull);
        final lensCount = find.byType(liquid.AdaptiveGlass).evaluate().length;
        final liteCount = find
            .byType(liquid.LightweightLiquidGlass)
            .evaluate()
            .length;
        final blurCount = find.byType(BackdropFilter).evaluate().length;
        final reduced = harness.reduceTransparency;
        final opticsActive =
            supported &&
            GlassMaterial.isInitialized &&
            lensCount > 0 &&
            liteCount == 0 &&
            !reduced;
        if (reduced) {
          // Accessibility must remove optics, including loading fallbacks.
          expect(lensCount, 0);
          expect(liteCount, 0);
          expect(blurCount, 0);
        } else if (supported) {
          expect(
            lensCount,
            harness.productionDemo
                ? greaterThanOrEqualTo(5)
                : harness.media
                ? 2
                : harness.blendDemo
                ? 5
                : 4,
          );
          expect(find.byType(liquid.LiquidGlassLayer), findsWidgets);
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
          'background': harness.photoPath != null
              ? 'repository-photo'
              : harness.media
              ? 'geometric-media'
              : 'lines-text-checks',
          if (harness.photoPath != null) 'photoPath': harness.photoPath,
          'variant': harness.media ? 'clear' : 'regular',
          if (!reduced)
            'opticalSettings': _opticsReceipt(
              harness.brightness,
              harness.media ? GlassVariant.clear : GlassVariant.regular,
            ),
          'reduceTransparency': reduced,
          'reduceMotion': harness.reduceMotion,
          'requestedAtUs': requestedAt,
          'receiptAtUs': DateTime.now().microsecondsSinceEpoch,
          'layerCount': find.byType(liquid.LiquidGlassLayer).evaluate().length,
          'blendGroupCount': find
              .byType(liquid.LiquidGlassBlendGroup)
              .evaluate()
              .length,
          'productionDemo': harness.productionDemo,
          'blendDemo': harness.blendDemo,
          'blendNear': harness.blendNear,
          'optics': reduced
              ? 'skipped-reduced-transparency'
              : opticsActive
              ? 'shader'
              : 'fallback-only',
          'surfaceCount': lensCount,
          'lightweightSurfaceCount': liteCount,
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
      // Capture a causal press/cancel/repress sequence. Samples are read from
      // actual presentation transforms on each requested frame, not targets.
      harness.configure(brightness: Brightness.light);
      await capture('motion-rest');
      final baseline = _presentationBounds(tester);
      final motion = report['motionSamples'] as List<Map<String, dynamic>>;
      final motionClock = Stopwatch()..start();
      Future<void> sample(String phase, int count) async {
        for (var frame = 0; frame < count; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          motion.add({
            'phase': phase,
            'elapsedUs': motionClock.elapsedMicroseconds,
            'bounds': _presentationBounds(tester),
          });
        }
      }

      final beforeMotion = harness.closeCount;
      final held = await tester.startGesture(
        tester.getCenter(find.byKey(_closeKey)),
      );
      await sample('press', 4);
      await capture('motion-held', settle: false);
      await held.moveBy(const Offset(18, 10));
      await sample('drag', 3);
      await capture('motion-drag', settle: false);
      await held.cancel();
      await sample('cancel', 1);
      final interruptedBounds = _presentationBounds(tester);
      final repress = await tester.startGesture(
        tester.getCenter(find.byKey(_closeKey)),
      );
      await sample('repress', 2);
      await capture('motion-repress', settle: false);
      await repress.cancel();
      await sample('recovery', 45);
      await capture('motion-recovered');
      expect(harness.closeCount, beforeMotion);
      final recovered = _presentationBounds(tester);
      expect(_boundsDistance(baseline, recovered), lessThan(.5));
      expect(
        _boundsDistance(baseline, interruptedBounds),
        greaterThan(.01),
        reason: 'Repress must interrupt a still-moving presentation, not a completed animation.',
      );
      await tester.tap(find.byKey(_closeKey));
      await _frames(tester);
      expect(harness.closeCount, beforeMotion + 1);
      interactions['interruptedRecovery'] = true;
      interactions['recoveredBounds'] = recovered;
      interactions['restBounds'] = baseline;

      // Reduce Motion changes geometry policy, not the ability to operate.
      harness.configure(brightness: Brightness.light, reduceMotion: true);
      await _frames(tester);
      final reducedRest = _presentationBounds(tester);
      final still = await tester.startGesture(
        tester.getCenter(find.byKey(_closeKey)),
      );
      await sample('reduced-motion-press', 4);
      expect(
        _boundsDistance(reducedRest, _presentationBounds(tester)),
        lessThan(.1),
      );
      await capture('reduced-motion-pressed', settle: false);
      await still.cancel();
      await _frames(tester);
      interactions['reducedMotionNoGeometry'] = true;

      // Two shapes participate in the real group SDF, then separate again.
      harness.configure(brightness: Brightness.light, blendDemo: true);
      await capture('blend-near');
      harness.setBlendNear(false);
      await capture('blend-separated');
      interactions['realBlendGroup'] = true;

      // Exercise the same navigation, menu and exit control used by app pages.
      harness.configure(brightness: Brightness.light, productionDemo: true);
      await _frames(tester);
      Finder indicator() => find.descendant(
        of: find.descendant(
          of: find.byKey(_tabsKey),
          matching: find.byType(liquid.SpringBuilder),
        ),
        matching: find.byType(DecoratedBox),
      );
      final navStart = tester.getRect(indicator());
      final navigationSamples = <Map<String, dynamic>>[];
      await tester.tap(find.text('Settings'));
      await tester.pump();
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final rect = tester.getRect(indicator());
        navigationSamples.add({
          'frame': frame,
          'left': rect.left,
          'width': rect.width,
        });
      }
      expect(tester.getRect(indicator()).left, greaterThan(navStart.left));
      await capture('navigation-travel', settle: false);
      final beforeRedirect = tester.getRect(indicator());
      await tester.tap(find.text('Files'));
      await tester.pump();
      expect(
        tester.getRect(indicator()).left,
        closeTo(beforeRedirect.left, beforeRedirect.width * .1),
      );
      harness.setReducedMotion(true);
      await tester.pump();
      final filesTarget = tester.getRect(
        find.ancestor(
          of: find.text('Files'),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(tester.getRect(indicator()).left, closeTo(filesTarget.left, .1));
      interactions['navigationRedirectAndReducedMotion'] = true;
      interactions['navigationSamples'] = navigationSamples;
      harness.setReducedMotion(false);
      await _frames(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(_menuKey),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Device details'), findsOneWidget);
      await capture('menu-open');
      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.tapAt(Offset(5, viewport.height - 5));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Device details'), findsNothing);
      expect(harness.menuCount, 0);
      await capture('menu-cancelled');
      await tester.tap(
        find.descendant(
          of: find.byKey(_menuKey),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.text('Device details'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(harness.menuCount, 1);
      interactions['productionMenuOpenCancelAction'] = true;
      harness.setReducedMotion(true);
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byKey(_menuKey),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Device details'), findsOneWidget);
      final reducedMenuBounds = tester.getRect(find.byType(MenuItemButton));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(find.byType(MenuItemButton)), reducedMenuBounds);
      interactions['reducedMenuBounds'] = [
        reducedMenuBounds.left,
        reducedMenuBounds.top,
        reducedMenuBounds.width,
        reducedMenuBounds.height,
      ];
      await tester.tapAt(Offset(5, viewport.height - 5));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Device details'), findsNothing);
      expect(harness.menuCount, 1);
      interactions['productionMenuReducedMotion'] = true;
      harness.setReducedMotion(false);
      await _frames(tester);
      final exit = find.descendant(
        of: find.byType(ExitHandle),
        matching: find.byType(GlassPressFeedback),
      );
      expect(tester.getSize(exit), const Size(52, 52));
      final exitPress = await tester.startGesture(tester.getCenter(exit));
      await tester.pump(const Duration(milliseconds: 64));
      await capture('exit-held', settle: false);
      await exitPress.cancel();
      await _frames(tester);
      expect(harness.exitCount, 0);
      await capture('exit-recovered');
      await tester.tap(exit);
      await _frames(tester);
      expect(harness.exitCount, 1);
      interactions['actualExitHandleFeedbackCancelTap'] = true;

      for (final photo in [
        ('regular-photo', _regularPhotoPath, false),
        ('clear-photo', _clearPhotoPath, true),
      ]) {
        final receipt = await tester.runAsync(() => _loadPhoto(photo.$2));
        expect(receipt, isNotNull);
        (report['photoSources'] as Map<String, dynamic>)[photo.$1] = receipt;
        harness.configure(
          brightness: Brightness.light,
          media: photo.$3,
          photoPath: photo.$2,
        );
        await _frames(tester);
        expect(find.byType(Image), findsOneWidget);
        await capture(photo.$1);
      }

      report['samplingBounds'] = GlassMaterial.samplingBounds;
      report['dynamicCaptureComplete'] = true;
      report['performanceCaptureComplete'] = true;
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
Map<String, Object> _opticsReceipt(
  Brightness brightness,
  GlassVariant variant,
) {
  final settings = Glass.optics(brightness: brightness, variant: variant);
  return {
    'bodyMode': settings.bodyMode.name,
    'blurSigmaLogicalPx': settings.blur,
    'thicknessLogicalPx': settings.thickness,
    'refractiveIndex': settings.refractiveIndex,
    'chromaticAberration': settings.chromaticAberration,
    'glassColorArgb': settings.glassColor
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0'),
  };
}

Future<Map<String, Object>> _loadPhoto(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw StateError(
      'Push the repository photograph to $path before the GPU run.',
    );
  }
  final bytes = await file.length();
  final stream = FileImage(file).resolve(const ImageConfiguration());
  final completed = Completer<ImageInfo>();
  final listener = ImageStreamListener(
    (info, synchronousCall) {
      if (!completed.isCompleted) completed.complete(info);
    },
    onError: (Object error, StackTrace? stack) {
      if (!completed.isCompleted) completed.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  try {
    final info = await completed.future.timeout(const Duration(seconds: 15));
    final receipt = <String, Object>{
      'path': path,
      'bytes': bytes,
      'decodedWidth': info.image.width,
      'decodedHeight': info.image.height,
      'imageStreamComplete': true,
    };
    info.dispose();
    return receipt;
  } finally {
    stream.removeListener(listener);
  }
}

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

// Route test pointers through the real event path, avoiding the live-test
// binding's painted crosshairs. Semantics and hit testing remain real.
class _CleanGlassBinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  void handlePointerEvent(PointerEvent event) {
    final previous = shouldPropagateDevicePointerEvents;
    shouldPropagateDevicePointerEvents = true;
    try {
      withPointerEventSource(
        TestBindingEventSource.device,
        () => super.handlePointerEvent(event),
      );
    } finally {
      shouldPropagateDevicePointerEvents = previous;
    }
  }
}

List<double> _presentationBounds(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(find.byIcon(Icons.close));
  final rect = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  return [rect.left, rect.top, rect.width, rect.height];
}

double _boundsDistance(List<double> a, List<double> b) => List.generate(
  4,
  (i) => (a[i] - b[i]).abs(),
).reduce((x, y) => x > y ? x : y);

class _GlassHarness extends StatefulWidget {
  const _GlassHarness({super.key});

  @override
  State<_GlassHarness> createState() => _GlassHarnessState();
}

class _GlassHarnessState extends State<_GlassHarness>
    with SingleTickerProviderStateMixin {
  late final backgroundMotion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  int backgroundPaints = 0;
  bool reduceMotion = false;
  bool blendDemo = false;
  bool productionDemo = false;
  int menuCount = 0;
  int exitCount = 0;
  void setReducedMotion(bool value) => setState(() => reduceMotion = value);
  bool blendNear = true;
  void startBackgroundMotion() => backgroundMotion.repeat();
  void stopBackgroundMotion() => backgroundMotion.stop();
  void setBlendNear(bool value) => setState(() {
    blendNear = value;
  });
  final scroll = ScrollController();
  Brightness brightness = Brightness.light;
  bool media = false;
  String? photoPath;
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
    bool reduceMotion = false,
    bool blendDemo = false,
    bool productionDemo = false,
    String? photoPath,
  }) {
    scroll.jumpTo(0);
    setState(() {
      this.brightness = brightness;
      this.media = media;
      this.reduceTransparency = reduceTransparency;
      this.reduceMotion = reduceMotion;
      this.blendDemo = blendDemo;
      this.productionDemo = productionDemo;
      this.photoPath = photoPath;
      blendNear = true;
      selectedIndex = 0;
    });
  }

  @override
  void dispose() {
    backgroundMotion.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassMaterial.wrap(
    child: TooltipVisibility(
      visible: false,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ConnectTokens.theme(brightness),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: GlassPreferences(
          reduceTransparency: reduceTransparency,
          child: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                final mediaColor = media ? Colors.white : null;
                final variant = media
                    ? GlassVariant.clear
                    : GlassVariant.regular;
                final topControls = Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GlassIconButton(
                      key: _closeKey,
                      icon: Icon(Icons.close, color: mediaColor),
                      semanticLabel: 'Close test control',
                      onPressed: () => setState(() => closeCount++),

                      size: DesignTokens.componentIconButtonSize,
                      iconSize: DesignTokens.componentIconSize,
                      quality: GlassMaterial.quality(context),
                      settings: GlassMaterial.settings(
                        context,
                        variant: variant,
                      ),
                      useOwnLayer: true,
                      interactionScale: GlassMaterial.reduceMotion(context)
                          ? 1
                          : DesignTokens.componentGlassInteractionScale,
                      anchorStretch: !GlassMaterial.reduceMotion(context),
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
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    SingleChildScrollView(
                      controller: scroll,
                      physics: const ClampingScrollPhysics(),
                      child: AnimatedBuilder(
                        animation: backgroundMotion,
                        builder: (context, _) => photoPath != null
                            ? Image.file(
                                File(photoPath!),
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                                fit: BoxFit.cover,
                              )
                            : CustomPaint(
                                size: Size(
                                  constraints.maxWidth,
                                  constraints.maxHeight * 3,
                                ),
                                painter: _BackdropPainter(
                                  dark: brightness == Brightness.dark,
                                  media: media,
                                  phase: backgroundMotion.value,
                                  onPaint: () => backgroundPaints++,
                                ),
                              ),
                      ),
                    ),
                    if (media)
                      Positioned(
                        left: 0,
                        top: 0,
                        right: 0,
                        child: MediaControlsProtection(
                          child: SafeArea(
                            bottom: false,
                            minimum: const EdgeInsets.all(20),
                            child: GlassSurfaceGroup(
                              variant: GlassVariant.clear,
                              child: topControls,
                            ),
                          ),
                        ),
                      ),
                    if (!media)
                      GlassSurfaceGroup(
                        variant: variant,
                        child: SafeArea(
                          minimum: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              topControls,
                              Expanded(
                                child: Center(
                                  child: media
                                      ? const SizedBox.shrink()
                                      : blendDemo
                                      ? SizedBox(
                                          key: _panelKey,
                                          width: 280,
                                          height: 120,
                                          child: GlassSurfaceGroup(
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                const Positioned(
                                                  left: 20,
                                                  top: 12,
                                                  child: SizedBox(
                                                    width: 96,
                                                    height: 96,
                                                    child: Glass(
                                                      radius: 48,
                                                      child: Center(
                                                        child: Icon(
                                                          Icons.circle_outlined,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  left: blendNear ? 110 : 160,
                                                  top: 12,
                                                  child: const SizedBox(
                                                    width: 96,
                                                    height: 96,
                                                    child: Glass(
                                                      radius: 48,
                                                      child: Center(
                                                        child: Icon(Icons.add),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
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
                                                if (productionDemo)
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: GlassMenuButton(
                                                      key: _menuKey,
                                                      icon: const Icon(
                                                        Icons.more_horiz,
                                                      ),
                                                      tooltip: 'Device actions',
                                                      actions: [
                                                        GlassMenuAction(
                                                          label:
                                                              'Device details',
                                                          onPressed: () =>
                                                              setState(
                                                                () =>
                                                                    menuCount++,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              if (!media)
                                GlassTabBar.bottom(
                                  key: _tabsKey,
                                  tabs: const [
                                    GlassTab(
                                      icon: Icon(Icons.devices),
                                      label: 'Devices',
                                    ),
                                    GlassTab(
                                      icon: Icon(Icons.folder),
                                      label: 'Files',
                                    ),
                                    GlassTab(
                                      icon: Icon(Icons.settings),
                                      label: 'Settings',
                                    ),
                                  ],
                                  selectedIndex: selectedIndex,
                                  onTabSelected: (index) => setState(() {
                                    selectedIndex = index;
                                    tabCount++;
                                  }),

                                  horizontalPadding: 0,
                                  verticalPadding: 0,
                                  barHeight: GlassMaterial.navigationHeight(
                                    context,
                                  ),
                                  barBorderRadius:
                                      DesignTokens.componentNavigationRounded,
                                  tabPadding: const EdgeInsets.symmetric(
                                    horizontal:
                                        DesignTokens.componentNavigationPadding,
                                  ),
                                  iconLabelSpacing: DesignTokens.spacingMicro,
                                  iconSize: DesignTokens.componentIconSize,
                                  labelFontSize: Theme.of(context)
                                      .textTheme
                                      .labelLarge!
                                      .fontSize!,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .labelLarge,
                                  selectedIconColor: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  selectedLabelColor: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  unselectedIconColor: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  unselectedLabelColor: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  indicatorColor: GlassMaterial.opaque(context)
                                      ? Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHigh
                                      : Theme.of(context).brightness ==
                                            Brightness.dark
                                      ? DesignTokens.colorGlassSelectedDark
                                      : DesignTokens.colorGlassSelected,
                                  settings: GlassMaterial.settings(context),
                                  quality: GlassMaterial.quality(context),
                                  indicatorSettings:
                                      GlassMaterial.opaque(context)
                                      ? GlassMaterial.settings(context)
                                            .copyWith(
                                              glassColor:
                                                  DesignTokens.colorTransparent,
                                            )
                                      : null,
                                  pressScale:
                                      GlassMaterial.reduceMotion(context)
                                      ? 1
                                      : DesignTokens
                                            .componentGlassInteractionScale,
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (productionDemo)
                      ExitHandle(
                        deviceLabel: 'GPU test device',
                        onExit: () => setState(() => exitCount++),
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
                                                markerCode &
                                                        (1 << (15 - bit)) ==
                                                    0
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
      ),
    ),
  );
}

// Deliberately diagnostic artwork, never a product asset or screen.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({
    required this.dark,
    required this.media,
    this.phase = 0,
    this.onPaint,
  });
  final double phase;
  final VoidCallback? onPaint;
  final bool dark;
  final bool media;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint?.call();
    final paint = Paint();
    canvas.drawColor(
      media
          ? (dark ? const Color(0xFF132031) : const Color(0xFFF0DEAE))
          : (dark ? const Color(0xFF222222) : const Color(0xFFF4F4F4)),
      BlendMode.src,
    );
    canvas.translate(0, -phase * 96);
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
      oldDelegate.dark != dark ||
      oldDelegate.media != media ||
      oldDelegate.phase != phase;
}
