import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// Public renderer diagnostics; the exercised controls use production configuration.
// ignore: depend_on_referenced_packages
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

const _bar = ValueKey('components-bar');
const _icon = ValueKey('components-icon');
const _tooltip = ValueKey('components-tooltip');
const _stamp = ValueKey('components-stamp');

/// Finite Android GPU captures, without a benchmark or perceptual verdict.
void main() {
  final binding = _ComponentsBinding()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('official production glass components render and select', (
    tester,
  ) async {
    final report = <String, dynamic>{
      'schemaVersion': 1,
      'scope': 'production-glass-components',
      'platform': Platform.operatingSystem,
      'buildMode': kProfileMode ? 'profile' : 'debug',
      'backend': GlassMaterial.backend,
      'backendVersion': GlassMaterial.backendVersion,
      'shaderSupported': ui.ImageFilter.isShaderFilterSupported,
      'visualReviewRequired': true,
      'visualAcceptanceComplete': false,
      'performanceMeasured': false,
      'background': 'painted-lines-and-color-blocks',
      'scenes': <Map<String, dynamic>>[],
      'dragResults': <Map<String, dynamic>>[],
    };
    binding.reportData = report;
    expect(Platform.isAndroid, isTrue);
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
    await tester.runAsync(GlassMaterial.initialize);
    report['shaderLoaded'] = GlassMaterial.isInitialized;
    expect(GlassMaterial.isInitialized, isTrue);
    final key = GlobalKey<_ComponentsHarnessState>();
    final fatal = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    try {
      await tester.pumpWidget(_ComponentsHarness(key: key));
      await _settle(tester);
      expect(find.byType(liquid.LightweightLiquidGlass), findsNothing);
      expect(find.byType(liquid.LiquidGlassLayer), findsWidgets);
      report['nativeWarmup'] = _renderer();
      await binding.convertFlutterSurfaceToImage();
      await _settle(tester);
      final state = key.currentState!;
      final scenes = report['scenes'] as List<Map<String, dynamic>>;

      Future<void> capture(String name) async {
        final marker = 0xc500 | (scenes.length + 1);
        state.setMarker(marker);
        await _raster(tester);
        await binding.callbackManager.takeScreenshot('$name-drain');
        await _raster(tester);
        final renderer = _renderer();
        expect(renderer['liteCount'], 0);
        expect(renderer['blurCount'], 0);
        if (state.opaque) {
          expect(renderer['nativeCount'], 0);
          expect(renderer['layerCount'], 0);
        } else {
          expect(renderer['nativeCount'], greaterThan(0));
          expect(renderer['layerCount'], greaterThan(0));
        }
        final indicators = tester
            .widgetList<liquid.AnimatedGlassIndicator>(
              find.byType(liquid.AnimatedGlassIndicator),
            )
            .map(
              (indicator) => <String, dynamic>{
                'thickness': indicator.thickness,
                'paintGlass': indicator.paintGlass,
                'backgroundPass': indicator.isBackgroundIndicator,
                'alignmentX': indicator.alignment.resolve(TextDirection.ltr).x,
              },
            )
            .toList();
        if (name.endsWith('-held') || name.endsWith('-dragged')) {
          if (name.startsWith('tab-')) {
            expect(
              indicators.any(
                (indicator) =>
                    indicator['paintGlass'] == true &&
                    indicator['backgroundPass'] == false &&
                    (indicator['thickness'] as double) > 0,
              ),
              isTrue,
              reason: 'Holding the production tab must mount its active lens.',
            );
          }
        }
        if (name.startsWith('dialog-') || name.startsWith('tooltip-')) {
          expect(renderer['cardCount'], 1);
        }
        expect(tester.takeException(), isNull);
        final bytes = await binding.takeScreenshot(name);
        scenes.add({
          'name': name,
          'markerCode': marker,
          'markerBounds': _rect(tester.getRect(find.byKey(_stamp))),
          'brightness': state.brightness.name,
          'reduceTransparency': state.opaque,
          'selectedIndex': state.selected,
          'selectionCount': state.selections.length,
          'renderer': renderer,
          'indicators': indicators,
          'sha256': sha256.convert(bytes).toString(),
          'bytes': bytes.length,
          'physicalWidth': tester.view.physicalSize.width,
          'physicalHeight': tester.view.physicalSize.height,
          'dpr': tester.view.devicePixelRatio,
        });
      }

      for (final brightness in Brightness.values.reversed) {
        state.configure(brightness: brightness);
        await _settle(tester);
        final suffix = brightness.name;
        expect(find.byType(liquid.GlassTabBar), findsOneWidget);
        await capture('tab-$suffix-rest');
        final rect = tester.getRect(find.byKey(_bar));
        final first = Offset(rect.left + rect.width / 6, rect.center.dy);
        final last = Offset(rect.right - rect.width / 6, rect.center.dy);
        final gesture = await tester.startGesture(first);
        await _settle(tester);
        await capture('tab-$suffix-held');
        for (var step = 1; step <= 8; step++) {
          await gesture.moveTo(Offset.lerp(first, last, step / 8)!);
          await tester.pump(const Duration(milliseconds: 32));
        }
        await _settle(tester);
        await capture('tab-$suffix-dragged');
        await gesture.up();
        await _settle(tester);
        expect(state.selected, 2);
        expect(state.selections.last, 2);
        (report['dragResults'] as List<Map<String, dynamic>>).add({
          'brightness': suffix,
          'from': 0,
          'to': state.selected,
          'selectionCallbacks': state.selections.toList(),
        });
      }

      state.configure(brightness: Brightness.light);
      await _settle(tester);
      await tester.tap(find.text('打开对话框'));
      await _settle(tester);
      expect(find.byType(GlassAlertDialog), findsOneWidget);
      await capture('dialog-light');
      await tester.tap(find.text('关闭对话框'));
      await _settle(tester);
      final tooltip = tester.state<TooltipState>(
        find.descendant(
          of: find.byKey(_tooltip),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.ensureTooltipVisible(), isTrue);
      await _settle(tester);
      expect(find.text('官方玻璃提示', findRichText: true), findsWidgets);
      await capture('tooltip-light');
      Tooltip.dismissAllToolTips();
      await _settle(tester);
      final iconPress = await tester.startGesture(
        tester.getCenter(find.byKey(_icon)),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(liquid.GlassIconButton), findsOneWidget);
      await capture('icon-held');
      await iconPress.cancel();
      await _settle(tester);
      expect(state.iconActivations, 0);
      for (final brightness in Brightness.values.reversed) {
        state.configure(brightness: brightness, opaque: true);
        await _settle(tester);
        await capture('opaque-${brightness.name}');
      }
      report['iconActivations'] = state.iconActivations;
      report['harnessComplete'] = true;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      WidgetController.hitTestWarningShouldBeFatal = fatal;
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Map<String, int> _renderer() => {
  // AdaptiveGlass also wraps the opaque minimal path. Exclude those wrappers;
  // layerCount separately verifies that premium optical layers are mounted.
  'nativeCount': find
      .byWidgetPredicate(
        (widget) =>
            widget is liquid.AdaptiveGlass &&
            widget.quality == liquid.GlassQuality.premium,
      )
      .evaluate()
      .length,
  'layerCount': find.byType(liquid.LiquidGlassLayer).evaluate().length,
  'liteCount': find.byType(liquid.LightweightLiquidGlass).evaluate().length,
  'blurCount': find.byType(BackdropFilter).evaluate().length,
  'cardCount': find.byType(liquid.GlassCard).evaluate().length,
};

List<double> _rect(Rect rect) => [rect.left, rect.top, rect.width, rect.height];

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _raster(WidgetTester tester) async {
  final complete = Completer<void>();
  final start = DateTime.now().microsecondsSinceEpoch;
  void timing(List<ui.FrameTiming> frames) {
    if (!complete.isCompleted &&
        frames.any(
          (frame) =>
              frame.timestampInMicroseconds(
                ui.FramePhase.rasterFinishWallTime,
              ) >=
              start,
        )) {
      complete.complete();
    }
  }

  tester.binding.addTimingsCallback(timing);
  try {
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.runAsync(() async {
      await complete.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  } finally {
    tester.binding.removeTimingsCallback(timing);
  }
}

class _ComponentsBinding extends IntegrationTestWidgetsFlutterBinding {
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

class _ComponentsHarness extends StatefulWidget {
  const _ComponentsHarness({super.key});
  @override
  State<_ComponentsHarness> createState() => _ComponentsHarnessState();
}

class _ComponentsHarnessState extends State<_ComponentsHarness> {
  Brightness brightness = Brightness.light;
  bool opaque = false;
  int selected = 0;
  int marker = 0;
  int iconActivations = 0;
  final selections = <int>[];

  void configure({required Brightness brightness, bool opaque = false}) =>
      setState(() {
        this.brightness = brightness;
        this.opaque = opaque;
        selected = 0;
        selections.clear();
      });
  void setMarker(int code) => setState(() => marker = code);

  @override
  Widget build(BuildContext context) => GlassMaterial.wrap(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: Duration.zero,
      theme: ConnectTokens.theme(brightness),
      builder: (context, child) => GlassPreferences(
        reduceTransparency: opaque,
        child: Stack(
          children: [
            child!,
            Positioned(
              left: 8,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 4,
              child: IgnorePointer(
                child: SizedBox(
                  key: _stamp,
                  width: 128,
                  height: 8,
                  child: CustomPaint(painter: _Stamp(marker)),
                ),
              ),
            ),
          ],
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _Background(brightness)),
              ),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    const Text('Production glass · Aa 0123456789'),
                    const SizedBox(height: 24),
                    TooltipVisibility(
                      visible: false,
                      child: GlassIconButton(
                        key: _icon,
                        semanticLabel: '添加',
                        icon: const Icon(Icons.add),
                        onPressed: () => iconActivations++,

                        size: DesignTokens.componentIconButtonSize,
                        iconSize: DesignTokens.componentIconSize,
                        quality: GlassMaterial.quality(context),
                        settings: GlassMaterial.settings(
                          context,
                          variant: GlassVariant.regular,
                        ),
                        useOwnLayer: true,
                        interactionScale: GlassMaterial.reduceMotion(context)
                            ? 1
                            : DesignTokens.componentGlassInteractionScale,
                        anchorStretch: !GlassMaterial.reduceMotion(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const GlassTooltip(
                      key: _tooltip,
                      message: '官方玻璃提示',
                      triggerMode: TooltipTriggerMode.manual,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.info),
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(
                        showGlassDialog<void>(
                          context: context,
                          builder: (context) => GlassAlertDialog(
                            title: const Text('官方玻璃对话框'),
                            content: const Text('背景细线与色块用于检查透入内容和边缘。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭对话框'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      child: const Text('打开对话框'),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      child: GlassTabBar.bottom(
                        key: _bar,
                        tabs: const [
                          GlassTab(icon: Icon(Icons.devices), label: '设备'),
                          GlassTab(icon: Icon(Icons.swap_vert), label: '传输'),
                          GlassTab(icon: Icon(Icons.settings), label: '设置'),
                        ],
                        selectedIndex: selected,
                        onTabSelected: (index) => setState(() {
                          selected = index;
                          selections.add(index);
                        }),

                        horizontalPadding: 0,
                        verticalPadding: 0,
                        barHeight: GlassMaterial.navigationHeight(context),
                        barBorderRadius:
                            DesignTokens.componentNavigationRounded,
                        tabPadding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.componentNavigationPadding,
                        ),
                        iconLabelSpacing: DesignTokens.spacingMicro,
                        iconSize: DesignTokens.componentIconSize,
                        labelFontSize: Theme.of(context)
                            .textTheme
                            .labelLarge!
                            .fontSize!,
                        textStyle: Theme.of(context).textTheme.labelLarge,
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
                            ? Theme.of(context).colorScheme.surfaceContainerHigh
                            : Theme.of(context).brightness == Brightness.dark
                            ? DesignTokens.colorGlassSelectedDark
                            : DesignTokens.colorGlassSelected,
                        settings: GlassMaterial.settings(context),
                        quality: GlassMaterial.quality(context),
                        indicatorSettings: GlassMaterial.opaque(context)
                            ? GlassMaterial.settings(context).copyWith(
                                glassColor: DesignTokens.colorTransparent,
                              )
                            : null,
                        pressScale: GlassMaterial.reduceMotion(context)
                            ? 1
                            : DesignTokens.componentGlassInteractionScale,
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
  );
}

class _Background extends CustomPainter {
  const _Background(this.brightness);
  final Brightness brightness;
  @override
  void paint(Canvas canvas, Size size) {
    final dark = brightness == Brightness.dark;
    canvas.drawColor(
      dark ? const Color(0xff14181e) : const Color(0xfff4f5f7),
      BlendMode.src,
    );
    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple];
    for (var i = 0; i < 12; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          (i % 3) * size.width / 3,
          i * size.height / 12,
          size.width / 3,
          size.height / 12,
        ),
        Paint()
          ..color = colors[i % colors.length].withValues(
            alpha: dark ? .45 : .3,
          ),
      );
    }
    final pen = Paint()..color = dark ? Colors.white54 : Colors.black54;
    for (var x = 0.0; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
    }
    for (var y = 0.0; y < size.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pen);
    }
  }

  @override
  bool shouldRepaint(_Background oldDelegate) =>
      oldDelegate.brightness != brightness;
}

class _Stamp extends CustomPainter {
  const _Stamp(this.code);
  final int code;
  @override
  void paint(Canvas canvas, Size size) {
    for (var bit = 0; bit < 16; bit++) {
      canvas.drawRect(
        Rect.fromLTWH(bit * size.width / 16, 0, size.width / 16, size.height),
        Paint()
          ..color = code & (1 << (15 - bit)) != 0 ? Colors.white : Colors.black,
      );
    }
  }

  @override
  bool shouldRepaint(_Stamp oldDelegate) => oldDelegate.code != code;
}
